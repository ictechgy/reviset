import Foundation
import AppKit
import SwiftUI
import PDFKit
import Combine

@MainActor private struct PDFControlPair:View {
    let model:AppModel
    let path:String
    let enabled:Bool
    let refresh:Int
    var body:some View {
        HStack(spacing:10) {
            pane(number:1,id:model.leftPageID)
            pane(number:2,id:model.rightPageID)
        }.accessibilityIdentifier("PDFControlPair.\(refresh)")
    }
    private func pane(number:Int,id:String)->some View {
        OriginalPDFView(keyboardEnabled:enabled,path:path,pageNumber:number,zoom:model.zoom,evidence:JSON(["page_id":id,"bbox":[0.2,0.2,0.3,0.1]]),page:JSON(["page_id":id,"width":500,"height":1500,"source_transform":[1,0,0,1,0,0]]))
    }
}

@main struct PDFPageOwnership {
    @MainActor static func main() throws {
        configureLegacyNativeLocalization()
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
        let retainedDocument=pdf.document,retainedPage=pdf.currentPage,retainedZoom=pdf.scaleFactor,retainedOrigin=pdf.documentView?.enclosingScrollView?.contentView.bounds.origin
        guard window.makeFirstResponder(pdf) else{throw NSError(domain:"VisiblePDFFocusUnavailable",code:1)}
        host.rootView=OriginalPDFView(keyboardEnabled:false,path:replacementURL.path,pageNumber:1,zoom:1,evidence:JSON(),page:JSON());host.layoutSubtreeIfNeeded();settle()
        guard !pdf.acceptsFirstResponder,!pdf.canBecomeKeyView,pdf.isAccessibilityHidden() else{throw NSError(domain:"HiddenPDFGateAbsent",code:1)}
        _ = window.makeFirstResponder(pdf)
        if let responder=window.firstResponder as? NSView,responder === pdf || responder.isDescendant(of:pdf) {throw NSError(domain:"HiddenPDFAllowedReacquisition",code:1)}
        for forward in [true,false] {for _ in 0..<12 {if forward {window.selectNextKeyView(nil)}else{window.selectPreviousKeyView(nil)};if let responder=window.firstResponder as? NSView,responder === pdf || responder.isDescendant(of:pdf) {throw NSError(domain:"NativeTraversalEnteredHiddenPDF",code:1)}}}
        guard pdf.document===retainedDocument,pdf.currentPage===retainedPage,pdf.scaleFactor==retainedZoom,pdf.documentView?.enclosingScrollView?.contentView.bounds.origin==retainedOrigin else{throw NSError(domain:"HiddenPDFGateChangedRetainedSource",code:1)}
        host.rootView=OriginalPDFView(keyboardEnabled:true,path:replacementURL.path,pageNumber:1,zoom:1,evidence:JSON(),page:JSON());host.layoutSubtreeIfNeeded();settle()
        guard !pdf.isAccessibilityHidden(),window.makeFirstResponder(pdf) else{throw NSError(domain:"PDFSourceInputGateDidNotRestore",code:1)}
        try checkPerPaneControls(path:url.path,folder:folder)
        if !failures.isEmpty { throw NSError(domain: "PDFViewportOwnership", code: failures.count, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "\n")]) }
        print("PASS production PDFKit page ownership: keys, destination links, previous-page actions, explicit model navigation, zoomed viewport preservation, within-page scrolling, and document changes")
        withExtendedLifetime(window) {}
    }
    @MainActor private static func checkPerPaneControls(path:String,folder:URL) throws {
        func requirePDFCaption(_ value:Bool)throws {if !value{throw NSError(domain:"GlobalGenericFitAndExplicitPDFWidthCaptionsMustBeDistinct",code:1)}}
        for (code,title,pdfTitle) in [("en","Fit","Fit width"),("ko","맞춤","너비 맞춤")] {
            let localizer=Localizer(language:code)
            try requirePDFCaption(localizer.string("doc.common.fit")==title && localizer.string("doc.pdf.fitWidth")==pdfTitle && title != pdfTitle)
        }
        let model=AppModel()
        model.projectID="pdf-control-project";model.report=JSON(["report_id":"fixed-pdf-report","revisions":[["revision_occurrence_id":"before"],["revision_occurrence_id":"after"]]])
        model.leftPageID="before-page";model.rightPageID="after-page";model.selectedChangeID="evidence-change"
        model.changes=[JSON(["change_id":"evidence-change","evidence":[["page_id":"before-page"],["page_id":"after-page"]]])]
        func root(_ refresh:Int=0,enabled:Bool=true)->PDFControlPair {PDFControlPair(model:model,path:path,enabled:enabled,refresh:refresh)}
        let host=NSHostingView(rootView:root())
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:1040,height:640),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.contentView=host
        func settle() {host.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.06));host.layoutSubtreeIfNeeded()}
        func panes(_ view:NSView)->[OriginalPDFPaneView] {if let pane=view as? OriginalPDFPaneView{return [pane]};return view.subviews.flatMap{panes($0)}}
        func require(_ condition:Bool,_ context:String) throws {if !condition{throw NSError(domain:"PDFPaneControls",code:1,userInfo:[NSLocalizedDescriptionKey:context])}}
        func snapshot() throws->Data {try JSON(["report":model.report.raw,"changes":model.changes.map(\.raw),"from":model.from,"to":model.to,"left":model.leftPageID,"right":model.rightPageID,"selected":model.selectedChangeID ?? "","zoom":model.zoom,"diff_mode":model.diffMode]).data()}
        settle()
        let pair=panes(host)
        try require(pair.count==2,"Expected two independent native PDF pane hosts")
        guard let before=pair.first(where:{$0.pdfView.representedPageID==model.leftPageID}),let after=pair.first(where:{$0.pdfView.representedPageID==model.rightPageID}) else{throw NSError(domain:"PDFControlPaneIdentity",code:1)}
        let left=before.pdfView,right=after.pdfView
        guard let leftDocument=left.document,let rightDocument=right.document,let leftPage=left.currentPage,let rightPage=right.currentPage,let leftMark=left.ownedEvidenceAnnotation,let rightMark=right.ownedEvidenceAnnotation,let leftClip=left.documentView?.enclosingScrollView?.contentView,let rightClip=right.documentView?.enclosingScrollView?.contentView else{throw NSError(domain:"PDFControlSourcesMissing",code:1)}
        let initialScale=left.scaleFactor
        try require(!left.autoScales && !right.autoScales && initialScale>left.bounds.height/1500,"Fresh pane should fit width once, independently of tall page height")
        let fixed=try snapshot()
        var modelEvents=0
        let subscription=model.objectWillChange.sink {modelEvents+=1}
        func sourceUnchanged() throws {
            try require(left.document===leftDocument && right.document===rightDocument && left.currentPage===leftPage && right.currentPage===rightPage,"Control replaced a PDF document or selected page")
            try require(left.ownedEvidenceAnnotation===leftMark && right.ownedEvidenceAnnotation===rightMark && leftPage.annotations.contains(where:{$0===leftMark}) && rightPage.annotations.contains(where:{$0===rightMark}),"Control replaced selected evidence annotation")
            try require(try snapshot()==fixed && modelEvents==0,"Control mutated the query, source selection, report, evidence, global zoom or published model")
        }
        left.scaleFactor=2;right.scaleFactor=2.6;settle()
        leftClip.scroll(to:NSPoint(x:100,y:650));leftClip.enclosingScrollView?.reflectScrolledClipView(leftClip)
        rightClip.scroll(to:NSPoint(x:130,y:720));rightClip.enclosingScrollView?.reflectScrolledClipView(rightClip);settle()
        let otherOrigin=rightClip.bounds.origin,otherScale=right.scaleFactor
        for button in [before.zoomOutButton,before.zoomInButton,before.fitWidthButton,after.zoomOutButton,after.zoomInButton,after.fitWidthButton] {
            try require(button.isEnabled && !button.visibleRect.isEmpty && button.toolTip==button.accessibilityLabel() && !(button.toolTip ?? "").isEmpty,"Native per-pane button is not visible, enabled or localized")
        }
        before.zoomInButton.performClick(nil);settle()
        try require(abs(left.scaleFactor-2.4)<0.001,"Native Zoom in did not change its own PDFKit scale")
        try sourceUnchanged()
        before.zoomOutButton.performClick(nil);settle()
        try require(abs(left.scaleFactor-2)<0.001,"Native Zoom out did not change its own PDFKit scale")
        try sourceUnchanged()
        before.fitWidthButton.performClick(nil);settle()
        let available=left.convert(leftClip.bounds,from:leftClip).width-left.pageBreakMargins.left-left.pageBreakMargins.right
        try require(abs(left.scaleFactor*500-available)<1 && !left.autoScales,"Native Fit width did not use the actual pane viewport: scale=\(left.scaleFactor), pageWidth=\(left.currentPage!.bounds(for:left.displayBox).width), clip=\(leftClip.bounds.width), available=\(available), pdfWidth=\(left.bounds.width), margins=\(left.pageBreakMargins), autoScales=\(left.autoScales)")
        try require(right.scaleFactor==otherScale && rightClip.bounds.origin==otherOrigin,"Before controls changed the other pane's manual zoom or viewport")
        try sourceUnchanged()
        let fitScale=left.scaleFactor
        after.zoomOutButton.performClick(nil);settle()
        try require(abs(right.scaleFactor-otherScale/1.2)<0.001 && left.scaleFactor==fitScale,"After controls did not act independently")
        try sourceUnchanged()
        // Retain the exact native hosts and manually scrolled viewports across
        // passive SwiftUI updates and a wider pane layout. No fit-on-resize.
        left.scaleFactor=2;right.scaleFactor=2.6;settle()
        leftClip.scroll(to:NSPoint(x:100,y:650));leftClip.enclosingScrollView?.reflectScrolledClipView(leftClip)
        rightClip.scroll(to:NSPoint(x:130,y:720));rightClip.enclosingScrollView?.reflectScrolledClipView(rightClip);settle()
        let leftOrigin=leftClip.bounds.origin,rightOrigin=rightClip.bounds.origin
        host.rootView=root(1);settle()
        window.setContentSize(NSSize(width:1100,height:680));settle()
        let retained=panes(host)
        try require(retained.contains(where:{$0===before}) && retained.contains(where:{$0===after}),"Passive redraw or layout reconstructed native PDF pane hosts")
        let originError=max(abs(leftClip.bounds.origin.x-leftOrigin.x),abs(leftClip.bounds.origin.y-leftOrigin.y),abs(rightClip.bounds.origin.x-rightOrigin.x),abs(rightClip.bounds.origin.y-rightOrigin.y))
        try require(left.document===leftDocument && right.document===rightDocument && left.currentPage===leftPage && right.currentPage===rightPage && left.scaleFactor==2 && right.scaleFactor==2.6 && originError<0.01,"Passive redraw or resize reset manual zoom, viewport, document or selected page: scales \(left.scaleFactor),\(right.scaleFactor); origin error \(originError); documents \(left.document===leftDocument),\(right.document===rightDocument); pages \(left.currentPage===leftPage),\(right.currentPage===rightPage)")
        try require(try snapshot()==fixed && modelEvents==0,"Passive pane layout mutated fixed query/source scope")
        host.rootView=root(2,enabled:false);settle()
        let hiddenScale=left.scaleFactor
        before.zoomInButton.performClick(nil);settle()
        try require(!before.zoomInButton.isEnabled && !before.zoomOutButton.isEnabled && !before.fitWidthButton.isEnabled && left.scaleFactor==hiddenScale,"Hidden source controls remained active")
        host.rootView=root(3);settle()
        try require(before.zoomInButton.isEnabled && left.scaleFactor==hiddenScale,"Restoring source controls reset manual zoom")
        let unavailableHost=NSHostingView(rootView:OriginalPDFView(path:path,pageNumber:1,zoom:1,evidence:JSON(),page:JSON()))
        let unavailableWindow=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:520,height:400),styleMask:[.titled],backing:.buffered,defer:false);unavailableWindow.isReleasedWhenClosed=false;unavailableWindow.contentView=unavailableHost
        func settleUnavailable() {unavailableHost.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.06));unavailableHost.layoutSubtreeIfNeeded()}
        settleUnavailable()
        guard let unavailable=panes(unavailableHost).first else{throw NSError(domain:"UnavailablePDFControlHostMissing",code:1)}
        try require(unavailable.zoomInButton.isEnabled,"Early-return fixture did not start with available native controls")
        unavailableHost.rootView=OriginalPDFView(keyboardEnabled:false,path:folder.appendingPathComponent("absent.pdf").path,pageNumber:1,zoom:1,evidence:JSON(),page:JSON());settleUnavailable()
        try require(panes(unavailableHost).first===unavailable && unavailable.pdfView.currentPage==nil && unavailable.pdfView.isAccessibilityHidden() && !unavailable.zoomInButton.isEnabled && !unavailable.zoomOutButton.isEnabled && !unavailable.fitWidthButton.isEnabled,"No-current-page return bypassed hidden source controls gate or availability refresh")
        unavailableHost.rootView=OriginalPDFView(path:folder.appendingPathComponent("absent.pdf").path,pageNumber:1,zoom:1,evidence:JSON(),page:JSON());settleUnavailable()
        try require(!unavailable.zoomInButton.isEnabled && !unavailable.zoomOutButton.isEnabled && !unavailable.fitWidthButton.isEnabled,"Visible unavailable PDF retained stale controls")
        unavailableWindow.close()
        // Passive root redraws above legitimately rebuild annotation instances.
        // Check the current physical evidence rather than the pre-redraw object.
        try require(left.document===leftDocument && right.document===rightDocument && left.currentPage===leftPage && right.currentPage===rightPage && left.scaleFactor==2 && right.scaleFactor==2.6 && left.qualifiedEvidence && right.qualifiedEvidence && left.ownedEvidenceAnnotation.map{leftPage.annotations.contains($0)}==true && right.ownedEvidenceAnnotation.map{rightPage.annotations.contains($0)}==true && (try snapshot())==fixed && modelEvents==0,"Unavailable pane test changed the retained physical sources, current evidence or model")
        let proof:[String:Any]=["native_per_pane_controls_visible_localized_and_performed":true,"control_ids":["Docver.pdf.zoomOut","Docver.pdf.zoomIn","Docver.pdf.fitWidth"],"ancestor_id":"Docver.pdf.pane","initial_fit_width_scale":initialScale,"fit_width_scale":fitScale,"manual_zoom_out_before":otherScale,"manual_zoom_out_after":otherScale/1.2,"pdf_hosts_documents_pages_retained":true,"control_actions_retain_exact_evidence_annotations":true,"other_pane_manual_zoom_and_viewport_retained":true,"passive_redraw_and_resize_retain_manual_zoom_and_viewports":true,"passive_viewport_max_origin_error":originError,"passive_viewport_origin_tolerance":0.01,"fixed_query_source_report_and_published_model_unchanged":true,"model_events_during_controls":modelEvents,"hidden_source_controls_disabled":true,"global_fit_caption_is_generic_in_both_locales":true,"pdf_fit_width_caption_remains_explicit_in_both_locales":true,"no_current_page_keeps_hidden_gate_and_updates_availability":true,"scope":"Controlled native button actions; no OS pointer, keyboard traversal or VoiceOver claim. Controls have no model or bridge reference."]
        if let path=ProcessInfo.processInfo.environment["DOCVER_TEST_PDF_CONTROLS_EVIDENCE_OUT"],!path.isEmpty {try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))}
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("pdf-controls-proof.json"))
        print("PASS native PDF per-pane zoom controls: retained PDFKit hosts/documents/pages/evidence, independent manual zoom, passive viewport preservation, fixed model scope")
        withExtendedLifetime((window,subscription)) {}
    }
}
