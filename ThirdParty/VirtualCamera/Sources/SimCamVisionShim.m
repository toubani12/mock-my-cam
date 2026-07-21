#import "SimCamVisionShim.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// The CIImage each VNImageRequestHandler was created from, stashed at init time
// so performRequests: can re-detect with CIDetector.
static const void *kSimCamVisionImageKey = &kSimCamVisionImageKey;

static CIContext *gCIContext;
static CIDetector *gQRDetector;

#pragma mark - Synthetic barcode observation

/// A stand-in `VNBarcodeObservation`. Allocated with `class_createInstance`
/// (Vision's observations have no public initializer) and overrides only the
/// getters scanners read.
@interface SimCamFakeBarcode : VNBarcodeObservation {
@public
    NSString *_scPayload;
    CGRect _scBox;
}
@end

@implementation SimCamFakeBarcode
- (NSString *)payloadStringValue { return _scPayload; }
- (VNBarcodeSymbology)symbology { return VNBarcodeSymbologyQR; }
- (CGRect)boundingBox { return _scBox; }
- (VNConfidence)confidence { return 1.0f; }
- (CGPoint)topLeft { return CGPointMake(CGRectGetMinX(_scBox), CGRectGetMaxY(_scBox)); }
- (CGPoint)topRight { return CGPointMake(CGRectGetMaxX(_scBox), CGRectGetMaxY(_scBox)); }
- (CGPoint)bottomLeft { return CGPointMake(CGRectGetMinX(_scBox), CGRectGetMinY(_scBox)); }
- (CGPoint)bottomRight { return CGPointMake(CGRectGetMaxX(_scBox), CGRectGetMinY(_scBox)); }

// VNRequest copies observations when they're stored/read; the default
// VNObservation copy doesn't know about our ivars and would drop the payload.
// Carry it across the copy so scanners read the real value.
- (id)copyWithZone:(NSZone *)zone {
    SimCamFakeBarcode *c = (SimCamFakeBarcode *)class_createInstance([SimCamFakeBarcode class], 0);
    c->_scPayload = [_scPayload copy];
    c->_scBox = _scBox;
    return c;
}
@end

#pragma mark - Image stashing (VNImageRequestHandler init)

static void SimCamStashImage(id handler, CIImage *image) {
    if (handler && image) {
        objc_setAssociatedObject(handler, kSimCamVisionImageKey, image, OBJC_ASSOCIATION_RETAIN);
    }
}

static id (*orig_initPixelBuffer)(id, SEL, CVPixelBufferRef, NSDictionary *);
static id swz_initPixelBuffer(id self, SEL _cmd, CVPixelBufferRef pb, NSDictionary *opts) {
    id h = orig_initPixelBuffer(self, _cmd, pb, opts);
    if (pb) SimCamStashImage(h, [CIImage imageWithCVPixelBuffer:pb]);
    return h;
}

static id (*orig_initPixelBufferOrient)(id, SEL, CVPixelBufferRef, CGImagePropertyOrientation, NSDictionary *);
static id swz_initPixelBufferOrient(id self, SEL _cmd, CVPixelBufferRef pb, CGImagePropertyOrientation o, NSDictionary *opts) {
    id h = orig_initPixelBufferOrient(self, _cmd, pb, o, opts);
    if (pb) SimCamStashImage(h, [CIImage imageWithCVPixelBuffer:pb]);
    return h;
}

static id (*orig_initCGImage)(id, SEL, CGImageRef, NSDictionary *);
static id swz_initCGImage(id self, SEL _cmd, CGImageRef cg, NSDictionary *opts) {
    id h = orig_initCGImage(self, _cmd, cg, opts);
    if (cg) SimCamStashImage(h, [CIImage imageWithCGImage:cg]);
    return h;
}

static id (*orig_initCGImageOrient)(id, SEL, CGImageRef, CGImagePropertyOrientation, NSDictionary *);
static id swz_initCGImageOrient(id self, SEL _cmd, CGImageRef cg, CGImagePropertyOrientation o, NSDictionary *opts) {
    id h = orig_initCGImageOrient(self, _cmd, cg, o, opts);
    if (cg) SimCamStashImage(h, [CIImage imageWithCGImage:cg]);
    return h;
}

static id (*orig_initCIImage)(id, SEL, CIImage *, NSDictionary *);
static id swz_initCIImage(id self, SEL _cmd, CIImage *ci, NSDictionary *opts) {
    id h = orig_initCIImage(self, _cmd, ci, opts);
    SimCamStashImage(h, ci);
    return h;
}

static id (*orig_initCIImageOrient)(id, SEL, CIImage *, CGImagePropertyOrientation, NSDictionary *);
static id swz_initCIImageOrient(id self, SEL _cmd, CIImage *ci, CGImagePropertyOrientation o, NSDictionary *opts) {
    id h = orig_initCIImageOrient(self, _cmd, ci, o, opts);
    SimCamStashImage(h, ci);
    return h;
}

#pragma mark - performRequests: interception

static BOOL (*orig_performRequests)(id, SEL, NSArray *, NSError **);

// Our observations, stashed on the request. Vision's own results storage
// round-trips observations through NSSecureCoding, which drops our ivars, so we
// keep the originals here and return them from a hooked `results` getter.
static const void *kSimCamResultsKey = &kSimCamResultsKey;
static NSArray * (*orig_results)(id, SEL);
static NSArray *swz_results(id self, SEL _cmd) {
    NSArray *mine = objc_getAssociatedObject(self, kSimCamResultsKey);
    if (mine != nil) return mine;
    return orig_results ? orig_results(self, _cmd) : nil;
}

