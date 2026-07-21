#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Feeds the shared-memory BGRA frames into an app's
/// `AVCaptureVideoDataOutput` sample-buffer delegate — the frame path used by
/// Flutter (`camera`), react-native-vision-camera, barcode/ML/document
/// scanners, and anything that reads `CMSampleBuffer`s instead of putting an
/// `AVCaptureVideoPreviewLayer` on screen. This is what makes MockMyCam work on
/// iOS 26 apps that render the camera through a Metal/GL texture rather than a
/// preview layer.
///
/// One driver per hooked output. It runs a timer on the delegate's own callback
/// queue, reads `/tmp/SimCam.bgra`, wraps each frame in an IOSurface-backed
/// `CMSampleBuffer`, and invokes
/// `captureOutput:didOutputSampleBuffer:fromConnection:`.
@interface SimCamSampleBufferDriver : NSObject

- (instancetype)initWithOutput:(AVCaptureOutput *)output
                      delegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                         queue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
