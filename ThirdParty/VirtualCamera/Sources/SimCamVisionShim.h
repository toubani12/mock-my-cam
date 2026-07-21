#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Makes Vision barcode/QR detection work in the iOS Simulator.
///
/// On the iOS 26 simulator, `-[VNImageRequestHandler performRequests:error:]`
/// for a `VNDetectBarcodesRequest` fails with `Could not create inference
/// context` (Vision error 9) — the ML backend isn't available in the simulator.
/// Plugins built on Vision (Flutter's `mobile_scanner`, many QR/barcode
/// scanners) treat that as fatal and never start the camera, so the user just
/// sees a blank preview.
///
/// CoreImage's `CIDetector` QR reader DOES work in the simulator. This shim
/// swizzles `VNImageRequestHandler` so barcode requests are satisfied with
/// `CIDetector` results instead of failing — the app gets real QR payloads and
/// proceeds to run the camera normally.
void SimCamInstallVisionShim(void);

NS_ASSUME_NONNULL_END