static BOOL SimCamRequestIsBarcode(VNRequest *r) {
    Class barcodeClass = NSClassFromString(@"VNDetectBarcodesRequest");
    return barcodeClass && [r isKindOfClass:barcodeClass];
}

static void SimCamDeliverResults(VNRequest *request, NSArray *observations) {
    objc_setAssociatedObject(request, kSimCamResultsKey, observations, OBJC_ASSOCIATION_RETAIN);
    @try {
        id handler = [request valueForKey:@"completionHandler"];
        if (handler) ((void (^)(VNRequest *, NSError *))handler)(request, nil);
    } @catch (__unused NSException *e) {}
}

static BOOL swz_performRequests(id self, SEL _cmd, NSArray<VNRequest *> *requests, NSError **error) {
    BOOL anyBarcode = NO;
    for (VNRequest *r in requests) { if (SimCamRequestIsBarcode(r)) { anyBarcode = YES; break; } }
    if (!anyBarcode) {
        return orig_performRequests(self, _cmd, requests, error);
    }

    CIImage *image = objc_getAssociatedObject(self, kSimCamVisionImageKey);
    if (image == nil) {
        // Nothing stashed — let Vision try (it will likely fail on the sim).
        return orig_performRequests(self, _cmd, requests, error);
    }

    NSArray *features = [gQRDetector featuresInImage:image] ?: @[];
    CGRect extent = image.extent;
    NSMutableArray *observations = [NSMutableArray array];
    for (CIQRCodeFeature *f in features) {
        if (f.messageString.length == 0) continue;
        SimCamFakeBarcode *obs = (SimCamFakeBarcode *)class_createInstance([SimCamFakeBarcode class], 0);
        obs->_scPayload = [f.messageString copy];
        // Normalize CIDetector's image-space bounds to Vision's 0..1,
        // bottom-left-origin coordinates.
        CGRect b = f.bounds;
        if (extent.size.width > 0 && extent.size.height > 0) {
            obs->_scBox = CGRectMake(b.origin.x / extent.size.width,
                                     b.origin.y / extent.size.height,
                                     b.size.width / extent.size.width,
                                     b.size.height / extent.size.height);
        } else {
            obs->_scBox = CGRectMake(0, 0, 1, 1);
        }
        [observations addObject:obs];
    }

    for (VNRequest *r in requests) {
        if (SimCamRequestIsBarcode(r)) SimCamDeliverResults(r, observations);
    }
    if (error) *error = nil;
    NSLog(@"[SimCamInject] Vision barcode request served via CIDetector (%lu found)",
          (unsigned long)observations.count);
    return YES;
}

#pragma mark - Install

static void SimCamHookInstance(Class cls, SEL sel, IMP newImp, void *origStore) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL) return;
    *(IMP *)origStore = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

void SimCamInstallVisionShim(void) {
    // Make sure Vision is loaded so its classes exist even if the app hasn't
    // touched it yet at constructor time.
    if (NSClassFromString(@"VNImageRequestHandler") == nil) {
        dlopen("/System/Library/Frameworks/Vision.framework/Vision", RTLD_LAZY);
    }
    Class handlerClass = NSClassFromString(@"VNImageRequestHandler");
    if (handlerClass == nil) {
        NSLog(@"[SimCamInject] Vision not present; skipping barcode shim");
        return;
    }

    gCIContext = [CIContext contextWithOptions:nil];
    gQRDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                     context:gCIContext
                                     options:@{ CIDetectorAccuracy: CIDetectorAccuracyHigh }];

    SimCamHookInstance(handlerClass, @selector(initWithCVPixelBuffer:options:),
                       (IMP)swz_initPixelBuffer, &orig_initPixelBuffer);
    SimCamHookInstance(handlerClass, @selector(initWithCVPixelBuffer:orientation:options:),
                       (IMP)swz_initPixelBufferOrient, &orig_initPixelBufferOrient);
    SimCamHookInstance(handlerClass, @selector(initWithCGImage:options:),
                       (IMP)swz_initCGImage, &orig_initCGImage);
    SimCamHookInstance(handlerClass, @selector(initWithCGImage:orientation:options:),
                       (IMP)swz_initCGImageOrient, &orig_initCGImageOrient);
    SimCamHookInstance(handlerClass, @selector(initWithCIImage:options:),
                       (IMP)swz_initCIImage, &orig_initCIImage);
    SimCamHookInstance(handlerClass, @selector(initWithCIImage:orientation:options:),
                       (IMP)swz_initCIImageOrient, &orig_initCIImageOrient);
    SimCamHookInstance(handlerClass, @selector(performRequests:error:),
                       (IMP)swz_performRequests, &orig_performRequests);

    // Return our stashed observations from VNRequest.results (base class covers
    // VNDetectBarcodesRequest and friends).
    Class requestClass = NSClassFromString(@"VNRequest");
    if (requestClass) {
        SimCamHookInstance(requestClass, @selector(results),
                           (IMP)swz_results, &orig_results);
    }

    NSLog(@"[SimCamInject] Vision barcode shim installed (CIDetector fallback)");
}
