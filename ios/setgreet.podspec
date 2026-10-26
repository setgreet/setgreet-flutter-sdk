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
  s.dependency 'SetgreetSDK', '1.9.0'

  # `pod 'setgreet'` (what Flutter adds) installs the root spec only, so apps
  # that don't opt in to Lottie keep a Lottie-free build.
  s.default_subspecs = :none

  # Opt-in Lottie support: `pod 'setgreet/Lottie', :path => '.symlinks/plugins/setgreet/ios'`
  # in the app's Podfile adds the SetgreetSDKLottie module (and lottie-ios),
  # which `Setgreet.registerLottie()` then registers. Keep the version in step
  # with SetgreetSDK above (SetgreetSDKLottie requires that exact version).
  s.subspec 'Lottie' do |ss|
    ss.dependency 'SetgreetSDKLottie', '1.8.0'
  end
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
