import SwiftUI

// A provided PDF is a reference for one revision. These links never edit the
// timeline relation editor or replace the PPTX's source observations.
struct BundleSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let projectID:String
    let reportID:String
    let occurrence:String
    let initialSource:String
    @State private var context=JSON()
    @State private var sourceID=""
    @State private var pdfID=""
    @State private var sourceSearch=""
    @State private var pdfSearch=""
    @State private var mode="link"
    @State private var reason=""
    @State private var saving=false
    @State private var failure=""
    @State private var conflictsExpanded=true
    @State private var warningsExpanded=true
    @State private var showHistory=false
    var revision:JSON {context["revision"]}
    var sourceAsset:String {revision["assets"].array.first{$0["format"].string=="pptx"}?["asset_id"].string ?? ""}
    var pdfAsset:String {revision["assets"].array.first{$0["format"].string=="pdf"}?["asset_id"].string ?? ""}
    var sources:[JSON] {revision["pages"].array.filter{$0["asset_id"].string==sourceAsset}}
    var pdfs:[JSON] {revision["pages"].array.filter{$0["asset_id"].string==pdfAsset}}
    var mapping:[JSON] {context["mapping"].array}
    var current:JSON {mapping.first{$0["source_page_id"].string==sourceID} ?? JSON()}
    var conflicts:[JSON] {
        mapping.filter { $0["source_page_id"].string==sourceID || (mode=="link" && $0["rendered_page_id"].string==pdfID) }
    }
    var selectionWarnings:[String] {
        let source=sources.first{$0["page_id"].string==sourceID} ?? JSON(),target=pdfs.first{$0["page_id"].string==pdfID} ?? JSON()
        var warnings=(source["coverage_gaps"].array+target["coverage_gaps"].array).map{coverageReasonName($0["reason"].string)}
        if mode=="link",!source.isNull,!target.isNull {
            if source["comparison_text_hash"].string != target["comparison_text_hash"].string || target["comparison_unresolved"].bool {warnings.append("선택한 PPTX와 PDF의 문구가 다르거나 PDF 판독이 불확실합니다.")}
            if abs((source["width"].number/max(1,source["height"].number))/(target["width"].number/max(1,target["height"].number))-1)>0.001 {warnings.append("선택한 PPTX와 PDF의 페이지 비율이 다릅니다.")}
            if source["hidden"].bool {warnings.append("숨김 슬라이드를 연결합니다. PDF 내보내기 범위를 확인하세요.")}
            if !target["native_raster_available"].bool {warnings.append("선택한 PDF의 화면 비교 근거가 없습니다. 연결 후에도 화면 차이는 미확정으로 남습니다.")}
            if !target["reference_transform_available"].bool {warnings.append("선택한 PDF의 좌표 변환이 없어 연결 화면 대신 구조·별도 변환 화면을 사용합니다.")}
            if revision["coverage_gaps"].array.contains(where:{$0["reason"].string=="reference_pdf_reused_for_different_pptx"}) {warnings.append("이 PDF를 서로 다른 PPTX 원본에 사용했습니다. 연결한 버전을 확인하세요.")}
        }
        var seen=Set<String>();return warnings.filter{seen.insert($0).inserted}
    }
    var validation:String? {
        if context.isNull {return "연결 정보를 불러오고 있습니다."}
        if !context["current_snapshot"].bool {return "최신 분석 결과에서 연결을 수정하세요."}
        if !sources.contains(where:{$0["page_id"].string==sourceID}) {return "PPTX 슬라이드를 선택하세요."}
        if mode=="link" && !pdfs.contains(where:{$0["page_id"].string==pdfID}) {return "연결할 PDF 페이지를 선택하세요."}
        if reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return "수정 이유를 입력하세요."}
        if reason.utf16.count>2000 {return "수정 이유는 2000단위 이내로 입력하세요."}
        return nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("제공 PDF 페이지 연결").font(.title2.weight(.semibold));Text(revision["label"].string).foregroundStyle(.secondary);Spacer();Button("연결 이력 \(context["decision_count"].int)개"){showHistory=true}.disabled(context.isNull || context["decision_count"].int==0 || saving);Button("취소"){dismiss()}.keyboardShortcut(.cancelAction).disabled(saving)}
            Text("같은 버전의 PPTX와 PDF를 한 쌍씩 연결합니다. 연결은 화면 참고용이며 PowerPoint 원본의 충실도를 보증하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing:16) {
                pageList(sources,search:$sourceSearch,selection:$sourceID,title:"PPTX 원본 슬라이드")
                Image(systemName:mode=="link" ? "link":"link.badge.plus").foregroundStyle(.secondary)
                pageList(pdfs,search:$pdfSearch,selection:$pdfID,title:"제공 PDF 페이지").disabled(mode=="unlink")
            }.frame(height:170).disabled(saving)
            HStack(spacing:16) {
                BundlePagePreview(projectID:projectID,reportID:reportID,pageID:sourceID,basis:"source",title:"PPTX 원본 · 구조 또는 별도 변환 화면")
                BundlePagePreview(projectID:projectID,reportID:reportID,pageID:pdfID,basis:"source",title:"제공 PDF 원본")
            }.frame(maxHeight:.infinity)
            if !selectionWarnings.isEmpty {
                DisclosureGroup("선택한 원문·연결 주의사항 \(selectionWarnings.count)개",isExpanded:$warningsExpanded){ScrollView{VStack(alignment:.leading,spacing:4){ForEach(selectionWarnings,id:\.self){Text($0).font(.caption).foregroundStyle(.orange)}}.frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:65)}.font(.caption)
            }
            HStack {Picker("연결 방식",selection:$mode){Text("PDF 페이지 연결").tag("link");Text("이 슬라이드의 PDF 연결 해제·차단").tag("unlink")}.labelsHidden().pickerStyle(.segmented).disabled(saving);Text(statusText).font(.caption).foregroundStyle(.secondary)}
            if !conflicts.isEmpty {
                DisclosureGroup("기존 연결 \(conflicts.count)개를 대체합니다 · 연결 이유 확인",isExpanded:$conflictsExpanded) {
                    ScrollView {VStack(alignment:.leading,spacing:6){ForEach(Array(conflicts.enumerated()),id:\.offset){_,entry in
                        Text(pairLabel(entry)+(entry["association"].string=="human_confirmed" ? " · 사용자 연결":" · 자동 추정")).font(.caption.weight(.medium))
                        if !entry["reason"].string.isEmpty {Text(entry["reason"].string).font(.caption).textSelection(.enabled)}
                    }}.frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:65)
                }.font(.caption)
            }
            TextField("수정 이유 (필수 · 연결 이력에 원문 그대로 보존)",text:$reason,axis:.vertical).lineLimit(2...3).textFieldStyle(.roundedBorder).disabled(saving)
            HStack {Text(validation ?? "적용하면 연결 이력을 보존하고 새 고정 보고서를 분석합니다.").foregroundStyle(validation == nil ? Color.secondary:Color.orange);Spacer();Text("\(reason.utf16.count)/2000").help("일부 이모지는 여러 단위로 계산됩니다.")}.font(.caption)
            if !failure.isEmpty {Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
            HStack {Text("적용 전 취소하면 저장하지 않습니다.").font(.caption).foregroundStyle(.secondary);Spacer();if saving{ProgressView().controlSize(.small)};Button("적용하고 재분석"){Task{await apply()}}.buttonStyle(.borderedProminent).disabled(validation != nil || saving || model.busy)}
        }.padding(22).frame(width:1040,height:780).background(Color(nsColor:.windowBackgroundColor))
        .sheet(isPresented:$showHistory){BundleHistorySheet(projectID:projectID,reportID:reportID,occurrence:occurrence).environmentObject(model)}
        .onChange(of:sourceID){selectCurrentPDF()}
        .task {
            do {
                context=try await model.bundleContext(project:projectID,report:reportID,occurrence:occurrence)
                sourceID=sources.contains(where:{$0["page_id"].string==initialSource}) ? initialSource:sources.first?["page_id"].string ?? ""
                selectCurrentPDF()
            }catch{failure=error.localizedDescription}
        }
    }
    var statusText:String {
        if !current.isNull {return "현재: "+pairLabel(current)+(current["association"].string=="human_confirmed" ? " · 사용자 연결":" · 자동 추정")}
        let state=context["manual_states"].array.first{$0["source_page_id"].string==sourceID}
        return state == nil ? "현재 연결 없음":state!["displaced"].bool ? "다른 연결로 인해 해제됨":"사용자가 연결 해제·차단함"
    }
    func selectCurrentPDF(){pdfID=current["rendered_page_id"].string}
    func pairLabel(_ entry:JSON)->String {
        let source=sources.first{$0["page_id"].string==entry["source_page_id"].string}?["page"].int ?? 0
        let target=pdfs.first{$0["page_id"].string==entry["rendered_page_id"].string}?["page"].int ?? 0
        return "슬라이드 \(source) → PDF p.\(target)"
    }
    func pageList(_ all:[JSON],search:Binding<String>,selection:Binding<String>,title:String)->some View {
        let pages=all.filter{search.wrappedValue.isEmpty || String($0["page"].int).contains(search.wrappedValue) || $0["text"].string.localizedCaseInsensitiveContains(search.wrappedValue)}
        let selected=all.first{$0["page_id"].string==selection.wrappedValue}
        return ScrollViewReader {proxy in
            VStack(alignment:.leading,spacing:6){
                HStack{Text(title).font(.headline);Spacer();Text("\(all.count)쪽").font(.caption).foregroundStyle(.secondary)}
                TextField("번호·문구 검색",text:search).textFieldStyle(.roundedBorder)
                List(selection:Binding<String?>(get:{selection.wrappedValue.isEmpty ? nil:selection.wrappedValue},set:{selection.wrappedValue=$0 ?? ""})) {
                    ForEach(pages){page in HStack(alignment:.top){Text("p.\(page["page"].int)").monospacedDigit().frame(width:50,alignment:.leading);Text(page["text"].string.isEmpty ? "판독된 요약 없음":page["text"].string).font(.caption).lineLimit(2);if page["hidden"].bool{Text("숨김").font(.caption2).foregroundStyle(.secondary)}}.tag(page["page_id"].string).id(page["page_id"].string)}
                }
                if let selected {Button("선택 p.\(selected["page"].int) · 목록에서 보기"){search.wrappedValue="";Task{@MainActor in await Task.yield();proxy.scrollTo(selection.wrappedValue,anchor:.center)}}.buttonStyle(.plain).font(.caption).foregroundStyle(.blue)}
            }.frame(maxWidth:.infinity).onChange(of:selection.wrappedValue){proxy.scrollTo(selection.wrappedValue,anchor:.center)}
        }
    }
    func apply() async {
        guard validation == nil,!saving else{return};saving=true;failure=""
        do {
            try await model.applyBundle(project:projectID,report:reportID,draftHash:context["draft_hash"].string,occurrence:occurrence,sourceAsset:sourceAsset,pdfAsset:pdfAsset,source:sourceID,pdf:mode=="link" ? pdfID:nil,action:mode,reason:reason)
            dismiss();await model.run(projectID)
        }catch{failure=error.localizedDescription;saving=false}
    }
}

