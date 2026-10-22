import SwiftUI
import AppKit
import PDFKit

func renderWarningName(_ value:String)->String{
    if value.hasPrefix("font_substitution_possible:"){return "대체될 수 있는 글꼴: "+String(value.dropFirst("font_substitution_possible:".count))}
    if value=="rendered_text_differs_from_ooxml_requires_source_review"{return "변환 화면에서 일부 원문 텍스트를 확인하지 못했습니다."}
    if value=="chart_smartart_or_other_object_render_requires_review"{return "차트·SmartArt 등 복합 개체의 변환 결과를 확인하세요."}
    if value=="standard_text_insets_materialized"{return "텍스트의 기본 여백을 표준값으로 적용한 변환 화면입니다."}
    return value
}

func hasEstimatedPDFGeometry(_ element:JSON)->Bool {
    element["visibility_evidence"].array.contains { $0["method"].string == "pdf_text_geometry_estimated_or_unavailable" }
}

func comparisonRoleName(_ element:JSON)->String {
    if element["method"].string == "pdf_page_annotation" {return "주석 메타데이터 · 텍스트 비교 제외"}
    switch element["comparison_role"].string {
    case "selected":return "비교에 사용"
    case "unresolved":
        if element["comparison_reason"].string == "contextual_ocr_disagreement_primary_retained" {return "판독 충돌 · 비교 보류"}
        return element["comparison_reason"].string == "borderline_ocr_context_unverified_primary_retained" ? "문맥 판독 미완료 · 비교 보류":"비교 보류"
    case "excluded":return element["provenance"].string == "inferred" ? "추정값 보존 · 비교 제외":"숨은 원문 · 비교 제외"
    case "shadowed":
        if element["comparison_reason"].string == "roi_context_primary_superseded" {return "최초 OCR 보존 · 재판독으로 비교"}
        return element["provenance"].string == "inferred" ? "참고 OCR · 원문 우선":"원문 보존 · OCR로 비교"
    default:return ""
    }
}

