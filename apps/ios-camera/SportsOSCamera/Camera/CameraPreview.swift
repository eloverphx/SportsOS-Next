import AVFoundation
import SwiftUI
import UIKit

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill

        updateVideoRotation()
    }

    private func updateVideoRotation() {
        guard
            let connection = previewLayer.connection,
            connection.isVideoRotationAngleSupported(0)
        else {
            return
        }

        let orientation =
            window?.windowScene?.interfaceOrientation
            ?? .landscapeRight

        let angle: CGFloat

        switch orientation {
        case .landscapeLeft:
            angle = 180
        case .landscapeRight:
            angle = 0
        case .portraitUpsideDown:
            angle = 270
        default:
            angle = 90
        }

        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: .zero)

        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        return view
    }
    func updateUIView(
        _ uiView: CameraPreviewView,
        context: Context
    ) {
        uiView.previewLayer.session = session
        uiView.setNeedsLayout()
    }
}