struct BundleHistorySheet:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    let projectID:String
    let reportID:String
    let occurrence:String
    @State private var entries:[JSON]=[]
    @State private var cursor:String?=nil
    @State private var loading=false
    @State private var loaded=false
    @State private var failure=""
    @State private var reasons:[String:String]=[:]
    @State private var expanding=Set<String>()
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Text("제공 PDF 연결 이력").font(.title2.weight(.semibold));Spacer();Button("닫기"){dismiss()}.keyboardShortcut(.cancelAction)}
            Text("이 고정 보고서에 저장된 순서와 이유입니다. 해제·재연결은 이전 기록을 보존합니다.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:14) {
                    ForEach(Array(entries.enumerated()),id:\.offset){_,entry in historyRow(entry)}
                    if cursor != nil {Button("기록 더 보기"){Task{await load()}}.disabled(loading)}
                    if loading {ProgressView()}
                    if loaded && entries.isEmpty {Text("저장된 연결 이력이 없습니다.").foregroundStyle(.secondary)}
                }
            }
            if !failure.isEmpty{Text(failure).font(.caption).foregroundStyle(.red);if !loaded{Button("다시 불러오기"){Task{await load()}}.disabled(loading)}}
            Text("사용자 연결은 PDF 내보내기 출처나 PowerPoint 원본 충실도의 인증이 아닙니다.").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width:800,height:580).task{await load()}
    }
    func historyRow(_ entry:JSON)->some View {
        let id=entry["decision_id"].string
        return VStack(alignment:.leading,spacing:6){
            Text("\(entry["ordinal"].int+1). 슬라이드 \(entry["source_page"].int) → "+(entry["action"].string=="unlink" ? "PDF 연결 없음":"PDF p.\(entry["rendered_page"].int)")).font(.headline)
            Text(reasons[id] ?? entry["reason"].string).font(.callout).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
            if !entry["next_reason_offset"].isNull && reasons[id]==nil {Button(expanding.contains(id) ? "이유 불러오는 중…":"수정 이유 전체 보기"){Task{await expand(entry)}}.disabled(expanding.contains(id))}
            Text("대체한 기존 연결 \(entry["displaced"].array.count)개 · "+String(id.prefix(17))+"…").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
    }
    func request(_ extra:[String:Any]=[:]) async throws->JSON {
        var args:[String:Any]=["project_id":projectID,"report_id":reportID,"revision_id":occurrence,"max_output_tokens":8000,"limit":10]
        args.merge(extra){_,value in value};return try await model.bridge.call("bundleDecisions",args)
    }
    func load() async {
        guard !loading else{return};loading=true;failure="";defer{loading=false}
        do{let response=try await request(cursor.map{["cursor":$0]} ?? [:]);entries += response["items"].array;cursor=response["next_cursor"].string.isEmpty ? nil:response["next_cursor"].string;loaded=true}catch{failure=error.localizedDescription}
    }
    func expand(_ entry:JSON) async {
        let id=entry["decision_id"].string;guard !expanding.contains(id) else{return};expanding.insert(id);defer{expanding.remove(id)}
        do{var text="",offset=0
            for _ in 0..<8 {let response=try await request(["decision_id":id,"reason_offset":offset,"reason_length":500]),part=response["items"].array.first ?? JSON();guard !part.isNull,part["omitted_fields"].array.isEmpty else{throw BridgeError(code:"HISTORY_REASON",message:"수정 이유를 불러오지 못했습니다.")};text+=part["reason"].string;if part["next_reason_offset"].isNull{reasons[id]=text;return};let next=part["next_reason_offset"].int;guard next>offset else{break};offset=next}
            throw BridgeError(code:"HISTORY_REASON",message:"수정 이유의 나머지를 확인하지 못했습니다. 다시 시도하세요.")
        }catch{failure=error.localizedDescription}
    }
}

