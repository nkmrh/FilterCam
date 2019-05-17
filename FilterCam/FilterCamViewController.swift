//
//  FilterCamViewController.swift
//  FilterCam
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation

public protocol FilterCamViewControllerDelegate: class {
    func filterCamDidStartRecording(_ filterCam: FilterCamViewController)
    func filterCamDidFinishRecording(_ filterCame: FilterCamViewController)
    func filterCam(_ filterCam: FilterCamViewController, didFailToRecord error: Error)
    func filterCam(_ filterCam: FilterCamViewController, didFinishWriting outputURL: URL)
    func filterCam(_ filterCam: FilterCamViewController, didFocusAtPoint tapPoint: CGPoint)
}

open class FilterCamViewController: UIViewController {

    public weak var cameraDelegate: FilterCamViewControllerDelegate?

    public var devicePosition = AVCaptureDevice.Position.back

    public var videoQuality = AVCaptureSession.Preset.high

    public var filters: [CIFilter] = [] {
        didSet {
            recorder.filters = filters
        }
    }

    public var hasTorch: Bool {
        return recorder.hasTorch
    }

    public var torchLevel: Float {
        set {
            recorder.torchLevel = newValue
        }
        get {
            return recorder.torchLevel
        }
    }

    public var shouldShowDebugLabels: Bool = false {
        didSet {
            fpsLabel.isHidden = !shouldShowDebugLabels
            secLabel.isHidden = !shouldShowDebugLabels
        }
    }

    private let previewViewRect: CGRect

    private var videoPreviewContainerView: UIView!

    private var videoPreviewView: GLKView!

    private var ciContext: CIContext!

    private var recorder: Recorder!

    private var videoPreviewViewBounds: CGRect = .zero

    private var fpsLabel: UILabel!

    private var secLabel: UILabel!

    private var isRecording: Bool {
        return recorder.assetWriter != nil
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override open var shouldAutorotate: Bool {
        return false
    }

    public init(previewViewRect: CGRect) {
        self.previewViewRect = previewViewRect
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        previewViewRect = UIScreen.main.bounds
        super.init(coder: aDecoder)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        videoPreviewContainerView = UIView(frame: previewViewRect)
        videoPreviewContainerView.backgroundColor = .black
        view.addSubview(videoPreviewContainerView)
        view.sendSubviewToBack(videoPreviewContainerView)

        // setup the GLKView for video/image preview
        guard let eaglContext = EAGLContext(api: .openGLES2) else {
            fatalError("Could not create EAGLContext")
        }
        if eaglContext != EAGLContext.current() {
            EAGLContext.setCurrent(eaglContext)
        }
        videoPreviewView = GLKView(frame: CGRect(x: 0,
                                                 y: 0,
                                                 width: previewViewRect.height,
                                                 height: previewViewRect.width),
                                   context: eaglContext)
        videoPreviewContainerView.addSubview(videoPreviewView)

        // because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform so that we can draw the video preview as if we were in a landscape-oriented view; if you're using the front camera and you want to have a mirrored preview (so that the user is seeing themselves in the mirror), you need to apply an additional horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
        videoPreviewView.transform = CGAffineTransform(rotationAngle: .pi / 2)
        videoPreviewView.center = CGPoint(x: previewViewRect.width * 0.5, y: previewViewRect.height * 0.5)
        videoPreviewView.enableSetNeedsDisplay = false

        // bind the frame buffer to get the frame buffer width and height; the bounds used by CIContext when drawing to a GLKView are in pixels (not points), hence the need to read from the frame buffer's width and height; in addition, since we will be accessing the bounds in another queue (_captureSessionQueue), we want to obtain this piece of information so that we won't be accessing _videoPreviewView's properties from another thread/queue
        videoPreviewView.bindDrawable()
        videoPreviewViewBounds.size.width = CGFloat(videoPreviewView.drawableWidth)
        videoPreviewViewBounds.size.height = CGFloat(videoPreviewView.drawableHeight)

        // create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
        ciContext = CIContext(eaglContext: eaglContext, options: convertToOptionalCIContextOptionDictionary([convertFromCIContextOption(CIContextOption.workingColorSpace): NSNull()]))

        recorder = Recorder(ciContext: ciContext, devicePosition: devicePosition, preset: videoQuality)
        recorder.delegate = self

        setupDebugLabels()
        addGestureRecognizers()
    }

    // MARK: - Private

    private func setupDebugLabels() {
        fpsLabel = UILabel()
        fpsLabel.isHidden = true
        view.addSubview(fpsLabel)
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10).isActive = true
        fpsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20).isActive = true
        fpsLabel.text = ""
        fpsLabel.textColor = .white

