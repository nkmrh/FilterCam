//
//  Capture.swift
//  FilterCam
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import AVFoundation
import Foundation

protocol CaptureDelegate: class {
    func captureWillStart()
    func captureDidStart()
    func captureWillStop()
    func captureDidStop()
    func captureDidFail(with error: CaptureError)
}

final class Capture {
    weak var delegate: CaptureDelegate?
    weak var videoDataOutputSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    weak var audioDataOutputSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate?

    var hasTorch: Bool {
        return videoDevice.hasTorch
    }

    var torchLevel: Float = 0 {
        didSet {
            if !hasTorch { return }
            if !videoDevice.isTorchAvailable { return }
            try? videoDevice.lockForConfiguration()
            if torchLevel > 0.1 {
                try? videoDevice.setTorchModeOn(level: torchLevel)
            } else {
                videoDevice.torchMode = .off
            }
            videoDevice.unlockForConfiguration()
        }
    }

    let queue = DispatchQueue(label: "caputre_session_queue")

    private(set) var session: AVCaptureSession?
    private var audioDevice: AVCaptureDevice!
    private var videoDevice: AVCaptureDevice!

    private var videoDeviceInput: AVCaptureDeviceInput? {
        do {
            return try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            delegate?.captureDidFail(with: .couldNotObtainVideoDeviceInput(error))
            return nil
        }
    }

    private var audioDeviceInput: AVCaptureDeviceInput? {
        do {
            return try AVCaptureDeviceInput(device: audioDevice)
        } catch {
            delegate?.captureDidFail(with: .couldNotObtainAudioDeviceInput(error))
            return nil
        }
    }

    // create and configure video data output
    private var videoDataOutput: AVCaptureVideoDataOutput {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            // CoreImage wants BGRA pixel format
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(videoDataOutputSampleBufferDelegate, queue: queue)
        return output
    }

    private var audioDataOutput: AVCaptureAudioDataOutput {
        // configure audio data output
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(audioDataOutputSampleBufferDelegate, queue: queue)
        return output
    }

    init(devicePosition: AVCaptureDevice.Position,
         preset: AVCaptureSession.Preset,
         delegate: CaptureDelegate,
         videoDataOutputSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
         audioDataOutputSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate) {
        self.delegate = delegate
        self.videoDataOutputSampleBufferDelegate = videoDataOutputSampleBufferDelegate
        self.audioDataOutputSampleBufferDelegate = audioDataOutputSampleBufferDelegate

        do {
            try AVAudioSession.sharedInstance().setActive(false)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowAirPlay, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("Failed to set background audio preference")
        }

        // check the availability of video and audio devices
        // create and start the capture session only if the devices are present
        do {
            #if targetEnvironment(simulator)
                NSLog("On iPhone Simulator, the app still gets a video device, but the video device will not work")
                NSLog("On iPad Simulator, the app gets no video device")
            #endif

            // see if we have any video device
            // get the input device and also validate the settings
            if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition) {
                // obtain the preset and validate the preset
                if videoDevice.supportsSessionPreset(preset) {
                    self.videoDevice = videoDevice
                    // find the audio device
                    if let audioDevice = AVCaptureDevice.default(.builtInMicrophone, for: .audio, position: .unspecified) {
                        self.audioDevice = audioDevice
                        start(preset)
                    }
                } else {
                    delegate.captureDidFail(with: .presetNotSupportedByVideoDevice(preset))
                }
            } else {
                delegate.captureDidFail(with: .couldNotGetVideoDevice)
            }
        }
    }

    func start(_ preset: AVCaptureSession.Preset) {
        if session != nil {
            return
        }

        delegate?.captureWillStart()

        queue.async { [unowned self] in

            // obtain device input
            guard let videoDeviceInput = self.videoDeviceInput else { return }
            guard let audioDeviceInput = self.audioDeviceInput else { return }

            // create the capture session
            let session = AVCaptureSession()
            session.sessionPreset = preset
            session.automaticallyConfiguresApplicationAudioSession = false
            self.session = session

            // obtain data output
            let videoDataOutput = self.videoDataOutput
            let audioDataOutput = self.audioDataOutput

            if !session.canAddOutput(videoDataOutput) {
                self.delegate?.captureDidFail(with: .couldNotAddVideoDataOutput)
                self.session = nil
                return
            }

            if !session.canAddOutput(audioDataOutput) {
                self.delegate?.captureDidFail(with: .couldNotAddAudioDataOutput)
                self.session = nil
                return
            }

            // begin configure capture session
            session.beginConfiguration()
            // connect the video device input and video data and still image outputs
            session.addInput(videoDeviceInput)
            session.addOutput(videoDataOutput)
            session.addInput(audioDeviceInput)
            session.addOutput(audioDataOutput)
            session.commitConfiguration()
            session.startRunning()

            DispatchQueue.main.async {
                self.delegate?.captureDidStart()
            }
        }
    }

    func stop() {
        guard let session = session else { return }
        if !session.isRunning { return }

        delegate?.captureWillStop()

        session.stopRunning()

        queue.async {
            NSLog("waiting for capture session to end")
        }

        self.session = nil

        delegate?.captureDidStop()
    }

    func focus(at point: CGPoint) {
        do {
            try videoDevice.lockForConfiguration()
            if videoDevice.isFocusPointOfInterestSupported == true {
                videoDevice.focusPointOfInterest = point
                videoDevice.focusMode = .autoFocus
            }
            videoDevice.exposurePointOfInterest = point
            videoDevice.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
            videoDevice.unlockForConfiguration()
        } catch {
            // just ignore
        }
    }
}
