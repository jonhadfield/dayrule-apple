import Foundation
import SwiftUI
import Testing
@testable import Dayrule

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Renders the five polish surfaces to PNG (temp dir; sandboxed test host).
@Suite("Design captures")
@MainActor
struct DesignCaptureTests {
    @Test func writePolishCaptures() throws {
        #if DEBUG
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayrule-design-captures", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let files = [
            ("01-editor-leading-rule.png", AnyView(DesignCaptures.EditorCapture())),
            ("02-mac-sidebar-chrome.png", AnyView(DesignCaptures.SidebarCapture())),
            ("02b-mac-menus.png", AnyView(DesignCaptures.MenuCapture())),
            ("03-move-sheet.png", AnyView(DesignCaptures.MoveCapture())),
            ("04-paper-add.png", AnyView(DesignCaptures.PaperAddCapture())),
            ("05-tokens-plan.png", AnyView(DesignCaptures.TokensCapture())),
        ]
        for (name, view) in files {
            let url = out.appendingPathComponent(name)
            let png = try render(view)
            try png.write(to: url)
            // Sandboxed host can't write into the repo; optional base64 dump for local copy-out.
            if ProcessInfo.processInfo.environment["DAYRULE_DUMP_CAPTURES"] == "1" {
                print("DAYRULE_PNG \(name) \(png.base64EncodedString())")
            }
        }
        print("DAYRULE_CAPTURES=\(out.path)")
        #else
        // Release test hosts skip DEBUG-only capture views.
        #endif
    }

    private func render<V: View>(_ view: V) throws -> Data {
        let wrapped = view
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw CaptureError.renderFailed
        }
        return png
        #elseif canImport(UIKit)
        guard let image = renderer.uiImage, let png = image.pngData() else {
            throw CaptureError.renderFailed
        }
        return png
        #else
        throw CaptureError.renderFailed
        #endif
    }

    private enum CaptureError: Error {
        case renderFailed
    }
}
