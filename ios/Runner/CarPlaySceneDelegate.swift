import CarPlay
import Flutter
import UIKit

struct CarPlayItem {
  let id: String
  let title: String
  let subtitle: String?
  let browsable: Bool
}

final class CarPlayBridge {
  static let shared = CarPlayBridge()

  private var channel: FlutterMethodChannel?
  private var connectionCallbacks: [() -> Void] = []

  private init() {}

  func connect(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.thomaskleckner.shrimphony/carplay",
      binaryMessenger: messenger
    )
    let callbacks = connectionCallbacks
    connectionCallbacks.removeAll()
    callbacks.forEach { $0() }
  }

  func whenConnected(_ callback: @escaping () -> Void) {
    if channel == nil {
      connectionCallbacks.append(callback)
    } else {
      callback()
    }
  }

  func catalog(id: String, retries: Int = 20, completion: @escaping ([CarPlayItem]) -> Void) {
    guard let channel else {
      whenConnected { [weak self] in self?.catalog(id: id, completion: completion) }
      return
    }

    channel.invokeMethod("catalog", arguments: ["id": id]) { [weak self] result in
      if result as? NSObject === FlutterMethodNotImplemented, retries > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          self?.catalog(id: id, retries: retries - 1, completion: completion)
        }
        return
      }

      let items = (result as? [[String: Any]] ?? []).compactMap { value -> CarPlayItem? in
        guard let id = value["id"] as? String,
              let title = value["title"] as? String else { return nil }
        return CarPlayItem(
          id: id,
          title: title,
          subtitle: value["subtitle"] as? String,
          browsable: value["browsable"] as? Bool ?? false
        )
      }
      DispatchQueue.main.async { completion(items) }
    }
  }

  func play(id: String) {
    channel?.invokeMethod("play", arguments: ["id": id])
  }
}

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    let loading = CPListTemplate(title: "Shrimphony", sections: [])
    loading.emptyViewTitleVariants = ["Loading library…"]
    interfaceController.setRootTemplate(loading, animated: false) { _, _ in }

    CarPlayBridge.shared.whenConnected { [weak self] in
      self?.showCatalog(id: "root", title: "Shrimphony", asRoot: true)
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
  }

  private func showCatalog(id: String, title: String, asRoot: Bool = false) {
    CarPlayBridge.shared.catalog(id: id) { [weak self] items in
      guard let self, let interfaceController else { return }
      let template = self.makeTemplate(title: title, items: items)
      if asRoot {
        interfaceController.setRootTemplate(template, animated: false) { _, _ in }
      } else {
        interfaceController.pushTemplate(template, animated: true) { _, _ in }
      }
    }
  }

  private func makeTemplate(title: String, items: [CarPlayItem]) -> CPListTemplate {
    let rows = items.map { item in
      let row = CPListItem(text: item.title, detailText: item.subtitle)
      row.accessoryType = item.browsable ? .disclosureIndicator : .none
      row.handler = { [weak self] _, completion in
        if item.browsable {
          self?.showCatalog(id: item.id, title: item.title)
        } else {
          CarPlayBridge.shared.play(id: item.id)
          self?.interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true
          ) { _, _ in }
        }
        completion()
      }
      return row
    }

    let template = CPListTemplate(
      title: title,
      sections: rows.isEmpty ? [] : [CPListSection(items: rows)]
    )
    if rows.isEmpty {
      template.emptyViewTitleVariants = ["No music available"]
      template.emptyViewSubtitleVariants = ["Check your Jellyfin connection."]
    }
    return template
  }
}
