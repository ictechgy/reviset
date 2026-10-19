import SwiftUI
import AppKit
import PDFKit

func renderWarningName(_ value:String)->String{
    if value.hasPrefix("font_substitution_possible:"){return "대체될 수 있는 글꼴: "+String(value.dropFirst("font_substitution_possible:".count))}
    if value=="rendered_text_differs_from_ooxml_requires_source_review"{return "변환 화면에서 일부 원문 텍스트를 확인하지 못했습니다."}
    if value=="chart_smartart_or_other_object_render_requires_review"{return "차트·SmartArt 등 복합 개체의 변환 결과를 확인하세요."}
    return value
}

func hasEstimatedPDFGeometry(_ element:JSON)->Bool {
    element["visibility_evidence"].array.contains { $0["method"].string == "pdf_text_geometry_estimated_or_unavailable" }
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
    final class Coordinator { var path = ""; var pageNumber = -1; var zoom = -1.0; var marks: [(PDFPage, PDFAnnotation)] = [] }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.displayMode = .singlePage; view.displayDirection = .vertical
        view.displaysPageBreaks = false; view.backgroundColor = NSColor.windowBackgroundColor
        view.minScaleFactor = 0.1; view.maxScaleFactor = 8; return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        let sourceChanged=context.coordinator.path != path
        if sourceChanged { view.document = PDFDocument(url: URL(fileURLWithPath: path)); context.coordinator.path = path }
        for (p, a) in context.coordinator.marks { p.removeAnnotation(a) }; context.coordinator.marks = []
        guard let current = view.document?.page(at: max(0, pageNumber - 1)) else { return }
        if sourceChanged || context.coordinator.pageNumber != pageNumber || context.coordinator.zoom != zoom {
            view.autoScales = zoom == 0;view.go(to:current);if zoom>0{view.scaleFactor=zoom}
            context.coordinator.pageNumber=pageNumber;context.coordinator.zoom=zoom
        }
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
                    let font = NSFont.systemFont(ofSize: max(11,min(35,bounds.width*0.029)))
                    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
                    (e["text"].string as NSString).draw(in: rect.insetBy(dx: 2, dy: 1), withAttributes: [.font:font,.foregroundColor:NSColor.black,.paragraphStyle:style])
                } else if e["kind"].string == "image" || e["kind"].string == "unsupported" {
                    NSColor.systemGray.withAlphaComponent(0.12).setFill(); rect.fill()
                    ((e["kind"].string == "image" ? "이미지" : "의미 추출 미지원") as NSString).draw(in: rect, withAttributes: [.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.gray])
                }
            }
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
    @State private var pageInput = "1"
    @State private var rawOpen = false
    var pages: [JSON] { model.primaryPages(revision) }
    var current: JSON { pages.first { $0["page_id"].string == pageID } ?? JSON() }
    var evidence: JSON { model.selected["evidence"].array.first { $0["page_id"].string == pageID } ?? JSON() }
    var body: some View {
        VStack(spacing: 9) {
            HStack { Text(side + " · " + revision["label"].string).font(.headline); Spacer()
                Picker("페이지", selection: $pageID) { Text("원문 없음").tag(""); ForEach(pages) { p in Text("p.\(p["page"].int) · \(p["text"].string.prefix(24))").tag(p["page_id"].string) } }.labelsHidden().frame(maxWidth:260)
            }
            HStack(spacing: 8) {
                Button { go(current["page"].int-1) } label: { Image(systemName:"chevron.left") }.disabled(current.isNull || current["page"].int <= 1)
                TextField("페이지", text:$pageInput).frame(width:48).multilineTextAlignment(.center).onSubmit { if let n=Int(pageInput){go(n)} }
                Text("/ \(pages.count)").foregroundStyle(.secondary).font(.caption)
                Button { go(current["page"].int+1) } label: { Image(systemName:"chevron.right") }.disabled(current.isNull || current["page"].int>=pages.count)
                Spacer(); Text(payload["source"]["origin"].string == "reference_pdf" ? "같은 버전의 원본 PDF" : payload["source"]["origin"].string == "pptx_converted" ? "PPTX 렌더 · LibreOffice" : payload["source"]["kind"].string == "pdf" ? "원본 PDF · PDFKit" : "구조 보기 · 렌더 없음").font(.caption).foregroundStyle(.secondary)
            }.controlSize(.small)
            if !evidence.isNull && ["reference_pdf","pptx_converted"].contains(payload["source"]["origin"].string) {
                Text("PPTX 근거의 화면 좌표는 미검증입니다. 아래 추출 원문에서 내용을 확인하세요.").font(.caption).foregroundStyle(.orange)
            }
            GeometryReader { geometry in
                if current.isNull { ContentUnavailableView("대응하는 원문 없음", systemImage:"doc", description:Text("관측 부재와 실제 삭제를 변경 근거에서 구분하세요.")) }
                else if !failure.isEmpty { ContentUnavailableView("페이지를 열지 못했습니다",systemImage:"exclamationmark.triangle",description:Text(failure)) }
                else if payload.isNull { ProgressView("원문 페이지 로딩…").frame(maxWidth:.infinity,maxHeight:.infinity) }
                else if payload["source"]["kind"].string == "pdf" {
                    OriginalPDFView(path:payload["source"]["path"].string,pageNumber:payload["display_page_number"].isNull ? payload["page"]["page"].int : payload["display_page_number"].int,zoom:model.zoom,evidence:payload["source"]["origin"].string == "original" ? evidence : JSON(),page:payload["display_page"].isNull ? payload["page"] : payload["display_page"])
                } else {
                    ScrollView([.horizontal,.vertical]) {
                        let width = geometry.size.width * (model.zoom == 0 ? 1 : model.zoom)
                        VStack { Spacer(minLength:0); StructureCanvas(page:payload["page"],evidence:evidence).frame(width:width,height:width * max(0.1,payload["page"]["height"].number/max(1,payload["page"]["width"].number))).shadow(color:.black.opacity(0.08),radius:5); Spacer(minLength:0) }.frame(minHeight:geometry.size.height)
                    }
                }
            }.background(Color(nsColor:.windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:5))
            DisclosureGroup("추출 원문·표·표시 상태",isExpanded:$rawOpen) {
                ScrollView { VStack(alignment:.leading,spacing:10) {
                    Text("원문은 보이는 텍스트와 별도로 보존합니다.").font(.caption).foregroundStyle(.secondary)
                    if !payload["page"]["ocr"].isNull {Text("로컬 OCR · \(payload["page"]["ocr"]["status"].string) · 인식 결과는 원본 화면으로 확인하세요.").font(.caption).foregroundStyle(.orange)}
                    if ["unsupported_format","unsupported_dimensions","budget_exceeded","ambiguous_boundaries","partial"].contains(payload["page"]["ocr"]["grid_status"].string) {Text("표의 격자 경계가 미확정이거나 검출 범위를 벗어났습니다. 행·열을 원본 화면에서 확인하세요.").font(.caption).foregroundStyle(.orange)}
                    ForEach(payload["source"]["warnings"].array.indices,id:\.self){i in Text(renderWarningName(payload["source"]["warnings"].array[i].string)).font(.caption).foregroundStyle(.orange)}
                    ForEach(payload["page"]["elements"].array) { e in
                        VStack(alignment:.leading,spacing:4) {
                            Text(e["text"].string).textSelection(.enabled)
                            if hasEstimatedPDFGeometry(e) { Text("원문 위치·표시 상태 미검증 · 글꼴 좌표는 추정값입니다.").font(.caption).foregroundStyle(.orange) }
                            HStack { Text(e["visibility"].string.isEmpty ? "원본 구조" : e["visibility"].string)
                                if e["method"].string == "vision_ocr" {Text("OCR 추정 · \(Int(e["ocr"]["confidence"].number*100))점")}
                                if !e["comparison_role"].string.isEmpty {Text(e["comparison_role"].string == "selected" ? "비교에 사용" : e["comparison_role"].string == "unresolved" ? "비교 보류" : e["comparison_role"].string == "excluded" ? "숨은 원문 · 비교 제외" : e["provenance"].string == "inferred" ? "참고 OCR · 원문 우선" : "원문 보존 · OCR로 비교")}
                                if !e["table"].isNull { Text(e["table"]["origin"].string == "ooxml_table" ? "PPTX 셀 · 구조 관측" : e["table"]["origin"].string == "vision_table_inferred" ? "화면 OCR 표 셀 · 추정" : "PDF 격자 · 추정") }
                            }.font(.caption2).foregroundStyle(e["visibility"].string.contains("occluded") || e["visibility"].string.contains("struck") ? .orange : .secondary)
                        }.padding(8).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:4))
                    }
                    Text("발표자 노트").font(.headline); Text(payload["page"]["notes"].isNull ? "관측 불가 · 이 형식에는 노트 정보가 없습니다." : payload["page"]["notes"].string)
                }.frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:220)
            }.font(.caption)
        }.padding(12).task(id:model.report["report_id"].string+pageID) {
            payload=JSON();failure="";pageInput=String(current["page"].int)
            guard !pageID.isEmpty else{return}
            do {let result=try await model.page(pageID);if !Task.isCancelled{payload=result}}catch{if !Task.isCancelled{failure=error.localizedDescription}}
        }
    }
    func go(_ number: Int) { if let p=pages.first(where:{$0["page"].int==number}){pageID=p["page_id"].string;pageInput=String(number)} }
}
