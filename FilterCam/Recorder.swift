//
//  Recorder.swift
//  FilterCam
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import AVFoundation
import CoreImage
import Foundation
import UIKit

protocol RecorderDelegate: class {
    func recorderDidUpdate(drawingImage: CIImage)
    func recorderDidStartRecording()
    func recorderDidAbortRecording()
    func recorderDidFinishRecording()
    func recorderWillStartWriting()
    func recorderDidFinishWriting(outputURL: URL)
    func recorderDidUpdate(frameRate: Float)
    func recorderDidUpdate(recordingSeconds: Int)
    func recorderDidFail(with error: Error & LocalizedError)
}

final class Recorder: NSObject {
    weak var delegate: RecorderDelegate?

    var filters: [CIFilter] = []

    var frameRate: Float {
        return frameRateCalculator.frameRate
    }

    var recordingSeconds: Int {
        guard assetWriter != nil else { return 0 }
        let diff = currentVideoTime - videoWritingStartTime
        let seconds = CMTimeGetSeconds(diff)
        guard !(seconds.isNaN || seconds.isInfinite) else { return 0 }
        return Int(seconds)
    }

    var hasTorch: Bool {
        return capture.hasTorch
    }

    var torchLevel: Float {
        set {
            capture.torchLevel = newValue
        }
        get {
            return capture.torchLevel
        }
    }

    private static let deviceRgbColorSpace = CGColorSpaceCreateDeviceRGB()
    private static let tempVideoFilename = "recording"
    private static let tempVideoFileExtention = "mov"

    private let ciContext: CIContext
    private var capture: Capture!
    private let devicePosition: AVCaptureDevice.Position!

    private var videoWritingStarted = false
    private var videoWritingStartTime = CMTime()
    private(set) var assetWriter: AVAssetWriter?
    private var assetWriterAudioInput: AVAssetWriterInput?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var currentAudioSampleBufferFormatDescription: CMFormatDescription?
    private var currentVideoDimensions: CMVideoDimensions?
    private var currentVideoTime = CMTime()

    private let frameRateCalculator = FrameRateCalculator()
    private var timer: Timer?
    private let timerUpdateInterval = 0.25

