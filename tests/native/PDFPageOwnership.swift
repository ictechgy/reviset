import Foundation
import AppKit
import SwiftUI
import PDFKit

@main struct PDFPageOwnership {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"]!)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = PDFDocument()
        for index in 0..<3 {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 500, height: 500), for: .mediaBox)
            document.insert(page, at: index)
        }
        let url = folder.appendingPathComponent("source.pdf")
        guard document.write(to: url) else { throw NSError(domain: "PDFWrite", code: 1) }
        let host = NSHostingView(rootView: OriginalPDFView(path: url.path, pageNumber: 1, zoom: 0, evidence: JSON(), page: JSON()))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        func findPDF(_ view: NSView) -> PDFView? {
            if let pdf = view as? PDFView { return pdf }
            return view.subviews.compactMap { findPDF($0) }.first
        }
        guard let pdf = findPDF(host), let loaded = pdf.document, let second = loaded.page(at: 1) else { throw NSError(domain: "PDFHostMissing", code: 1) }
        func requirePage(_ expected: Int, _ context: String) throws {
            let actual = pdf.currentPage.map { loaded.index(for: $0) + 1 } ?? 0
            guard actual == expected else { throw NSError(domain: "PDFPageOwnership", code: actual, userInfo: [NSLocalizedDescriptionKey: "\(context): visible \(actual), selected \(expected)"]) }
        }
        for (key, characters): (UInt16, String) in [(121, "\u{f72d}"), (125, "\u{f701}"), (49, " ")] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key)!
            pdf.keyDown(with: event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            try requirePage(1, "PDF internal key event")
        }
        pdf.perform(PDFActionGoTo(destination: PDFDestination(page: second, at: .zero)))
        try requirePage(1, "PDF destination link")
        host.rootView = OriginalPDFView(path: url.path, pageNumber: 2, zoom: 0, evidence: JSON(), page: JSON())
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        try requirePage(2, "Explicit model navigation")
        pdf.goToPreviousPage(nil)
        try requirePage(2, "PDF previous-page action")
        host.rootView = OriginalPDFView(path: url.path, pageNumber: 3, zoom: 1, evidence: JSON(), page: JSON())
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        try requirePage(3, "Explicit model navigation with zoom")
        print("PASS production PDFKit page ownership: keys, destination links, previous-page actions, and explicit model navigation")
        withExtendedLifetime(window) {}
    }
}
