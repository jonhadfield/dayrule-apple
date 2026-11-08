import UIKit
import UniformTypeIdentifiers

/// Share sheet target: encrypt shared text into the App Group queue (PLAN §1).
/// Never touches the account key.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await finishShare() }
    }

    @MainActor
    private func finishShare() async {
        do {
            let title = try await sharedTitle()
            if !title.isEmpty {
                try ShareInboxQueue.enqueue(title: title)
            }
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } catch {
            let alert = UIAlertController(
                title: "Couldn’t add to Dayrule",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: error)
            })
            present(alert, animated: true)
        }
    }

    private func sharedTitle() async throws -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return ""
        }
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try await loadURL(provider) {
                    return ShareInboxPickedTitle.resolve(urlString: url.absoluteString)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try await loadText(provider) {
                    return ShareInboxPickedTitle.resolve(plainText: text)
                }
            }
            return ShareInboxPickedTitle.resolve(
                attributedText: item.attributedContentText?.string
            )
        }
        return ""
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let s = item as? String {
                    cont.resume(returning: s)
                } else if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                    cont.resume(returning: s)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let s = item as? String, let url = URL(string: s) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
