import SwiftUI
import AppKit
import PDFKit

@MainActor func renderWarningName(_ value:String)->String{
    if value.hasPrefix("font_substitution_possible:"){return L("doc.render.fontSubstitution", .verbatim(String(value.dropFirst("font_substitution_possible:".count))))}
    if value=="rendered_text_differs_from_ooxml_requires_source_review"{return L("doc.tail.render.someSourceTextUnconfirmedInConversion")}
    if value=="chart_smartart_or_other_object_render_requires_review"{return L("doc.tail.render.checkComplexObjectConversion")}
    if value=="standard_text_insets_materialized"{return L("doc.tail.render.standardTextInsetsApplied")}
    return value
}

func hasEstimatedPDFGeometry(_ element:JSON)->Bool {
    element["visibility_evidence"].array.contains { $0["method"].string == "pdf_text_geometry_estimated_or_unavailable" }
}

@MainActor func comparisonRoleName(_ element:JSON)->String {
    if element["method"].string == "pdf_page_annotation" {return L("doc.tail.text.annotationMetadataExcluded")}
    switch element["comparison_role"].string {
    case "selected":return L("doc.tail.text.usedForComparison")
    case "unresolved":
        if element["comparison_reason"].string == "contextual_ocr_disagreement_primary_retained" {return L("doc.tail.text.readingConflictComparisonWithheld")}
        return element["comparison_reason"].string == "borderline_ocr_context_unverified_primary_retained" ? L("doc.tail.text.contextReadingIncompleteComparisonWithheld"):L("doc.tail.text.comparisonWithheld")
    case "excluded":return element["provenance"].string == "inferred" ? L("doc.tail.text.estimateRetainedExcluded"):L("doc.tail.text.hiddenSourceExcluded")
    case "shadowed":
        if element["comparison_reason"].string == "roi_context_primary_superseded" {return L("doc.tail.ocr.initialRetainedComparedViaRereading")}
        return element["provenance"].string == "inferred" ? L("doc.tail.ocr.referenceSourceTextPreferred"):L("doc.tail.ocr.sourceRetainedComparedViaOcr")
    default:return L("doc.comparison.unknownRole", .verbatim(element["comparison_role"].string))
    }
}

@MainActor func ocrStatusName(_ code:String)->String {
    switch code {
    case "available":return L("doc.tail.ocr.recognitionComplete")
    case "not_needed":return L("doc.ocr.notNeeded")
    case "not_detected":return L("doc.tail.ocr.noReading")
    case "failed":return L("doc.tail.ocr.recognitionFailed")
    case "budget_exceeded":return L("doc.tail.ocr.processingLimitReached")
    case "unsupported_format":return L("doc.tail.ocr.imageFormatUnsupported")
    case "unsupported_dimensions":return L("doc.ocr.unsupportedDimensions")
    case "partial":return L("doc.ocr.partial")
    default:return code
    }
}