    private var temporaryVideoFileURL: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(Recorder.tempVideoFilename)
            .appendingPathExtension(Recorder.tempVideoFileExtention)
    }

    private func makeAssetWriter() -> AVAssetWriter? {
        do {
            return try AVAssetWriter(url: temporaryVideoFileURL, fileType: .mov)
        } catch {
            DispatchQueue.main.async {
                self.delegate?.recorderDidFail(with: RecorderError.couldNotCreateAssetWriter(error))
            }
            return nil
        }
    }

    private func makeAssetWriterVideoInput() -> AVAssetWriterInput {
        let settings: [String: Any]
        if #available(iOS 11.0, *) {
            settings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: currentVideoDimensions?.width ?? 0,
                AVVideoHeightKey: currentVideoDimensions?.height ?? 0,
            ]
        } else {
            settings = [
                AVVideoCodecKey: AVVideoCodecH264,
                AVVideoWidthKey: currentVideoDimensions?.width ?? 0,
                AVVideoHeightKey: currentVideoDimensions?.height ?? 0,
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    // create a pixel buffer adaptor for the asset writer; we need to obtain pixel buffers for rendering later from its pixel buffer pool
    private func makeAssetWriterInputPixelBufferAdaptor(with input: AVAssetWriterInput) -> AVAssetWriterInputPixelBufferAdaptor {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: currentVideoDimensions?.width ?? 0,
            kCVPixelBufferHeightKey as String: currentVideoDimensions?.height ?? 0,
            kCVPixelFormatOpenGLESCompatibility as String: kCFBooleanTrue!,
        ]
        return AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )
    }

    private func makeAudioCompressionSettings() -> [String: Any]? {
        guard let currentAudioSampleBufferFormatDescription = self.currentAudioSampleBufferFormatDescription else {
            DispatchQueue.main.async {
                self.delegate?.recorderDidFail(with: RecorderError.couldNotGetAudioSampleBufferFormatDescription)
            }
            return nil
        }

        let channelLayoutData: Data
        var layoutSize: size_t = 0
        if let channelLayout = CMAudioFormatDescriptionGetChannelLayout(currentAudioSampleBufferFormatDescription, sizeOut: &layoutSize) {
            channelLayoutData = Data(bytes: channelLayout, count: layoutSize)
        } else {
            channelLayoutData = Data()
        }

        guard let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(currentAudioSampleBufferFormatDescription) else {
            DispatchQueue.main.async {
                self.delegate?.recorderDidFail(with: RecorderError.couldNotGetStreamBasicDescriptionOfAudioSampleBuffer)
            }
            return nil
        }

        // record the audio at AAC format, bitrate 64000, sample rate and channel number using the basic description from the audio samples
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: basicDescription.pointee.mChannelsPerFrame,
            AVSampleRateKey: basicDescription.pointee.mSampleRate,
            AVEncoderBitRateKey: 64000,
            AVChannelLayoutKey: channelLayoutData,
        ]
    }

    private func getRenderedOutputPixcelBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor?) -> CVPixelBuffer? {
        guard let pixelBufferPool = adaptor?.pixelBufferPool else {
            NSLog("Cannot get pixel buffer pool")
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard let renderedOutputPixelBuffer = pixelBuffer else {
            NSLog("Cannot obtain a pixel buffer from the buffer pool")
            return nil
        }

        return renderedOutputPixelBuffer
    }

    init(ciContext: CIContext,
         devicePosition: AVCaptureDevice.Position,
         preset: AVCaptureSession.Preset) {
        self.ciContext = ciContext
        self.devicePosition = devicePosition

        super.init()

        capture = Capture(devicePosition: devicePosition,
                          preset: preset,
                          delegate: self,
                          videoDataOutputSampleBufferDelegate: self,
                          audioDataOutputSampleBufferDelegate: self)

        // handle AVCaptureSessionWasInterruptedNotification (such as incoming phone call)
        NotificationCenter.default.addObserver(self, selector: #selector(avCaptureSessionWasInterrupted(_:)),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: nil)

        // handle UIApplicationDidEnterBackgroundNotification
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }

    func startRecording() {
        capture.queue.async { [unowned self] in
            self.removeTemporaryVideoFileIfAny()

            guard let newAssetWriter = self.makeAssetWriter() else { return }

            let newAssetWriterVideoInput = self.makeAssetWriterVideoInput()
            let canAddInput = newAssetWriter.canAdd(newAssetWriterVideoInput)
            if canAddInput {
                newAssetWriter.add(newAssetWriterVideoInput)
            } else {
                DispatchQueue.main.async {
                    self.delegate?.recorderDidFail(with: RecorderError.couldNotAddAssetWriterVideoInput)
                }
                self.assetWriterVideoInput = nil
                return
            }

            let newAssetWriterInputPixelBufferAdaptor = self.makeAssetWriterInputPixelBufferAdaptor(with: newAssetWriterVideoInput)

            guard let audioCompressionSettings = self.makeAudioCompressionSettings() else { return }
            let canApplayOutputSettings = newAssetWriter.canApply(outputSettings: audioCompressionSettings, forMediaType: .audio)
            if canApplayOutputSettings {
                let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioCompressionSettings)
                assetWriterAudioInput.expectsMediaDataInRealTime = true
                self.assetWriterAudioInput = assetWriterAudioInput

                let canAddInput = newAssetWriter.canAdd(assetWriterAudioInput)
                if canAddInput {
                    newAssetWriter.add(assetWriterAudioInput)
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.recorderDidFail(with: RecorderError.couldNotAddAssetWriterAudioInput)
                    }
                    self.assetWriterAudioInput = nil
                    return
                }
            } else {
                DispatchQueue.main.async {
                    self.delegate?.recorderDidFail(with: RecorderError.couldNotApplyAudioOutputSettings)
                }
                return
            }

            self.videoWritingStarted = false
            self.assetWriter = newAssetWriter
            self.assetWriterVideoInput = newAssetWriterVideoInput
            self.assetWriterInputPixelBufferAdaptor = newAssetWriterInputPixelBufferAdaptor

            DispatchQueue.main.async {
                self.delegate?.recorderDidStartRecording()
            }
        }
    }

    private func abortRecording() {
        guard let writer = assetWriter else { return }

        writer.cancelWriting()
        assetWriterVideoInput = nil
        assetWriterAudioInput = nil
        assetWriter = nil

        // remove the temp file
        let fileURL = writer.outputURL
        try? FileManager.default.removeItem(at: fileURL)

        DispatchQueue.main.async {
            self.delegate?.recorderDidAbortRecording()
        }
    }

    func stopRecording() {
        guard let writer = assetWriter else { return }

        assetWriterVideoInput = nil
        assetWriterAudioInput = nil
        assetWriterInputPixelBufferAdaptor = nil
        assetWriter = nil

        DispatchQueue.main.async {
            self.delegate?.recorderWillStartWriting()
        }

        capture.queue.async { [unowned self] in
            writer.endSession(atSourceTime: self.currentVideoTime)
            writer.finishWriting {
                switch writer.status {
                case .failed:
                    DispatchQueue.main.async {
                        self.delegate?.recorderDidFail(with: RecorderError.couldNotCompleteWritingVideo)
                    }
                case .completed:
                    DispatchQueue.main.async {
                        self.delegate?.recorderDidFinishWriting(outputURL: writer.outputURL)
                    }
                default:
                    break
                }
            }
            DispatchQueue.main.async {
                self.delegate?.recorderDidFinishRecording()
            }
            self.startTimer()
        }
    }

    func focus(at point: CGPoint) {
        capture.focus(at: point)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: timerUpdateInterval,
                                     repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            DispatchQueue.main.async {
                strongSelf.delegate?.recorderDidUpdate(frameRate: strongSelf.frameRate)
                strongSelf.delegate?.recorderDidUpdate(recordingSeconds: strongSelf.recordingSeconds)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func handleAudioSampleBuffer(buffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(buffer) else { return }
        currentAudioSampleBufferFormatDescription = formatDesc

        // write the audio data if it's from the audio connection
        if assetWriter == nil { return }
        guard let input = assetWriterAudioInput else { return }
        if input.isReadyForMoreMediaData {
            let success = input.append(buffer)
            if !success {
                DispatchQueue.main.async {
                    self.delegate?.recorderDidFail(with: RecorderError.couldNotWriteAudioData)
                }
                abortRecording()
            }
        }
    }

    private func handleVideoSampleBuffer(buffer: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        frameRateCalculator.calculateFramerate(at: timestamp)

        // update the video dimensions information
        guard let formatDesc = CMSampleBufferGetFormatDescription(buffer) else { return }
        currentVideoDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)

        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let sourceImage: CIImage
        if devicePosition == .front {
            let image = CIImage(cvPixelBuffer: imageBuffer)
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: 0, y: image.extent.height)
            transform = transform.scaledBy(x: 1, y: -1)
            sourceImage = image.transformed(by: transform)
        } else {
            sourceImage = CIImage(cvPixelBuffer: imageBuffer)
        }

        // run the filter through the filter chain
        guard let filteredImage = runFilter(cameraImage: sourceImage, filters: filters) else { return }

        guard let writer = assetWriter, let pixelBufferAdaptor = assetWriterInputPixelBufferAdaptor else {
            DispatchQueue.main.async {
                self.delegate?.recorderDidUpdate(drawingImage: filteredImage)
            }
            return
        }

        // if we need to write video and haven't started yet, start writing
        if !videoWritingStarted {
            videoWritingStarted = true
            let success = writer.startWriting()
            if !success {
                DispatchQueue.main.async {
                    self.delegate?.recorderDidFail(with: RecorderError.couldNotWriteVideoData)
                }
                abortRecording()
                return
            }

            writer.startSession(atSourceTime: timestamp)
            videoWritingStartTime = timestamp
        }

        guard let renderedOutputPixelBuffer = getRenderedOutputPixcelBuffer(adaptor: pixelBufferAdaptor) else { return }

        // render the filtered image back to the pixel buffer (no locking needed as CIContext's render method will do that
        ciContext.render(filteredImage, to: renderedOutputPixelBuffer, bounds: filteredImage.extent, colorSpace: Recorder.deviceRgbColorSpace)

        // pass option nil to enable color matching at the output, otherwise the color will be off
        let drawImage = CIImage(cvPixelBuffer: renderedOutputPixelBuffer)
        DispatchQueue.main.async {
            self.delegate?.recorderDidUpdate(drawingImage: drawImage)
        }

        currentVideoTime = timestamp

        // write the video data
        guard let input = assetWriterVideoInput else { return }
        if input.isReadyForMoreMediaData {
            let success = pixelBufferAdaptor.append(renderedOutputPixelBuffer, withPresentationTime: timestamp)
            if !success {
                DispatchQueue.main.async {
                    self.delegate?.recorderDidFail(with: RecorderError.couldNotWriteVideoData)
                }
            }
        }
    }

    private func removeTemporaryVideoFileIfAny() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: temporaryVideoFileURL.path) {
            try? fileManager.removeItem(at: temporaryVideoFileURL)
        }
    }

    @objc private func avCaptureSessionWasInterrupted(_: Notification) {
        stopRecording()
    }

    @objc private func applicationDidEnterBackground(_: Notification) {
        stopRecording()
    }
}

extension Recorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        if mediaType == kCMMediaType_Audio {
            handleAudioSampleBuffer(buffer: sampleBuffer)
        } else if mediaType == kCMMediaType_Video {
            handleVideoSampleBuffer(buffer: sampleBuffer)
        }
    }

    func runFilter(cameraImage: CIImage, filters: [CIFilter]) -> CIImage? {
        var filterdImage = cameraImage
        for filter in filters {
            filter.setValue(filterdImage, forKey: kCIInputImageKey)
            if let image = filter.outputImage {
                filterdImage = image
            }
        }
        return filterdImage
    }
}

extension Recorder: CaptureDelegate {
    func captureWillStart() {
        stopTimer()
        frameRateCalculator.reset()
    }

    func captureDidStart() {
        startTimer()
    }

    func captureWillStop() {}

    func captureDidStop() {
        stopTimer()
        stopRecording()
    }

    func captureDidFail(with error: CaptureError) {
        DispatchQueue.main.async {
            self.delegate?.recorderDidFail(with: error)
        }
    }
}
