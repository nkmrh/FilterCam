Pod::Spec.new do |s|
  s.name         = "FilterCam"
  s.version      = "1.0.1"
  s.summary      = "A video capture framework that can easily apply your custom filters"
  s.description  = <<-DESC
  FilterCam is a simple iOS camera framework for recording videos with custom CIFilters applied. Also FilterCam is made very inspired by SwiftyCam.
                   DESC
  s.homepage     = "https://github.com/nkmrh/FilterCam"
  # s.screenshots  = "www.example.com/screenshots_1.gif", "www.example.com/screenshots_2.gif"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "Hajime Nakamura" => "nkmrhj@gmail.com" }
  s.social_media_url   = "http://twitter.com/_nkmrh"
  s.platform     = :ios, "10.0"
  s.source       = { :git => "https://github.com/nkmrh/FilterCam.git", :tag => s.version }
  s.source_files  = "FilterCam/*.swift"
  s.requires_arc = true
end
