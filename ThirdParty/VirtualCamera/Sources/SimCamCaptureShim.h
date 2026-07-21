#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Makes the iOS Simulator behave as if a real camera device were present.
///
/// The simulator vends NO `AVCaptureDevice` (`+defaultDeviceWithMediaType:`
/// returns nil, discovery is empty), so apps that build an `AVCaptureSession`
/// from an `AVCaptureDeviceInput` — Flutter's `camera`, react-native-vision-
/// camera, most production camera/scanner apps — bail with "no camera" before
/// they ever set a sample-buffer delegate. Painting the preview layer can't help
/// those apps because they never get that far.
///
/// This shim swizzles the `AVCaptureDevice` discovery/authorization class
/// methods to vend a synthetic front camera, and makes `AVCaptureSession`
/// permissive enough to accept the synthetic input and "start" without a real
/// capture backend. Frames are then delivered by SimCamSampleBufferDriver
/// (hooked on `AVCaptureVideoDataOutput`) and/or the preview-layer driver.
void SimCamInstallCaptureShim(void);

NS_ASSUME_NONNULL_END
