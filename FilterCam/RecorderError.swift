//
//  RecorderError.swift
//  FilterCam
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import Foundation

enum RecorderError: Error {
    case couldNotCreateAssetWriter(Error)
    case couldNotAddAssetWriterVideoInput
    case couldNotAddAssetWriterAudioInput
    case couldNotGetAudioSampleBufferFormatDescription
    case couldNotGetStreamBasicDescriptionOfAudioSampleBuffer
    case couldNotCompleteWritingVideo
    case couldNotApplyAudioOutputSettings
    case couldNotWriteAudioData
    case couldNotWriteVideoData
}

extension RecorderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .couldNotCreateAssetWriter(error):
            return "Could not create asset writer, error: \(error)"
        case .couldNotAddAssetWriterVideoInput:
            return "Could not add asset writer video input"
        case .couldNotAddAssetWriterAudioInput:
            return "Could not add asset writer audio input"
        case .couldNotGetAudioSampleBufferFormatDescription:
            return "Could not get current audio sample buffer format description"
        case .couldNotGetStreamBasicDescriptionOfAudioSampleBuffer:
            return "Could not get stream basic description of audio sample buffer"
        case .couldNotCompleteWritingVideo:
            return "Could not complete writing the video"
        case .couldNotApplyAudioOutputSettings:
            return "Could not apply audio output settings"
        case .couldNotWriteAudioData:
            return "Could not write audio data, recording aborted"
        case .couldNotWriteVideoData:
            return "Could not write video data, recording aborted"
        }
    }
}
