import AVKit
import Network
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

  private var networkMonitor: NWPathMonitor?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterMethodChannel(name: "com.thomaskleckner.shrimphony/network", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "isWifi" else { result(FlutterMethodNotImplemented); return }
        let monitor = NWPathMonitor()
        self?.networkMonitor = monitor
        monitor.pathUpdateHandler = { path in
          monitor.cancel()
          DispatchQueue.main.async {
            result(path.status == .satisfied && path.usesInterfaceType(.wifi))
          }
        }
        monitor.start(queue: DispatchQueue(label: "shrimphony.network"))
      }
    FlutterMethodChannel(name: "com.thomaskleckner.shrimphony/links", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "open", let arguments = call.arguments as? [String: Any],
              let text = arguments["url"] as? String, let url = URL(string: text),
              ["https", "mailto"].contains(url.scheme ?? "") else {
          result(FlutterError(code: "invalid_url", message: "Use an HTTPS or email support link", details: nil))
          return
        }
        UIApplication.shared.open(url) { opened in
          result(opened ? nil : FlutterError(code: "unavailable", message: "Could not open support", details: nil))
        }
      }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    CarPlayBridge.shared.connect(messenger: engineBridge.applicationRegistrar.messenger())
    engineBridge.applicationRegistrar.register(
      AudioRoutePickerFactory(),
      withId: "com.thomaskleckner.shrimphony/audio_route_picker"
    )
  }
}
