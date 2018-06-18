<img src="images/FilterCam.png"  align="center">

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%2010%2B-blue.svg"/>
    <img src="https://img.shields.io/badge/language-swift%204.1-green.svg" />
    <img src="https://img.shields.io/badge/pod-v1.0.0-blue.svg" />
    <img src="https://img.shields.io/badge/license-MIT-lightgrey.svg" /> <br><br>
</p>

## Overview

FilterCam is a simple iOS camera framework for recording videos with custom CIFilters applied. Also FilterCam is made very inspired by [SwiftyCam](https://github.com/Awalz/SwiftyCam).

## Features

|       | FilterCam |
| --------- | -----|
| :+1: | Support iOS 10.0+  |
| :movie_camera: | Video capture  |
| :eyeglasses: | Custom filter  |
| :chart_with_upwards_trend: | Manual image quality settings  |
| :tada: | Front and rear camera support  |
| :flashlight: | Support torch  |
| :eyes: | Supports manual focus  |
| :speaker: | Background audio support  |


## Requirements

- iOS 10.0+

- Swift 4.1+

## License

FilterCam is available under the MIT license. See the LICENSE file for more info.

## Installation

### Carthage:

Add this to `Cartfile`

```
github "nkmrh/FilterCam"`
```

```
$ carthage update FilterCam
```

### Cocoapods:

FilterCam is available through CocoaPods. To install it, simply add the following line to your Podfile:

```
pod "FilterCam"
```

### Manual Installation:

Simply copy the contents of the FilterCam folder into your project.

## Usage

Using FilterCam is very simple.

### Prerequisites:

As of iOS 10, Apple requires the additon of the NSCameraUsageDescription and NSMicrophoneUsageDescription strings to the info.plist of your application. Example:

```xml
<key>NSCameraUsageDescription</key>
	<string>To record video</string>
<key>NSMicrophoneUsageDescription</key>
	<string>To record audio with video</string>
```

### Getting Started:

If you install FilterCam from Cocoapods, be sure to import the module into your View Controller:

```swift
import FilterCam
```

FilterCam is a drop-in convenience framework. To create a Camera instance, create a new UIViewController subclass. Replace the UIViewController subclass declaration with `FilterCamViewController`:

```swift
class MyCameraViewController : FilterCamViewController
```

That is all that is required to setup the AVSession for photo and video capture. FilterCam will prompt the user for permission to use the camera/microphone, and configure both the device inputs and outputs.

### Capture

Capturing Video is just as easy. To begin recording video, call the `startRecording` function:

```swift
startRecording()
```

To end the capture of a video, call the `stopRecording` function:

```swift
stopRecording()
```

### Delegate

You must implement the `FilterCamViewControllerDelegate` and set the `cameraDelegate` to your view controller instance:

```swift
class MyCameraViewController : FilterCamViewController, FilterCamViewControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        cameraDelegate = self
    }
    ...
}
```

#### Delegate methods:

```swift

func filterCamDidStartRecording(_ filterCam: FilterCamViewController) {
	// Called when startRecording() is called
}

func filterCamDidFinishRecording(_ filterCame: FilterCamViewController) {
	// Called when stopRecording() is called
}

func filterCam(_ filterCam: FilterCamViewController, didFinishWriting outputURL: URL) {
	// Called when stopRecording() is called and the video is finished processing
	// Returns a URL in the temporary directory where video is stored
}

func filterCam(_ filterCam: FilterCamViewController, didFocusAtPoint tapPoint: CGPoint) {
	// Called when a user initiates a tap gesture on the preview layer
	// Returns a CGPoint of the tap location on the preview layer
}

func filterCam(_ filterCam: FilterCamViewController, didFailToRecord error: Error) {
	// Called when recorder fail to record
}
```

### Torch

The torch can be enabled by changing the torchLevel property:
```swift
torchLevel = 1
```

Torch level specifies the value between 0.0 and 1.0.


### Switching Camera


By default, FilterCam will launch to the rear facing camera. This can be changed by changing the defaultCamera property in viewDidLoad:
```swift
devicePosition = .front
```

### Configuration

#### Apply filter

You can apply custom filters by specifying an array of filters in the  filters property:
```swift
filters = [CIFilter(name: "CIPhotoEffectInstant")!, CIFilter(name: "CIPhotoEffectNoir")!]
```
filters property type is an array of CIFilter. It is applied sequentially from the first filter.

#### Preview view

If you want to specify the preview frame, you can use custom initializer:
```swift
MyCameraViewController(previewViewRect: CGRect)
```

#### Video Quality

Video quality can be set by the videoQuality property of FilterCamViewController. The choices available AVCaptureSessionPreset.

## Contact

If you have any questions, requests, or enhancements, feel free to submit a pull request, create an issue.