struct OcrContextEvidence: View {
    let element:JSON
    var reconsideration:JSON {element["ocr"]["reconsideration"]}
    var observation:JSON {reconsideration.isNull ? element["ocr"]["reconsideration_observation"]:reconsideration["observation"]}
    var body: some View {
        if !observation.isNull {
            DisclosureGroup(L("doc.tail.ocr.contextRereadingEvidence")) {
                VStack(alignment:.leading,spacing:7) {
                    if !reconsideration.isNull {
                        Text(L("doc.ocr.labelWithScore", .verbatim(element["comparison_reason"].string == "roi_evidence_or_primary_relationship_unverified" ? L("doc.tail.ocr.recordedInitialLinkUnverified"):L("doc.tail.ocr.initial")), .count(Int(reconsideration["primary_confidence"].number*100)))).font(.caption2).foregroundStyle(.secondary)
                        Text(reconsideration["primary_text"].string).textSelection(.enabled)
                    }
                    let statuses=["available":L("doc.tail.ocr.regionObservationCreated"),"budget_exceeded":L("doc.tail.ocr.processingLimitReached"),"unsupported_bitmap":L("doc.tail.ocr.imageFormatUnsupported"),"unsupported_background":L("doc.tail.ocr.backgroundReadingUnsupported"),"empty_ink":L("doc.tail.ocr.noTextInkObserved"),"failed":L("doc.tail.ocr.contextReadingFailed")]
                    Text(L("doc.ocr.contextStatus", .verbatim(statuses[observation["status"].string] ?? observation["status"].string))).font(.caption2).foregroundStyle(.secondary)
                    Text(observation["contexts"].array.isEmpty ? L("doc.tail.ocr.contextReadingIncompleteInitialRetainedAsEstimate"):L("doc.tail.ocr.sameRecognizerMultiConditionEstimate")).font(.caption2).foregroundStyle(.secondary)
                    ForEach(observation["contexts"].array.indices,id:\.self){i in
                        let context=observation["contexts"].array[i]
                        let names=["available":L("doc.tail.ocr.recognitionComplete"),"not_detected":L("doc.tail.ocr.noReading"),"contaminated":L("doc.tail.ocr.surroundingContentMixedIn"),"edge_cut":L("doc.tail.ocr.clippedAtBoundary"),"ambiguous":L("doc.tail.ocr.conflictingAlternatives"),"failed":L("doc.tail.ocr.recognitionFailed"),"budget_exceeded":L("doc.tail.ocr.processingLimitReached")]
                        let languages=context["languages"].array.map{localizedOCRLanguageCode($0.string)}.joined(separator:"+")
                        VStack(alignment:.leading,spacing:3) {
                            Text(L("doc.ocr.condition", .integer(i+1), .verbatim(languages), .integer(Int(context["scale"].number)), .verbatim(context["padding"].number>0.5 ? L("doc.tail.ocr.wideSurroundingContext"):L("doc.tail.ocr.narrowSurroundingContext")))).font(.caption2).foregroundStyle(.secondary)
                            Text(names[context["status"].string] ?? context["status"].string).font(.caption2).foregroundStyle(.secondary)
                            ForEach(context["observations"].array.indices,id:\.self){n in
                                Text(context["observations"].array[n]["text"].string).font(.caption).textSelection(.enabled)
                                Text(L("doc.tail.ocr.recognitionScore", .count(Int(context["observations"].array[n]["confidence"].number*100)))).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.top,4).frame(maxWidth:.infinity,alignment:.leading)
            }.font(.caption)
        }
    }
}

func canHighlightEvidence(_ evidence:JSON,page:JSON)->Bool {
    let b=evidence["bbox"].array.map(\.number)
    guard b.count==4 && b.allSatisfy({$0.isFinite}) && b[2]>0 && b[3]>0 else{return false}
    let observation=evidence["observation_id"].string
    return observation.isEmpty || !page["elements"].array.contains { $0["observation_id"].string==observation && hasEstimatedPDFGeometry($0) }
}

// Read-only native-host diagnostics for the opt-in packaged-app probe. These
// record the actual supplied evidence and installed annotation, never invent a
// rectangle when source/geometry guards reject it.
final class OriginalPDFHostView:PDFView {
    var sourceKeyboardEnabled=true
    override var acceptsFirstResponder:Bool {sourceKeyboardEnabled && super.acceptsFirstResponder}
    override var canBecomeKeyView:Bool {sourceKeyboardEnabled && super.canBecomeKeyView}
    override func becomeFirstResponder()->Bool {sourceKeyboardEnabled && super.becomeFirstResponder()}

    var representedPageID=""
    var representedEvidencePageID=""
    var qualifiedEvidence=false
    var sourceTransformCount=0
    weak var ownedEvidenceAnnotation:PDFAnnotation?
}

struct OriginalPDFView: NSViewRepresentable {
    var keyboardEnabled=true
    let path: String
    let pageNumber: Int
    let zoom: Double
    let evidence: JSON
    let page: JSON
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject {
        var path = ""; var pageNumber = -1; var zoom = -1.0
        var marks: [(PDFPage, PDFAnnotation)] = []
        var selectedPage: PDFPage?
        private weak var observedView: PDFView?
        private weak var clipView: NSClipView?
        private var viewportOrigin: NSPoint?
        private var viewportScale = 0.0
        private var viewportGeneration = 0
        private var pendingCaptureGeneration: Int?
        private var restoringViewport = false
        func observe(_ view: PDFView) {
            observedView = view
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        }
        func resetViewport() {
            viewportGeneration &+= 1
            pendingCaptureGeneration = nil
            restoringViewport = false
            viewportOrigin = nil
        }
        func observeViewport(_ view: PDFView) {
            let clip = view.documentView?.enclosingScrollView?.contentView
            if clipView !== clip {
                if let clipView { NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clipView) }
                clipView = clip
                clip?.postsBoundsChangedNotifications = true
                if let clip { NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: clip) }
            }
            captureViewport(view)
        }
        private func captureViewport(_ view: PDFView) {
            guard !restoringViewport, let selectedPage, view.currentPage === selectedPage,
                  let clipView else { return }
            viewportOrigin = clipView.bounds.origin
            viewportScale = view.scaleFactor
        }
        @objc private func boundsChanged(_ notification: Notification) {
            guard !restoringViewport else { return }
            let generation = viewportGeneration
            guard pendingCaptureGeneration != generation else { return }
            pendingCaptureGeneration = generation
            // PDFKit can scroll to the next page's top before publishing its page
            // change. Only retain a viewport after that navigation has settled.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewportGeneration == generation, let view = self.observedView else { return }
                self.pendingCaptureGeneration = nil
                self.captureViewport(view)
            }
        }
        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let selectedPage,
                  selectedPage.document === view.document, view.currentPage !== selectedPage else { return }
            let origin = viewportOrigin, scale = viewportScale
            viewportGeneration &+= 1
            pendingCaptureGeneration = nil
            let generation = viewportGeneration
            restoringViewport = true
            // The model owns source/reference associations. PDF links and native
            // keys cannot independently change the page behind its evidence.
            view.go(to: selectedPage)
            // Destination actions can still scroll after PageChanged returns.
            // Restore the selected page's viewport when the action has finished.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.viewportGeneration == generation else { return }
                if view.currentPage === self.selectedPage, let origin, view.scaleFactor == scale, let clip = self.clipView {
                    clip.scroll(to: origin)
                    clip.enclosingScrollView?.reflectScrolledClipView(clip)
                }
                self.restoringViewport = false
                self.captureViewport(view)
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
    func makeNSView(context: Context) -> PDFView {
        let view = OriginalPDFHostView(); view.displayMode = .singlePage; view.displayDirection = .vertical
        view.displaysPageBreaks = true; view.pageShadowsEnabled = true; view.backgroundColor = NSColor.underPageBackgroundColor
        view.minScaleFactor = 0.1; view.maxScaleFactor = 8
        context.coordinator.observe(view); return view
    }
    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.selectedPage = nil
        coordinator.resetViewport()
    }
    func updateNSView(_ view: PDFView, context: Context) {
        (view as? OriginalPDFHostView)?.sourceKeyboardEnabled=keyboardEnabled;view.setAccessibilityHidden(!keyboardEnabled)
        if !keyboardEnabled {resignHiddenSourceFirstResponder(in:view)}
        let sourceChanged=context.coordinator.path != path
        let selectionChanged = sourceChanged || context.coordinator.pageNumber != pageNumber || context.coordinator.zoom != zoom
        if selectionChanged { context.coordinator.resetViewport() }
        context.coordinator.selectedPage = nil
        if sourceChanged { view.document = PDFDocument(url: URL(fileURLWithPath: path)); context.coordinator.path = path }
        for (p, a) in context.coordinator.marks { p.removeAnnotation(a); view.annotationsChanged(on: p) }; context.coordinator.marks = []
        guard let current = view.document?.page(at: max(0, pageNumber - 1)) else { return }
        context.coordinator.selectedPage = current
        if sourceChanged || context.coordinator.pageNumber != pageNumber || context.coordinator.zoom != zoom || view.currentPage !== current {
            view.autoScales = zoom == 0;view.go(to:current);if zoom>0{view.scaleFactor=zoom}
            context.coordinator.pageNumber=pageNumber;context.coordinator.zoom=zoom
        }
        context.coordinator.observeViewport(view)
        let b = evidence["bbox"].array.map(\.number), t = page["source_transform"].array.map(\.number)
        if let host=view as? OriginalPDFHostView {
            host.representedPageID=page["page_id"].string;host.representedEvidencePageID=evidence["page_id"].string
            host.qualifiedEvidence=canHighlightEvidence(evidence,page:page);host.sourceTransformCount=t.count;host.ownedEvidenceAnnotation=nil
        }
        if canHighlightEvidence(evidence,page:page) && t.count == 6 {
            let det = t[0] * t[3] - t[1] * t[2]
            if abs(det) > 0.000001 {
                let x = b[0] * page["width"].number, y = b[1] * page["height"].number, w = b[2] * page["width"].number, h = b[3] * page["height"].number
                let points = [(x,y),(x+w,y),(x,y+h),(x+w,y+h)].map { p -> CGPoint in
                    let px = p.0 - t[4], py = p.1 - t[5]
                    return CGPoint(x: (t[3]*px-t[2]*py)/det, y: (-t[1]*px+t[0]*py)/det)
                }
                let xs = points.map(\.x), ys = points.map(\.y)
                let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()!-xs.min()!, height: ys.max()!-ys.min()!)
                let mark = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
                mark.shouldDisplay=true;current.displaysAnnotations=true
                mark.color = NSColor.systemBlue.withAlphaComponent(0.85); let border = PDFBorder(); border.lineWidth = 1.5; mark.border = border
                current.addAnnotation(mark); context.coordinator.marks.append((current,mark));(view as? OriginalPDFHostView)?.ownedEvidenceAnnotation=mark;view.annotationsChanged(on:current);view.needsDisplay=true
            }
        }
    }
}
struct StructureCanvas: NSViewRepresentable {
    var language:String=LanguagePreferences.shared.effectiveLanguage
    let page: JSON; let evidence: JSON
    final class Canvas: NSView {
        var page = JSON(); var evidence = JSON()
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill(); bounds.fill()
            for e in page["elements"].array {
                let b = e["bbox"].array.map(\.number); guard b.count == 4 else { continue }
                let rect = NSRect(x: b[0]*bounds.width, y: b[1]*bounds.height, width: b[2]*bounds.width, height: b[3]*bounds.height)
                if e["kind"].string == "text" || e["kind"].string == "table_cell" {
                    if e["kind"].string == "table_cell" { NSColor.gridColor.setStroke(); NSBezierPath(rect: rect).stroke() }
                    let contentRect=rect.insetBy(dx:2,dy:1)
                    guard contentRect.width>0,contentRect.height>0 else{continue}
                    let text=e["text"].string,lines=max(1,text.split(separator:"\n",omittingEmptySubsequences:false).count)
                    let initial=NSFont.systemFont(ofSize:max(0.1,min(35,bounds.width*0.029)))
                    let lineHeight=initial.ascender-initial.descender+initial.leading
                    let fit=min(1,contentRect.height/(CGFloat(lines)*lineHeight))
                    let font=NSFont.systemFont(ofSize:initial.pointSize*fit*0.95)
                    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
                    (text as NSString).draw(in: contentRect, withAttributes: [.font:font,.foregroundColor:NSColor.black,.paragraphStyle:style])
                } else if e["kind"].string == "image" || e["kind"].string == "unsupported" {
                    NSColor.systemGray.withAlphaComponent(0.12).setFill(); rect.fill()
                    ((e["kind"].string == "image" ? L("doc.tail.element.image") : L("doc.tail.element.semanticExtractionUnsupported")) as NSString).draw(in: rect, withAttributes: [.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.gray])
                }
            }
            let pixel=1/max(1,window?.backingScaleFactor ?? 1)
            NSColor.gray.withAlphaComponent(0.45).setStroke()
            let outline=NSBezierPath(rect:bounds.insetBy(dx:pixel/2,dy:pixel/2));outline.lineWidth=pixel;outline.stroke()
            let b = evidence["bbox"].array.map(\.number)
            if canHighlightEvidence(evidence,page:page) { NSColor.systemBlue.setStroke(); let p = NSBezierPath(rect: NSRect(x:b[0]*bounds.width,y:b[1]*bounds.height,width:b[2]*bounds.width,height:b[3]*bounds.height)); p.lineWidth=2;p.stroke() }
        }
    }
    func makeNSView(context: Context) -> Canvas { Canvas() }
    func updateNSView(_ view: Canvas, context: Context) { view.page=page;view.evidence=evidence;view.needsDisplay=true }
}
// Opt-in smoke observes the evaluated SwiftUI picker binding/title separately
// from the actual AppKit text entry; closed in-process AX omits Picker captions.
final class PageColumnControlObservationView:NSView {
    var occurrence=""
    var selection=""
    var title=""
    override func hitTest(_ point:NSPoint)->NSView? {nil}
}
@MainActor func pageColumnControlObservations(in view:NSView)->[PageColumnControlObservationView] {
    ((view as? PageColumnControlObservationView).map{[$0]} ?? [])+view.subviews.flatMap{pageColumnControlObservations(in:$0)}
}
private struct PageColumnControlObservation:NSViewRepresentable {
    let kind:String
    let occurrence:String
    let selection:String
    let title:String
    func makeNSView(context:Context)->PageColumnControlObservationView {PageColumnControlObservationView()}
    func updateNSView(_ view:PageColumnControlObservationView,context:Context) {
        view.identifier=NSUserInterfaceItemIdentifier("Reviset.document."+kind+"."+occurrence);view.occurrence=occurrence;view.selection=selection;view.title=title
    }
}
private struct PageColumnReadIdentity:Equatable {
    let report:String
    let occurrence:String
    let page:String
}
private struct PageColumnSelectionIdentity:Equatable {
    let source:PageColumnReadIdentity
    let number:Int?
}
struct PageColumn: View {
    @EnvironmentObject var model: AppModel
    let revision: JSON; let side: String
    @Binding var pageID: String
    @State private var payload = JSON()
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    @State private var loadingPage = false
    @State private var loadedSource:PageColumnReadIdentity?
    @State private var pageInput = ""
    @State private var rawOpen = false
    var pages: [JSON] { model.primaryPages(revision) }
    var payloadReady:Bool {!payload.isNull && !pageID.isEmpty && !loadingPage && failure.isEmpty && loadedSource==readIdentity && payload["page"]["page_id"].string==pageID}
    var current: JSON { pages.first { $0["page_id"].string == pageID } ?? JSON() }
    private var readIdentity:PageColumnReadIdentity {PageColumnReadIdentity(report:model.report["report_id"].string,occurrence:revision["revision_occurrence_id"].string,page:pageID)}
    private var currentPageNumber:Int? {guard !current.isNull,current["page"].int>0 else{return nil};return current["page"].int}
    private var selectionIdentity:PageColumnSelectionIdentity {PageColumnSelectionIdentity(source:readIdentity,number:currentPageNumber)}
    private var currentPageInput:String {currentPageNumber.map(String.init) ?? ""}
    private func pickerTitle(_ page:JSON)->String {"p.\(page["page"].int) · \(page["text"].string.prefix(24))"}
    var evidence: JSON { model.selected["evidence"].array.first { $0["page_id"].string == pageID || (!current["appearance"]["source_page_id"].string.isEmpty && $0["page_id"].string == current["appearance"]["source_page_id"].string) } ?? JSON() }
    var body: some View {
        VStack(spacing: 9) {
            HStack { Text(side + " · " + (model.revisions.firstIndex(where:{$0["revision_occurrence_id"].string==revision["revision_occurrence_id"].string}).map{versionDisplayName($0,revision)} ?? revision["label"].string)).font(.caption.weight(.semibold)); Spacer()
                Picker(L("doc.common.page"), selection: Binding(get:{pageID},set:{model.navigatePage($0,in:revision["revision_occurrence_id"].string)})) { Text(L("doc.tail.source.noSourceText")).tag(""); ForEach(pages) { p in Text(pickerTitle(p)).tag(p["page_id"].string) } }.labelsHidden().frame(maxWidth:260).background(PageColumnControlObservation(kind:"pagePicker",occurrence:revision["revision_occurrence_id"].string,selection:pageID,title:current.isNull ? L("doc.tail.source.noSourceText"):pickerTitle(current)))
            }
            HStack(spacing: 8) {
                Button { go(current["page"].int-1) } label: { Image(systemName:"chevron.left") }.disabled(current.isNull || current["page"].int <= 1).accessibilityLabel(L("doc.tail.sourcePage.previous"))
                TextField(L("doc.common.page"), text:$pageInput).frame(width:48).multilineTextAlignment(.center).onSubmit { if let number=Int(pageInput) {go(number)}else{pageInput=currentPageInput} }.disabled(currentPageNumber==nil).accessibilityLabel(L("doc.page.sideNumber", .verbatim(side))).background(PageColumnControlObservation(kind:"pageNumber",occurrence:revision["revision_occurrence_id"].string,selection:pageID,title:currentPageInput))
                Text("/ \(pages.count)").foregroundStyle(.secondary).font(.caption)
                Button { go(current["page"].int+1) } label: { Image(systemName:"chevron.right") }.disabled(current.isNull || current["page"].int>=pages.count).accessibilityLabel(L("doc.tail.sourcePage.next"))
                Spacer(); Text(loadingPage ? (payload.isNull ? L("doc.tail.sourcePage.checking"):L("doc.tail.sourcePage.showingPreviousVerifyingNext")) : !payloadReady ? L("doc.tail.sourcePage.infoNeedsCheck") : payload["source"]["origin"].string == "reference_pdf" ? (payload["page"]["appearance"]["association"].string == "human_confirmed" ? L("doc.tail.renderSource.suppliedPdfUserLinkedReference"):L("doc.tail.renderSource.suppliedPdfPageMappingInferred")) : payload["source"]["origin"].string == "pptx_converted" ? L("doc.tail.renderSource.pptxLibreOffice") : payload["source"]["kind"].string == "pdf" ? L("doc.tail.renderSource.originalPdfPdfKit") : L("doc.tail.renderSource.structureViewNoRender")).font(.caption).foregroundStyle(.secondary)
                if model.isBundle(revision) {Button{model.openBundle(revision,source:pageID)}label:{Image(systemName:"link")}.help(model.bundleEditingUnavailable == nil ? L("doc.tail.suppliedPdf.editPageLinksForVersion"):L("doc.tail.suppliedPdf.viewReportLinksAndHistory")).disabled(model.busy || model.loading).accessibilityLabel(L("doc.tail.suppliedPdf.reviewPageLinksAndHistory"))}
                if model.sidecarConfigured && revision["assets"].array.contains(where:{$0["format"].string=="pptx"&&$0["asset_id"].string==current["asset_id"].string}) {
                    Button {model.openSidecar(revision,page:pageID)} label:{Label(L("doc.tail.render.referenceRender"),systemImage:"rectangle.on.rectangle")}
                        .help(L("doc.tail.render.viewOnlyofficeConversionForReference")).disabled(model.busy||model.loading)
                }
            }.controlSize(.small)
            if payloadReady && !evidence.isNull && ["reference_pdf","pptx_converted"].contains(payload["source"]["origin"].string) {
                Text(evidence["method"].string == "provided_pdf_native_raster" ? (payload["page"]["appearance"]["association"].string == "human_confirmed" ? L("doc.tail.suppliedPdf.visualEvidenceUserLinkedFidelityUnverified"):L("doc.tail.suppliedPdf.visualEvidencePageMappingInferred")) : L("doc.tail.evidence.pptxCoordinatesUnverifiedCheckExtractedText")).font(.caption).foregroundStyle(.orange)
            }
            GeometryReader { geometry in
                if current.isNull { ContentUnavailableView(L("doc.tail.evidence.noCorrespondingSourceText"), systemImage:"doc", description:Text(L("doc.tail.evidence.distinguishObservedAbsenceFromDeletion"))) }
                else if !failure.isEmpty { ContentUnavailableView(L("doc.tail.page.openFailed"),systemImage:"exclamationmark.triangle",description:Text(failure)) }
                else if payload.isNull { ProgressView(L("doc.tail.sourcePage.loading")).frame(maxWidth:.infinity,maxHeight:.infinity) }
                else if payload["source"]["kind"].string == "pdf" {
                    OriginalPDFView(keyboardEnabled:model.effectiveDiffMode=="source",path:payload["source"]["path"].string,pageNumber:payload["display_page_number"].isNull ? payload["page"]["page"].int : payload["display_page_number"].int,zoom:model.zoom,evidence:payloadReady && payload["source"]["origin"].string == "original" ? evidence : JSON(),page:payload["display_page"].isNull ? payload["page"] : payload["display_page"])
                } else if let size=fittedPageSize(width:payload["page"]["width"].number,height:payload["page"]["height"].number,available:geometry.size,inset:8) {
                    ScrollView([.horizontal,.vertical]) {
                        let scale = model.zoom == 0 ? 1 : model.zoom
                        VStack { Spacer(minLength:0); StructureCanvas(language:LanguagePreferences.shared.effectiveLanguage,page:payload["page"],evidence:payloadReady ? evidence:JSON()).frame(width:size.width*scale,height:size.height*scale).shadow(color:.black.opacity(0.08),radius:5); Spacer(minLength:0) }.frame(minWidth:geometry.size.width,minHeight:geometry.size.height)
                    }
                } else {ContentUnavailableView(L("doc.tail.page.sizeUndeterminable"),systemImage:"exclamationmark.triangle")}
            }.background(Color(nsColor:.windowBackgroundColor).overlay(Color.primary.opacity(0.045))).clipShape(RoundedRectangle(cornerRadius:5))
                .overlay {if loadingPage && !payload.isNull && failure.isEmpty {VStack(spacing:6){ProgressView();Text(L("doc.tail.sourcePage.previousShownWhileVerifyingNext")).font(.caption)}.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8))}}.allowsHitTesting(!loadingPage)
            DisclosureGroup(L("doc.tail.inspector.extractedContentTablesDisplayState"),isExpanded:$rawOpen) {
                if payloadReady {ScrollView { LazyVStack(alignment:.leading,spacing:10) {
                    Text(L("doc.tail.inspector.extractionAndOcrRetainedSeparately")).font(.caption).foregroundStyle(.secondary)
                    if !payload["page"]["ocr"].isNull {Text(L("doc.tail.ocr.localStatusVerifyAgainstSource", .verbatim(ocrStatusName(payload["page"]["ocr"]["status"].string)))).font(.caption).foregroundStyle(.orange)}
                    if ["unsupported_format","unsupported_dimensions","budget_exceeded","ambiguous_boundaries","partial"].contains(payload["page"]["ocr"]["grid_status"].string) {Text(L("doc.tail.table.gridBoundsUnconfirmedCheckRowsColumns")).font(.caption).foregroundStyle(.orange)}
                    ForEach(payload["source"]["warnings"].array.indices,id:\.self){i in Text(renderWarningName(payload["source"]["warnings"].array[i].string)).font(.caption).foregroundStyle(.orange)}
                    ForEach(payload["page"]["elements"].array) { e in
                        VStack(alignment:.leading,spacing:4) {
                            Text(e["method"].string == "pdf_page_annotation" ? (e["source_ref"].string.hasSuffix("/StrikeOut") ? L("doc.tail.strikethroughAnnotationDisplayUnverified") : e["source_ref"].string.hasSuffix("/Redact") ? L("doc.tail.deletionIntentAnnotationApplyCheck") : L("doc.tail.pdfAnnotationRegionSourceCheckRequired")) : e["text"].string).textSelection(.enabled)
                            if hasEstimatedPDFGeometry(e) { Text(e["visibility"].string == "hidden_render_mode" ? L("doc.tail.sourcePositionUnverifiedEstimatedCoordsHiddenMode") : L("doc.tail.sourcePositionDisplayUnverifiedFontCoordsEstimated")).font(.caption).foregroundStyle(.orange) }
                            HStack { Text(e["visibility"].string.isEmpty ? L("doc.tail.sourceStructure") : appearanceStateName(e["visibility"].string))
                                if e["method"].string == "vision_ocr" {Text(L("doc.ocr.labelWithScore", .verbatim(e["ocr"]["reconsideration"].isNull ? L("doc.tail.initialOcrEstimate"):L("doc.tail.contextualRereadEstimate")), .count(Int(e["ocr"]["confidence"].number*100))))}
                                if !e["comparison_role"].string.isEmpty {Text(comparisonRoleName(e))}
                                if !e["table"].isNull { Text(e["table"]["origin"].string == "ooxml_table" ? L("doc.tail.pptxCellStructureObserved") : e["table"]["origin"].string == "vision_table_inferred" ? L("doc.tail.screenOcrTableCellEstimate") : L("doc.tail.pdfGridEstimate")) }
                            }.font(.caption2).foregroundStyle(e["visibility"].string.contains("occluded") || e["visibility"].string.contains("struck") ? .orange : .secondary)
                            if e["method"].string == "vision_ocr" {OcrContextEvidence(element:e)}
                        }.padding(8).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:4))
                    }
                    Text(L("doc.tail.speakerNotes")).font(.headline); Text(notesDisplayText(payload["page"]))
                }.frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:220)}else{Text(loadingPage ? L("doc.tail.verifyingSelectedPageExtract"):L("doc.tail.currentPageExtractReadFailed")).foregroundStyle(.secondary)}
            }.font(.caption).disabled(!payloadReady)
        }.padding(12).onChange(of:selectionIdentity,initial:true){pageInput=currentPageInput}.task(id:readIdentity) {
            let source=readIdentity
            if loadedSource?.report != source.report {payload=JSON()}
            failure="";loadingPage=true
            defer{if !Task.isCancelled{loadingPage=false}}
            guard !source.page.isEmpty else{payload=JSON();return}
            do {let result=try await model.page(source.page);if !Task.isCancelled,readIdentity==source{payload=result;loadedSource=source}}catch{if !Task.isCancelled,readIdentity==source{payload=JSON();failureMessage=bridgeErrorMessage(error)}}
        }
    }
    func go(_ number: Int) { if number>0,let p=pages.first(where:{$0["page"].int==number}){model.navigatePage(p["page_id"].string,in:revision["revision_occurrence_id"].string);pageInput=String(number)}else{pageInput=currentPageInput} }
}
