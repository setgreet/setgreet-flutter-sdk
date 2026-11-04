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
  s.source_files = 'setgreet/Sources/setgreet/**/*.swift'
  s.dependency 'Flutter'

  # The native SDK ships inside the plugin as prebuilt xcframeworks (copied
  # from https://github.com/setgreet/setgreet-ios-sdk at the matching tag by
  # the update-native-sdk workflow), so apps that still use CocoaPods need no
  # extra pod source. Keep ios/Frameworks in step with the `exact:` version in
  # setgreet/Package.swift, which is what Swift Package Manager builds use.
  s.vendored_frameworks = 'Frameworks/SetgreetSDK.xcframework'
  s.preserve_paths = 'Frameworks/SetgreetSDK.xcframework'

  # `pod 'setgreet'` (what Flutter adds) installs the root spec only, so apps
  # that don't opt in to Lottie keep a Lottie-free build.
  s.default_subspecs = :none

  # Opt-in Lottie support: `pod 'setgreet/Lottie', :path => '.symlinks/plugins/setgreet/ios'`
  # in the app's Podfile adds the SetgreetSDKLottie module (and lottie-ios),
  # which `Setgreet.registerLottie()` then registers. The module is built
  # against the SetgreetSDK above, so both xcframeworks come from the same tag.
  # The lottie-ios constraint mirrors the SDK's own SetgreetSDKLottie podspec.
  s.subspec 'Lottie' do |ss|
    ss.vendored_frameworks = 'Frameworks/SetgreetSDKLottie.xcframework'
    ss.preserve_paths = 'Frameworks/SetgreetSDKLottie.xcframework'
    ss.dependency 'lottie-ios', '~> 4.6'
  end
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