struct BundlePagePreview:View {
    @EnvironmentObject var model:AppModel
    let projectID:String
    let reportID:String
    let pageID:String
    let basis:String
    let title:String
    @State private var payload=JSON()
    @State private var failure=""
    var body:some View {
        VStack(alignment:.leading,spacing:5){
            HStack{Text(title);Spacer();if payload["source"]["origin"].string=="pptx_converted"{Text("LibreOffice 렌더")}else if payload["source"]["kind"].string=="pptx"{Text("구조 보기 · 원본 화면 미검증")}}.font(.caption).foregroundStyle(.secondary)
            if !payload["source"]["warnings"].array.isEmpty {Text(payload["source"]["warnings"].array.map{renderWarningName($0.string)}.joined(separator:" · ")).font(.caption2).foregroundStyle(.orange).lineLimit(2)}
            GeometryReader{geometry in
                if pageID.isEmpty {ContentUnavailableView("페이지를 선택하세요",systemImage:"doc")}
                else if !failure.isEmpty {Text(failure).foregroundStyle(.red).font(.caption)}
                else if payload.isNull {ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity)}
                else if payload["source"]["kind"].string=="pdf" {OriginalPDFView(path:payload["source"]["path"].string,pageNumber:payload["page"]["page"].int,zoom:0,evidence:JSON(),page:payload["display_page"])}
                else {StructureCanvas(page:payload["page"],evidence:JSON()).frame(width:geometry.size.width,height:min(geometry.size.height,geometry.size.width*payload["page"]["height"].number/max(1,payload["page"]["width"].number)))}
            }.background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:5))
        }.frame(maxWidth:.infinity).task(id:projectID+reportID+pageID+basis){
            payload=JSON();failure="";guard !pageID.isEmpty else{return}
            do{let result=try await model.bridge.call("page",["project_id":projectID,"report_id":reportID,"page_id":pageID,"basis":basis]);if !Task.isCancelled{payload=result}}catch{if !Task.isCancelled{failure=error.localizedDescription}}
        }
    }
}