struct OcrContextEvidence: View {
    let element:JSON
    var reconsideration:JSON {element["ocr"]["reconsideration"]}
    var observation:JSON {reconsideration.isNull ? element["ocr"]["reconsideration_observation"]:reconsideration["observation"]}
    var body: some View {
        if !observation.isNull {
            DisclosureGroup("문맥 재판독 근거") {
                VStack(alignment:.leading,spacing:7) {
                    if !reconsideration.isNull {
                        Text((element["comparison_reason"].string == "roi_evidence_or_primary_relationship_unverified" ? "기록된 최초 OCR · 연결 미검증":"최초 OCR")+" · \(Int(reconsideration["primary_confidence"].number*100))점").font(.caption2).foregroundStyle(.secondary)
                        Text(reconsideration["primary_text"].string).textSelection(.enabled)
                    }
                    let statuses=["available":"영역 관측 생성","budget_exceeded":"처리 한도 도달","unsupported_bitmap":"영상 형식 미지원","unsupported_background":"배경 판독 미지원","empty_ink":"문자 잉크 미관측","failed":"문맥 판독 실패"]
                    Text("문맥 판독 상태 · "+(statuses[observation["status"].string] ?? "상태 미상")).font(.caption2).foregroundStyle(.secondary)
                    Text(observation["contexts"].array.isEmpty ? "문맥 판독을 완료하지 못했습니다. 최초 OCR은 추정값으로 보존합니다.":"같은 인식기의 여러 조건에서 얻은 추정입니다. 원본 화면과 대조하세요.").font(.caption2).foregroundStyle(.secondary)
                    ForEach(observation["contexts"].array.indices,id:\.self){i in
                        let context=observation["contexts"].array[i]
                        let names=["available":"인식 완료","not_detected":"판독값 없음","contaminated":"주변 내용 혼입","edge_cut":"경계 잘림","ambiguous":"대안 충돌","failed":"인식 실패","budget_exceeded":"처리 한도 도달"]
                        let languages=context["languages"].array.map{$0.string == "ko-KR" ? "한국어":"영어"}.joined(separator:"+")
                        VStack(alignment:.leading,spacing:3) {
                            Text("조건 \(i+1) · "+languages+" · \(Int(context["scale"].number))배 · "+(context["padding"].number>0.5 ? "넓은 주변":"가까운 주변")).font(.caption2).foregroundStyle(.secondary)
                            Text(names[context["status"].string] ?? "상태 미상").font(.caption2).foregroundStyle(.secondary)
                            ForEach(context["observations"].array.indices,id:\.self){n in
                                Text(context["observations"].array[n]["text"].string).font(.caption).textSelection(.enabled)
                                Text("인식 점수 \(Int(context["observations"].array[n]["confidence"].number*100))점").font(.caption2).foregroundStyle(.secondary)
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

struct OriginalPDFView: NSViewRepresentable {
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
        let view = PDFView(); view.displayMode = .singlePage; view.displayDirection = .vertical
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
                current.addAnnotation(mark); context.coordinator.marks.append((current,mark));view.annotationsChanged(on:current);view.needsDisplay=true
            }
        }
    }
}
struct StructureCanvas: NSViewRepresentable {
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
                    ((e["kind"].string == "image" ? "이미지" : "의미 추출 미지원") as NSString).draw(in: rect, withAttributes: [.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.gray])
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
struct PageColumn: View {
    @EnvironmentObject var model: AppModel
    let revision: JSON; let side: String
    @Binding var pageID: String
    @State private var payload = JSON()
    @State private var failure = ""
    @State private var loadingPage = false
    @State private var loadedReport = ""
    @State private var pageInput = "1"
    @State private var rawOpen = false
    var pages: [JSON] { model.primaryPages(revision) }
    var payloadReady:Bool {!payload.isNull && !pageID.isEmpty && !loadingPage && failure.isEmpty && loadedReport==model.report["report_id"].string && payload["page"]["page_id"].string==pageID}
    var current: JSON { pages.first { $0["page_id"].string == pageID } ?? JSON() }
    var evidence: JSON { model.selected["evidence"].array.first { $0["page_id"].string == pageID || (!current["appearance"]["source_page_id"].string.isEmpty && $0["page_id"].string == current["appearance"]["source_page_id"].string) } ?? JSON() }
    var body: some View {
        VStack(spacing: 9) {
            HStack { Text(side + " · " + revision["label"].string).font(.headline); Spacer()
                Picker("페이지", selection: Binding(get:{pageID},set:{model.navigatePage($0,in:revision["revision_occurrence_id"].string)})) { Text("원문 없음").tag(""); ForEach(pages) { p in Text("p.\(p["page"].int) · \(p["text"].string.prefix(24))").tag(p["page_id"].string) } }.labelsHidden().frame(maxWidth:260)
            }
            HStack(spacing: 8) {
                Button { go(current["page"].int-1) } label: { Image(systemName:"chevron.left") }.disabled(current.isNull || current["page"].int <= 1).accessibilityLabel("이전 원문 페이지")
                TextField("페이지", text:$pageInput).frame(width:48).multilineTextAlignment(.center).onSubmit { go(Int(pageInput) ?? current["page"].int) }.accessibilityLabel(side+" 원문 페이지 번호")
                Text("/ \(pages.count)").foregroundStyle(.secondary).font(.caption)
                Button { go(current["page"].int+1) } label: { Image(systemName:"chevron.right") }.disabled(current.isNull || current["page"].int>=pages.count).accessibilityLabel("다음 원문 페이지")
                Spacer(); Text(loadingPage ? (payload.isNull ? "원문 페이지를 확인하고 있습니다…":"이전 페이지 표시 · 다음 페이지 검증 중") : !payloadReady ? "페이지 정보 확인 필요" : payload["source"]["origin"].string == "reference_pdf" ? (payload["page"]["appearance"]["association"].string == "human_confirmed" ? "제공 PDF · 사용자 연결 · 참고용":"제공 PDF · 페이지 대응 추정") : payload["source"]["origin"].string == "pptx_converted" ? "PPTX 렌더 · LibreOffice" : payload["source"]["kind"].string == "pdf" ? "원본 PDF · PDFKit" : "구조 보기 · 렌더 없음").font(.caption).foregroundStyle(.secondary)
                if model.isBundle(revision) {Button{model.openBundle(revision,source:pageID)}label:{Image(systemName:"link")}.help(model.bundleEditingUnavailable == nil ? "이 버전의 PPTX와 제공 PDF 페이지 연결 수정":"이 보고서의 제공 PDF 연결·이력 조회").disabled(model.busy || model.loading).accessibilityLabel("제공 PDF 페이지 연결·이력 확인")}
                if model.sidecarConfigured && revision["assets"].array.contains(where:{$0["format"].string=="pptx"&&$0["asset_id"].string==current["asset_id"].string}) {
                    Button {model.openSidecar(revision,page:pageID)} label:{Label("참고 렌더",systemImage:"rectangle.on.rectangle")}
                        .help("ONLYOFFICE의 별도 변환 화면을 참고용으로 확인").disabled(model.busy||model.loading)
                }
            }.controlSize(.small)
            if payloadReady && !evidence.isNull && ["reference_pdf","pptx_converted"].contains(payload["source"]["origin"].string) {
                Text(evidence["method"].string == "provided_pdf_native_raster" ? (payload["page"]["appearance"]["association"].string == "human_confirmed" ? "제공 PDF의 화면 근거입니다. 사용자가 페이지를 연결했으며 PowerPoint 원본 충실도는 미검증입니다.":"제공 PDF의 화면 근거입니다. PPTX와의 페이지 대응은 추정입니다.") : "PPTX 근거의 화면 좌표는 미검증입니다. 아래 추출 원문에서 내용을 확인하세요.").font(.caption).foregroundStyle(.orange)
            }
            GeometryReader { geometry in
                if current.isNull { ContentUnavailableView("대응하는 원문 없음", systemImage:"doc", description:Text("관측 부재와 실제 삭제를 변경 근거에서 구분하세요.")) }
                else if !failure.isEmpty { ContentUnavailableView("페이지를 열지 못했습니다",systemImage:"exclamationmark.triangle",description:Text(failure)) }
                else if payload.isNull { ProgressView("원문 페이지 로딩…").frame(maxWidth:.infinity,maxHeight:.infinity) }
                else if payload["source"]["kind"].string == "pdf" {
                    OriginalPDFView(path:payload["source"]["path"].string,pageNumber:payload["display_page_number"].isNull ? payload["page"]["page"].int : payload["display_page_number"].int,zoom:model.zoom,evidence:payloadReady && payload["source"]["origin"].string == "original" ? evidence : JSON(),page:payload["display_page"].isNull ? payload["page"] : payload["display_page"])
                } else if let size=fittedPageSize(width:payload["page"]["width"].number,height:payload["page"]["height"].number,available:geometry.size,inset:8) {
                    ScrollView([.horizontal,.vertical]) {
                        let scale = model.zoom == 0 ? 1 : model.zoom
                        VStack { Spacer(minLength:0); StructureCanvas(page:payload["page"],evidence:payloadReady ? evidence:JSON()).frame(width:size.width*scale,height:size.height*scale).shadow(color:.black.opacity(0.08),radius:5); Spacer(minLength:0) }.frame(minWidth:geometry.size.width,minHeight:geometry.size.height)
                    }
                } else {ContentUnavailableView("페이지 크기를 확인할 수 없습니다",systemImage:"exclamationmark.triangle")}
            }.background(Color(nsColor:.windowBackgroundColor).overlay(Color.primary.opacity(0.045))).clipShape(RoundedRectangle(cornerRadius:5))
                .overlay {if loadingPage && !payload.isNull && failure.isEmpty {VStack(spacing:6){ProgressView();Text("다음 페이지를 검증하는 동안 이전 페이지를 표시합니다.").font(.caption)}.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8))}}.allowsHitTesting(!loadingPage)
            DisclosureGroup("추출 내용·표·표시 상태",isExpanded:$rawOpen) {
                if payloadReady {ScrollView { LazyVStack(alignment:.leading,spacing:10) {
                    Text("원문 추출과 OCR 추정을 각각 보존합니다.").font(.caption).foregroundStyle(.secondary)
                    if !payload["page"]["ocr"].isNull {Text("로컬 OCR · \(payload["page"]["ocr"]["status"].string) · 인식 결과는 원본 화면으로 확인하세요.").font(.caption).foregroundStyle(.orange)}
                    if ["unsupported_format","unsupported_dimensions","budget_exceeded","ambiguous_boundaries","partial"].contains(payload["page"]["ocr"]["grid_status"].string) {Text("표의 격자 경계가 미확정이거나 검출 범위를 벗어났습니다. 행·열을 원본 화면에서 확인하세요.").font(.caption).foregroundStyle(.orange)}
                    ForEach(payload["source"]["warnings"].array.indices,id:\.self){i in Text(renderWarningName(payload["source"]["warnings"].array[i].string)).font(.caption).foregroundStyle(.orange)}
                    ForEach(payload["page"]["elements"].array) { e in
                        VStack(alignment:.leading,spacing:4) {
                            Text(e["method"].string == "pdf_page_annotation" ? (e["source_ref"].string.hasSuffix("/StrikeOut") ? "취소선 주석 · 표시 상태 미검증" : e["source_ref"].string.hasSuffix("/Redact") ? "삭제 의도 주석 · 적용 여부 확인" : "PDF 주석 영역 · 원본 확인 필요") : e["text"].string).textSelection(.enabled)
                            if hasEstimatedPDFGeometry(e) { Text(e["visibility"].string == "hidden_render_mode" ? "원문 위치 미검증 · 좌표는 추정값 · 비표시 모드 관측" : "원문 위치·표시 상태 미검증 · 글꼴 좌표는 추정값입니다.").font(.caption).foregroundStyle(.orange) }
                            HStack { Text(e["visibility"].string.isEmpty ? "원본 구조" : e["visibility"].string)
                                if e["method"].string == "vision_ocr" {Text((e["ocr"]["reconsideration"].isNull ? "최초 OCR 추정":"문맥 재판독 추정")+" · \(Int(e["ocr"]["confidence"].number*100))점")}
                                if !e["comparison_role"].string.isEmpty {Text(comparisonRoleName(e))}
                                if !e["table"].isNull { Text(e["table"]["origin"].string == "ooxml_table" ? "PPTX 셀 · 구조 관측" : e["table"]["origin"].string == "vision_table_inferred" ? "화면 OCR 표 셀 · 추정" : "PDF 격자 · 추정") }
                            }.font(.caption2).foregroundStyle(e["visibility"].string.contains("occluded") || e["visibility"].string.contains("struck") ? .orange : .secondary)
                            if e["method"].string == "vision_ocr" {OcrContextEvidence(element:e)}
                        }.padding(8).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:4))
                    }
                    Text("발표자 노트").font(.headline); Text(notesDisplayText(payload["page"]))
                }.frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:220)}else{Text(loadingPage ? "선택한 페이지의 추출 내용을 검증하고 있습니다.":"현재 페이지의 추출 내용을 읽지 못했습니다.").foregroundStyle(.secondary)}
            }.font(.caption).disabled(!payloadReady)
        }.padding(12).task(id:model.report["report_id"].string+pageID) {
            let report=model.report["report_id"].string
            if loadedReport != report {payload=JSON()}
            failure="";pageInput=String(current["page"].int);loadingPage=true
            defer{if !Task.isCancelled{loadingPage=false}}
            guard !pageID.isEmpty else{payload=JSON();return}
            do {let result=try await model.page(pageID);if !Task.isCancelled{payload=result;loadedReport=report}}catch{if !Task.isCancelled{payload=JSON();failure=error.localizedDescription}}
        }
    }
    func go(_ number: Int) { if let p=pages.first(where:{$0["page"].int==number}){model.navigatePage(p["page_id"].string,in:revision["revision_occurrence_id"].string);pageInput=String(number)}else{pageInput=String(current["page"].int)} }
}
