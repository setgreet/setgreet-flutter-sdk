#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint setgreet.podspec` to validate before publishing.
#
require "yaml"

pubspec = YAML.load_file(File.join(__dir__, "../pubspec.yaml"))

Pod::Spec.new do |s|
  s.name             = 'setgreet'
  s.version          = pubspec["version"]
  s.summary          = pubspec["description"]
  s.description      = pubspec["description"]
  s.homepage         = 'https://setgreet.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Setgreet' => 'support@setgreet.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'SetgreetSDK', '0.4.0'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
