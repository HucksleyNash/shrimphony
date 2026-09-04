import AVKit
import Flutter
import UIKit

final class AudioRoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    AudioRoutePicker(frame: frame)
  }
}

final class AudioRoutePicker: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView

  init(frame: CGRect) {
    picker = AVRoutePickerView(frame: frame)
    picker.prioritizesVideoDevices = false
    picker.tintColor = .label
    picker.activeTintColor = .systemBlue
    picker.accessibilityLabel = "Choose AirPlay or Bluetooth output"
    super.init()
  }

  func view() -> UIView { picker }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    CarPlayBridge.shared.connect(messenger: engineBridge.applicationRegistrar.messenger())
    engineBridge.applicationRegistrar.register(
      AudioRoutePickerFactory(),
      withId: "com.thomaskleckner.shrimphony/audio_route_picker"
    )
  }
}
