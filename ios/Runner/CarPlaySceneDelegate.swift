import CarPlay
import Flutter
import UIKit

struct CarPlayItem {
  let id: String
  let title: String
  let subtitle: String?
  let browsable: Bool
  let artworkUri: String?
  let artworkHeaders: [String: String]?
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

  func catalog(id: String, retries: Int = 20, completion: @escaping ([CarPlayItem], String?) -> Void) {
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

      if let error = result as? FlutterError {
        DispatchQueue.main.async { completion([], error.message ?? "Could not load music. Retry when connected.") }
        return
      }
      if result as? NSObject === FlutterMethodNotImplemented {
        DispatchQueue.main.async { completion([], "Open Shrimphony on your phone, then retry.") }
        return
      }
      let items = (result as? [[String: Any]] ?? []).compactMap { value -> CarPlayItem? in
        guard let id = value["id"] as? String,
              let title = value["title"] as? String else { return nil }
        return CarPlayItem(
          id: id,
          title: title,
          subtitle: value["subtitle"] as? String,
          browsable: value["browsable"] as? Bool ?? false,
          artworkUri: value["artworkUri"] as? String,
          artworkHeaders: value["artworkHeaders"] as? [String: String]
        )
      }
      DispatchQueue.main.async { completion(items, nil) }
    }
  }

  func play(id: String, completion: @escaping (String?) -> Void) {
    guard let channel else { completion("Open Shrimphony on your phone first."); return }
    channel.invokeMethod("play", arguments: ["id": id]) { result in
      completion((result as? FlutterError)?.message)
    }
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
    CarPlayBridge.shared.catalog(id: id) { [weak self] items, error in
      guard let self, let interfaceController else { return }
      if let error { self.showError(error) { self.showCatalog(id: id, title: title, asRoot: asRoot) }; return }
      let template = self.makeTemplate(title: title, items: items)
      if asRoot {
        interfaceController.setRootTemplate(template, animated: false) { _, _ in }
      } else {
        interfaceController.pushTemplate(template, animated: true) { _, _ in }
      }
    }
  }

  private func showError(_ message: String, retry: @escaping () -> Void) {
    let alert = CPAlertTemplate(titleVariants: [message], actions: [
      CPAlertAction(title: "Retry", style: .default) { [weak self] _ in
        self?.interfaceController?.dismissTemplate(animated: true) { _, _ in retry() }
      },
      CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
        self?.interfaceController?.dismissTemplate(animated: true) { _, _ in }
      }
    ])
    interfaceController?.presentTemplate(alert, animated: true) { _, _ in }
  }

  private func play(_ id: String, completion: @escaping () -> Void) {
    CarPlayBridge.shared.play(id: id) { [weak self] error in
      if let error { self?.showError(error) { self?.play(id, completion: {}) } }
      else { self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { _, _ in } }
      completion()
    }
  }

  private func makeTemplate(title: String, items: [CarPlayItem]) -> CPListTemplate {
    let rows = items.map { item in
      let row = CPListItem(text: item.title, detailText: item.subtitle)
      if let text = item.artworkUri, let url = URL(string: text) {
        if url.isFileURL { row.setImage(UIImage(contentsOfFile: url.path)) }
        else if ["http", "https"].contains(url.scheme ?? "") {
          var request = URLRequest(url: url)
          request.allHTTPHeaderFields = item.artworkHeaders
          URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { row.setImage(image) }
          }.resume()
        }
      }
      row.accessoryType = item.browsable ? .disclosureIndicator : .none
      row.handler = { [weak self] _, completion in
        if item.browsable {
          self?.showCatalog(id: item.id, title: item.title)
        } else {
          self?.play(item.id, completion: completion)
          return
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
