#import "SimCamSampleBufferDriver.h"
#import "SimCamSharedFrameReader.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <sys/mman.h>
#import <fcntl.h>
#import <unistd.h>

static NSString * const kSimCamSharedPath = @"/tmp/SimCam.bgra";
static const double kSimCamDataOutputFPS = 30.0;

// Header layout mirrors SimCamSharedFrameReader (24-byte LE header + BGRA).
static const size_t kSBHeaderSize = 24;
static const size_t kSBMaxCanvas  = 1280;
static const size_t kSBBufferSize = kSBHeaderSize + kSBMaxCanvas * kSBMaxCanvas * 4;

@implementation SimCamSampleBufferDriver {
    __weak AVCaptureOutput *_output;
    __weak id<AVCaptureVideoDataOutputSampleBufferDelegate> _delegate;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    int _fd;
    void *_buffer;
    CVPixelBufferPoolRef _pool;
    size_t _poolWidth;
    size_t _poolHeight;
}

- (instancetype)initWithOutput:(AVCaptureOutput *)output
                      delegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                         queue:(dispatch_queue_t)queue {
    if ((self = [super init])) {
        _output = output;
        _delegate = delegate;
        _queue = queue;
        _fd = -1;
        _buffer = NULL;
        _pool = NULL;
        _poolWidth = 0;
        _poolHeight = 0;
    }
    return self;
}

- (void)dealloc {
    [self stop];
    if (_buffer != NULL) { munmap(_buffer, kSBBufferSize); _buffer = NULL; }
    if (_fd >= 0) { close(_fd); _fd = -1; }
    if (_pool != NULL) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
}

- (void)start {
    if (_timer != nil || _queue == nil) return;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    uint64_t interval = (uint64_t)(NSEC_PER_SEC / kSimCamDataOutputFPS);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              interval, interval / 10);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{ [weakSelf tick]; });
    dispatch_resume(_timer);
    NSLog(@"[SimCamInject] sample-buffer driver started for %@", _output);
}

- (void)stop {
    if (_timer != nil) {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }
}

- (BOOL)openIfNeeded {
    if (_buffer != NULL) return YES;
    int fd = open(kSimCamSharedPath.UTF8String, O_RDONLY);
    if (fd < 0) return NO;
    void *map = mmap(NULL, kSBBufferSize, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) { close(fd); return NO; }
    _fd = fd;
    _buffer = map;
    return YES;
}

- (void)tick {
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = _delegate;
    AVCaptureOutput *output = _output;
    if (delegate == nil || output == nil) { [self stop]; return; }
    if (![self openIfNeeded]) return;

    uint32_t sequence = 0, width = 0, height = 0, flags = 0;
    memcpy(&sequence, _buffer, 4);
    memcpy(&width,  (uint8_t *)_buffer + 8,  4);
    memcpy(&height, (uint8_t *)_buffer + 12, 4);
    memcpy(&flags,  (uint8_t *)_buffer + 16, 4);
    // Nothing streamed yet, or a torn/invalid header — deliver no frame (the
    // app just sees a still/blank preview, same as an idle camera).
    if (sequence == 0) return;
    if (width == 0 || height == 0 || width > kSBMaxCanvas || height > kSBMaxCanvas) return;

    CVPixelBufferRef pixelBuffer =
            [self pixelBufferOfWidth:width height:height mirror:(flags & kSimCamFlagMirror) != 0];
    if (pixelBuffer == NULL) return;

    CMSampleBufferRef sampleBuffer = [self sampleBufferWithPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
    if (sampleBuffer == NULL) return;

    AVCaptureConnection *connection = nil;
    if ([output respondsToSelector:@selector(connectionWithMediaType:)]) {
        connection = [output connectionWithMediaType:AVMediaTypeVideo];
    }
    if (connection == nil) connection = output.connections.firstObject;

    if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
    CFRelease(sampleBuffer);
}

/// Copies the current shared frame into a fresh, IOSurface-backed BGRA
/// `CVPixelBuffer`. IOSurface backing is required for apps that turn the buffer
/// into a Metal/GL texture (Flutter, RN-vision-camera). The pool is recreated
/// only when the frame dimensions change.
- (CVPixelBufferRef)pixelBufferOfWidth:(uint32_t)width height:(uint32_t)height mirror:(BOOL)mirror CF_RETURNS_RETAINED {
    if (_pool == NULL || _poolWidth != width || _poolHeight != height) {
        if (_pool != NULL) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
        NSDictionary *attrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
            // Required so consumers can wrap the buffer in a Metal/GL texture —
            // Flutter (and RN-vision-camera) render the preview that way. Without
            // it, frames still reach the sample-buffer delegate (so scanning/Vision
            // work) but the on-screen texture stays blank.
            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
            (id)kCVPixelBufferOpenGLESCompatibilityKey: @YES,
        };
        if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL,
                (__bridge CFDictionaryRef)attrs, &_pool) != kCVReturnSuccess) {
            _pool = NULL;
            return NULL;
        }
        _poolWidth = width;
        _poolHeight = height;
    }

    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &pb) != kCVReturnSuccess) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *dst = (uint8_t *)CVPixelBufferGetBaseAddress(pb);
    size_t dstStride = CVPixelBufferGetBytesPerRow(pb);
    const uint8_t *src = (const uint8_t *)_buffer + kSBHeaderSize;
    size_t srcStride = (size_t)width * 4;

    for (size_t y = 0; y < height; y++) {
        const uint8_t *srcRow = src + y * srcStride;
        uint8_t *dstRow = dst + y * dstStride;
        if (!mirror) {
            memcpy(dstRow, srcRow, srcStride);
        } else {
            // Horizontal flip so the front-camera "selfie" feel matches the
            // preview/photo paths, which also honor the mirror flag.
            for (size_t x = 0; x < width; x++) {
                memcpy(dstRow + x * 4, srcRow + (width - 1 - x) * 4, 4);
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

- (CMSampleBufferRef)sampleBufferWithPixelBuffer:(CVPixelBufferRef)pixelBuffer CF_RETURNS_RETAINED {
    CMVideoFormatDescriptionRef format = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(
            kCFAllocatorDefault, pixelBuffer, &format) != noErr) {
        return NULL;
    }

    CMSampleTimingInfo timing;
    timing.duration = CMTimeMake(1, (int32_t)kSimCamDataOutputFPS);
    timing.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000);
    timing.decodeTimeStamp = kCMTimeInvalid;

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus status = CMSampleBufferCreateForImageBuffer(
            kCFAllocatorDefault, pixelBuffer, YES, NULL, NULL,
            format, &timing, &sampleBuffer);
    CFRelease(format);
    if (status != noErr) return NULL;
    return sampleBuffer;
}

@end
