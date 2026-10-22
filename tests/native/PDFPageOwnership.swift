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
            page.setBounds(CGRect(x: 0, y: 0, width: 500, height: 1500), for: .mediaBox)
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
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        func select(_ page: Int, zoom: Double, path: String? = nil) {
            host.rootView = OriginalPDFView(path: path ?? url.path, pageNumber: page, zoom: zoom, evidence: JSON(), page: JSON())
            host.layoutSubtreeIfNeeded()
            settle()
        }
        guard let clip = pdf.documentView?.enclosingScrollView?.contentView, let first = loaded.page(at: 0) else { throw NSError(domain: "PDFClipMissing", code: 1) }
        func viewport(_ point: NSPoint) -> NSPoint {
            var bounds = clip.bounds
            bounds.origin = point
            clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
            clip.enclosingScrollView?.reflectScrolledClipView(clip)
            settle()
            return clip.bounds.origin
        }
        var failures = [String]()
        func requireViewport(_ expected: NSPoint, _ context: String) {
            let actual = clip.bounds.origin
            if abs(actual.x - expected.x) > 0.5 || abs(actual.y - expected.y) > 0.5 {
                failures.append("\(context): viewport \(actual), expected \(expected)")
            }
            if abs(pdf.scaleFactor - 2) > 0.001 { failures.append("\(context): lost zoom") }
        }
        select(1, zoom: 2)
        // Check both axes: a link may scroll horizontally after PageChanged,
        // while PageDown can reset vertical bounds before that notification.
        for position in [NSPoint(x: 100, y: 500), NSPoint(x: 100, y: 10000)] {
            let beforeLink = viewport(position)
            pdf.perform(PDFActionGoTo(destination: PDFDestination(page: second, at: CGPoint(x: 0, y: 200))))
            settle()
            try requirePage(1, "Zoomed destination link")
            requireViewport(beforeLink, "Zoomed destination link")
        }
        let beforeKey = viewport(NSPoint(x: 100, y: 10000))
        let pageDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{f72d}", charactersIgnoringModifiers: "\u{f72d}", isARepeat: false, keyCode: 121)!
        pdf.keyDown(with: pageDown)
        settle()
        try requirePage(1, "Zoomed PageDown")
        requireViewport(beforeKey, "Zoomed PageDown")
        // Ordinary within-page scrolling and destinations remain available.
        let firstScroll = viewport(NSPoint(x: 100, y: 500))
        let secondScroll = viewport(NSPoint(x: 120, y: 700))
        if firstScroll == secondScroll { failures.append("Within-page scrolling stopped") }
        pdf.go(to: PDFDestination(page: first, at: CGPoint(x: 40, y: 500)))
        settle()
        try requirePage(1, "Same-page destination")
        if clip.bounds.origin == secondScroll { failures.append("Same-page destination stopped") }
        // Invalidate a queued restoration when the model changes its selection.
        _ = viewport(NSPoint(x: 100, y: 10000))
        pdf.perform(PDFActionGoTo(destination: PDFDestination(page: second, at: .zero)))
        select(2, zoom: 1)
        try requirePage(2, "Explicit selection during pending viewport restoration")
        if abs(pdf.scaleFactor - 1) > 0.001 { failures.append("Explicit zoom change was overwritten") }
        select(3, zoom: 2)
        try requirePage(3, "Explicit zoomed page selection")
        let beforePrevious = viewport(NSPoint(x: 100, y: 700))
        pdf.goToPreviousPage(nil)
        settle()
        try requirePage(3, "Zoomed previous-page action")
        requireViewport(beforePrevious, "Zoomed previous-page action")
        let replacement = PDFDocument()
        let replacementPage = PDFPage()
        replacementPage.setBounds(CGRect(x: 0, y: 0, width: 350, height: 700), for: .mediaBox)
        replacement.insert(replacementPage, at: 0)
        let replacementURL = folder.appendingPathComponent("replacement.pdf")
        guard replacement.write(to: replacementURL) else { throw NSError(domain: "ReplacementPDFWrite", code: 1) }
        pdf.goToPreviousPage(nil)
        select(1, zoom: 1, path: replacementURL.path)
        if pdf.document === loaded || pdf.currentPage !== pdf.document?.page(at: 0) || abs(pdf.scaleFactor - 1) > 0.001 {
            failures.append("Explicit document replacement was overwritten")
        }
        if !failures.isEmpty { throw NSError(domain: "PDFViewportOwnership", code: failures.count, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "\n")]) }
        print("PASS production PDFKit page ownership: keys, destination links, previous-page actions, explicit model navigation, zoomed viewport preservation, within-page scrolling, and document changes")
        withExtendedLifetime(window) {}
    }
}
