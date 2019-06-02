//
//  ViewController.swift
//  Example
//
//  Copyright © 2018 hajime-nakamura. All rights reserved.
//

import Photos
import UIKit

final class ViewController: FilterCamViewController {
    @IBOutlet private var controlPanelView: UIView!
    @IBOutlet private var segmentedControl: UISegmentedControl!
    @IBOutlet private var torchButton: UIButton!
    @IBOutlet private var recordButton: UIButton!

    private let myFilters: [[CIFilter]] = [
        [],
        [CIFilter(name: "CIPhotoEffectInstant")!],
        [CIFilter(name: "CIPhotoEffectInstant")!, CIFilter(name: "CIPhotoEffectNoir")!],
    ]

    override func viewDidLoad() {
//        devicePosition = .front
//        videoQuality = .low
        super.viewDidLoad()
        cameraDelegate = self
        shouldShowDebugLabels = true
    }

    private func saveVideoToPhotos(_ url: URL) {
        let save = {
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }, completionHandler: { _, _ in
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                }
            })
        }
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    save()
                }
            }
        } else {
            save()
        }
    }

    @IBAction func segmentedControlAction(_ sender: UISegmentedControl) {
        filters = myFilters[sender.selectedSegmentIndex]
    }

    @IBAction func torchButtonAction(_ sender: UIButton) {
        torchLevel = sender.isSelected ? 0 : 1
        sender.isSelected = !sender.isSelected
    }

    @IBAction func recordButtonAction(_ sender: UIButton) {
        sender.isSelected ? stopRecording() : startRecording()
        sender.isSelected = !sender.isSelected
    }
}

extension ViewController: FilterCamViewControllerDelegate {
    func filterCamDidStartRecording(_: FilterCamViewController) {}

    func filterCamDidFinishRecording(_: FilterCamViewController) {}

    func filterCam(_: FilterCamViewController, didFinishWriting outputURL: URL) {
        saveVideoToPhotos(outputURL)
    }

    func filterCam(_: FilterCamViewController, didFocusAtPoint _: CGPoint) {}

    func filterCam(_: FilterCamViewController, didFailToRecord _: Error) {}
}
