//
//  FrameRateCalculator.swift
//  FilterCam
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import AVFoundation
import Foundation

final class FrameRateCalculator {
    var previousSecondTimestamps: [CMTime] = []
    var frameRate: Float = 0

    func reset() {
        previousSecondTimestamps.removeAll()
        frameRate = 0
    }

    func calculateFramerate(at timestamp: CMTime) {
        previousSecondTimestamps.append(timestamp)

        let oneSecond = CMTime(seconds: 1, preferredTimescale: 1)
        let oneSecondAgo = timestamp - oneSecond

        while !previousSecondTimestamps.isEmpty && previousSecondTimestamps[0] < oneSecondAgo {
            previousSecondTimestamps.remove(at: 0)
        }

        let newRate = Float(previousSecondTimestamps.count)

        frameRate = (frameRate + newRate) / 2
    }
}