        secLabel = UILabel()
        secLabel.isHidden = true
        view.addSubview(secLabel)
        secLabel.translatesAutoresizingMaskIntoConstraints = false
        secLabel.leadingAnchor.constraint(equalTo: fpsLabel.leadingAnchor).isActive = true
        secLabel.topAnchor.constraint(equalTo: fpsLabel.bottomAnchor).isActive = true
        secLabel.text = ""
        secLabel.textColor = .white
    }

    private func addGestureRecognizers() {
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(singleTapGesture(tap:)))
        singleTapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTapGesture)
    }

    @objc private func singleTapGesture(tap: UITapGestureRecognizer) {
        let screenSize = view.bounds.size
        let tapPoint = tap.location(in: view)
        let x = tapPoint.y / screenSize.height
        let y = 1.0 - tapPoint.x / screenSize.width
        let focusPoint = CGPoint(x: x, y: y)

        recorder.focus(at: focusPoint)

        // call delegate function and pass in the location of the touch
        DispatchQueue.main.async {
            self.cameraDelegate?.filterCam(self, didFocusAtPoint: tapPoint)
        }
    }

    private func calculateDrawRect(for image: CIImage) -> CGRect {
        let sourceExtent = image.extent
        let sourceAspect = sourceExtent.size.width / sourceExtent.size.height
        let previewAspect = videoPreviewViewBounds.size.width / videoPreviewViewBounds.size.height

        // we want to maintain the aspect ratio of the screen size, so we clip the video image
        var drawRect = sourceExtent

        if sourceAspect > previewAspect {
            // use full height of the video image, and center crop the width
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0
            drawRect.size.width = drawRect.size.height * previewAspect
        } else {
            // use full width of the video image, and center crop the height
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0
            drawRect.size.height = drawRect.size.width / previewAspect
        }

        return drawRect
    }

    // MARK: - Public

    public func startRecording() {
        if !isRecording {
            recorder.startRecording()
        }
    }

    public func stopRecording() {
        if isRecording {
            recorder.stopRecording()
        }
    }
}

extension FilterCamViewController: RecorderDelegate {

    func recorderDidUpdate(drawingImage: CIImage) {
        let drawRect = calculateDrawRect(for: drawingImage)
        videoPreviewView.bindDrawable()
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        ciContext.draw(drawingImage, in: videoPreviewViewBounds, from: drawRect)
        videoPreviewView.display()
    }

    func recorderDidStartRecording() {
        secLabel?.text = "00:00"
        cameraDelegate?.filterCamDidStartRecording(self)
    }

    func recorderDidAbortRecording() {}

    func recorderDidFinishRecording() {
        cameraDelegate?.filterCamDidFinishRecording(self)
    }

    func recorderWillStartWriting() {
        secLabel?.text = "Saving..."
    }

    func recorderDidFinishWriting(outputURL: URL) {
        let fileName = UUID().uuidString
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName).appendingPathExtension("mov")
        Composer.compose(videoURL: outputURL, outputURL: tempURL) { [weak self] url, error in
            guard let strongSelf = self else { return }
            if let url = url {
                strongSelf.cameraDelegate?.filterCam(strongSelf, didFinishWriting: url)
            } else if let error = error {
                strongSelf.cameraDelegate?.filterCam(strongSelf, didFailToRecord: error)
            }
        }
    }

    func recorderDidUpdate(frameRate: Float) {
        fpsLabel?.text = NSString(format: "%.1f fps", frameRate) as String
    }

    func recorderDidUpdate(recordingSeconds: Int) {
        secLabel?.text = NSString(format: "%02lu:%02lu sec", recordingSeconds / 60, recordingSeconds % 60) as String
    }

    func recorderDidFail(with error: Error & LocalizedError) {
        cameraDelegate?.filterCam(self, didFailToRecord: error)
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalCIContextOptionDictionary(_ input: [String: Any]?) -> [CIContextOption: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (CIContextOption(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCIContextOption(_ input: CIContextOption) -> String {
	return input.rawValue
}
