import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            if !model.error.isEmpty { HStack { Image(systemName:"exclamationmark.triangle.fill");Text(model.error).textSelection(.enabled);Spacer();Button("닫기"){model.error=""} }.padding(10).background(.red.opacity(0.1)) }
            if model.busy { HStack { ProgressView().controlSize(.small);Text(model.status);Text("\(model.progress["current"].int)/\(max(1,model.progress["total"].int))").foregroundStyle(.secondary);Spacer();Button(model.committing ? "저장 중" : "분석 취소"){model.cancel()}.disabled(model.committing) }.padding(10).background(.blue.opacity(0.06)) }
            HStack(spacing:0) {
                if !model.focus { SidebarView().frame(width:220);Divider() }
                VStack(spacing:0) {
                    if model.report.isNull { EmptyWorkspace() }
                    else {
                        if !model.focus { ReportBar();Divider();VersionBar();Divider() }
                        if model.tab=="export" { ExportView() }
                        else if model.tab=="history" { HistoryView() }
                        else { CompareWorkspace() }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            Divider();HStack { Label("내 Mac에만 저장",systemImage:"internaldrive");Spacer();Text(model.status.isEmpty ? "근거 · 추정 · 관측 공백을 구분합니다" : model.status);Spacer();Text("Docver · Native macOS") }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,14).padding(.vertical,5)
        }.disabled(!model.libraryAvailable || model.initializing).preferredColorScheme(.light).background(Color(nsColor:.windowBackgroundColor)).frame(minWidth:1100,minHeight:740)
        .toolbar {
            ToolbarItem(placement:.navigation){Button {model.focus.toggle()} label:{Image(systemName:model.focus ? "sidebar.left" : "arrow.up.left.and.arrow.down.right")}.help(model.focus ? "기본 화면" : "문서 크게 보기")}
            ToolbarItem { Text(model.project["title"].string.isEmpty ? "Docver" : model.project["title"].string).font(.headline) }
            ToolbarItemGroup(placement:.primaryAction) {
                if !model.report.isNull {
                    Picker("작업",selection:$model.tab){Text("비교").tag("compare");Text("전체 이력").tag("history");Text("AI·내보내기").tag("export")}.pickerStyle(.segmented).frame(width:265)
                    Button {Task{await model.exportReport()}} label:{Label("내보내기",systemImage:"square.and.arrow.up")}
                }
            }
        }.onChange(of:model.tab){if model.tab=="export"{Task{await model.loadMCP()}}else{model.changeRange()}}
        .sheet(isPresented:$model.importSheet){ImportView()}
        .task {await model.start()}
    }
}
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack{Text("프로젝트").font(.caption).foregroundStyle(.secondary);Spacer();Button{model.importSheet=true}label:{Image(systemName:"plus")}.buttonStyle(.borderless).disabled(model.busy)}.padding(.horizontal,14).padding(.top,18)
            List(model.projects){p in Button{Task{await model.selectProject(p["project_id"].string)}}label:{HStack{Image(systemName:"folder.fill").foregroundStyle(.blue);VStack(alignment:.leading,spacing:3){Text(p["title"].string).lineLimit(1);Text("\(p["revisions"].array.count)개 버전"+(p["dirty"].bool ? " · 분석 대기":"")).font(.caption2).foregroundStyle(.secondary)}}.padding(.vertical,5)}.buttonStyle(.plain).disabled(model.busy||model.loading).listRowBackground(p["project_id"].string==model.projectID ? Color.blue.opacity(0.12):Color.clear)}.listStyle(.sidebar).frame(minHeight:80,maxHeight:220)
            if !model.project.isNull {
                Text("가져오기 순서").font(.caption).foregroundStyle(.secondary).padding(.horizontal,14)
                ScrollView { LazyVStack(spacing:0){ForEach(Array(model.project["revisions"].array.enumerated()),id:\.offset){i,r in HStack(spacing:8){Text(String(format:"%02d",i+1)).foregroundStyle(.secondary).font(.caption2);VStack(alignment:.leading,spacing:4){Text(r["label"].string).lineLimit(1).font(.caption);Text(r["files"].array.map{$0["blob"].string.hasSuffix("pdf") ? "PDF":"PPTX"}.joined(separator:" + ")).font(.caption2).foregroundStyle(.secondary)};Spacer();VStack(spacing:3){Button{Task{await model.reorder(i,delta:-1)}}label:{Image(systemName:"chevron.up")}.disabled(i==0||model.busy);Button{Task{await model.reorder(i,delta:1)}}label:{Image(systemName:"chevron.down")}.disabled(i==model.project["revisions"].array.count-1||model.busy)}.buttonStyle(.borderless).font(.caption2)}.padding(.horizontal,14).padding(.vertical,9);Divider()}} }
                Button(model.project["dirty"].bool ? "변경한 순서로 분석":"다시 분석"){Task{await model.run(model.projectID)}}.disabled(model.busy).frame(maxWidth:.infinity).padding(.horizontal,14)
            }
            Spacer(minLength:5)
            Button{model.importSheet=true}label:{Label("문서 버전 가져오기",systemImage:"plus")}.disabled(model.busy).frame(maxWidth:.infinity).padding(14)
        }.background(Color(nsColor:.underPageBackgroundColor))
    }
}
struct EmptyWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View { VStack(spacing:22){Image(systemName:"doc.on.doc").font(.system(size:62,weight:.light)).foregroundStyle(.blue);Text("문서가 바뀐 모든 순간을\n한눈에 따라가세요.").font(.system(size:32,weight:.semibold)).multilineTextAlignment(.center);Text("PPTX와 PDF를 순서대로 모으면 숫자 수정부터\n중간에 사라진 페이지까지 원문과 함께 확인할 수 있습니다.").foregroundStyle(.secondary).multilineTextAlignment(.center);HStack{Button("문서 버전 가져오기"){model.importSheet=true}.buttonStyle(.borderedProminent);Button("5버전 합성 데모 열기"){Task{await model.demo()}}}.disabled(model.busy);Text("계정 없이 · 업로드 없이 · 네이티브 macOS 앱").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity) }
}
struct ReportBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {HStack{Label("고정 보고서",systemImage:"lock.doc").font(.caption);Picker("보고서",selection:Binding(get:{model.report["report_id"].string},set:{id in Task{await model.selectProject(model.projectID,snapshot:id)}})){ForEach(model.reports){r in Text(String(r["report_id"].string.dropFirst(4).prefix(12))+" · "+String(r["created_at"].string.prefix(16))).tag(r["report_id"].string)}}.labelsHidden().frame(width:300).disabled(model.busy);Spacer();if model.project["dirty"].bool{Text("입력/대응 변경 · 아래는 이전 보고서").font(.caption).foregroundStyle(.orange)};Text("\(model.revisions.count)개 버전").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,16).padding(.vertical,8)}
}
struct VersionBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Button{model.from=min(i,max(0,model.revisions.count-2));model.to=min(model.revisions.count-1,model.from+1);model.changeRange()}label:{VStack(spacing:5){Circle().fill(i==model.from||i==model.to ? Color.blue:Color.gray.opacity(0.3)).frame(width:11,height:11);Text("v\(i+1) "+r["label"].string).font(.caption.weight(.semibold));Text("\(model.primaryPages(r).count)쪽 · "+r["assets"].array.map{$0["format"].string.uppercased()}.joined(separator:"+")).font(.caption2).foregroundStyle(.secondary);if r["status"].string != "success"{Text("부분 실패 · 확인 필요").font(.caption2).foregroundStyle(.orange)}}.frame(minWidth:135).padding(7)}.buttonStyle(.plain)}}.padding(.horizontal,15).padding(.vertical,9)}}
}
struct CompareWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing:0){
            HStack(spacing:10){
                Picker("이전",selection:$model.from){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i<model.to{Text("v\(i+1) "+r["label"].string).tag(i)}}}.frame(maxWidth:220)
                Image(systemName:"arrow.right").foregroundStyle(.secondary)
                Picker("이후",selection:$model.to){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i>model.from{Text("v\(i+1) "+r["label"].string).tag(i)}}}.frame(maxWidth:220)
                Text(model.to==model.from+1 ? "인접 비교":"선택 구간의 순변경").font(.caption).foregroundStyle(.secondary);Spacer()
                Button{model.inspector.toggle()}label:{Label("근거",systemImage:"sidebar.right")}
            }.padding(.horizontal,16).padding(.top,12).onChange(of:model.from){model.changeRange()}.onChange(of:model.to){model.changeRange()}
            HStack{
                Picker("문서 보기",selection:$model.pageMode){Text("두 페이지").tag("both");Text("이전만 크게").tag("before");Text("이후만 크게").tag("after")}.pickerStyle(.segmented).frame(width:295)
                Picker("확대",selection:$model.zoom){Text("화면 맞춤").tag(0.0);Text("100%").tag(1.0);Text("150%").tag(1.5);Text("200%").tag(2.0)}.frame(width:160)
                Spacer();Button(model.showChanges ? "변경 목록 접기":"변경 목록 열기"){model.showChanges.toggle()}
            }.controlSize(.small).padding(.horizontal,16).padding(.vertical,10)
            HSplitView {
                VStack(spacing:0){
                    HSplitView{
                        if model.pageMode != "after"{PageColumn(revision:model.revision(model.from),side:"이전",pageID:$model.leftPageID)}
                        if model.pageMode != "before"{PageColumn(revision:model.revision(model.to),side:"이후",pageID:$model.rightPageID)}
                    }.frame(maxHeight:.infinity)
                    if model.showChanges {Divider();ChangeListView().frame(height:model.focus ? 190:240)}
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.inspector { InspectorView().frame(minWidth:275,idealWidth:300,maxWidth:360) }
            }
        }.onChange(of:model.selectedChangeID){Task {await Task.yield();model.selectEvidence()}}
    }
}
struct ChangeListView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {VStack(spacing:5){HStack{Picker("유형",selection:$model.kind){Text("전체 변경").tag("all");ForEach(changeNames.keys.sorted(),id:\.self){Text(changeNames[$0]!).tag($0)}}.frame(width:180);TextField("원문에서 검색",text:$model.search).textFieldStyle(.roundedBorder).frame(maxWidth:250);Spacer();Text("\(model.filteredChanges.count)개").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,12).padding(.top,8)
        ScrollView { LazyVStack(spacing:1) { ForEach(model.filteredChanges) { c in Button {model.chooseChange(c["change_id"].string)} label: {ChangeRow(change:c).padding(.horizontal,10).padding(.vertical,4).contentShape(Rectangle())}.buttonStyle(.plain).background(model.selectedChangeID==c["change_id"].string ? Color.blue.opacity(0.12) : Color.clear) } }.padding(6) }
    }}
}

struct ChangeRow: View {
    let change: JSON
    var kindName: String {changeNames[change["kind"].string] ?? change["kind"].string}
    var text: String {(change["after"].isNull ? change["before"].string:change["after"].string).replacingOccurrences(of:"\n",with:" ")}
    var status: String {let value=change["lineage"]["status"].string;return value=="human_confirmed" ? "사용자 확정":value=="needs_review" ? "검토 필요":"추정 대응"}
    var body: some View {HStack(spacing:10){Text(kindName).font(.caption).foregroundStyle(change["kind"].string=="coverage_gap" ? Color.secondary:Color.blue).frame(width:85,alignment:.leading);VStack(alignment:.leading,spacing:3){Text(text).lineLimit(1).font(.caption);Text(change["evidence"].array.map{"p.\($0["page"].int)"}.joined(separator:" → ")).font(.caption2).foregroundStyle(.secondary)};Spacer();if change["region_pairing_assessment"].string == "inferred"{Text("영역 대응 추정").font(.caption2).foregroundStyle(.orange)};if change["text_assessment"].string == "inferred"{Text("OCR 추정 · 원문 확인").font(.caption2).foregroundStyle(.orange)};if !change["appearance_assessment"].string.isEmpty{Text(change["appearance_assessment"].string=="observed" ? "표시 관측":"표시 추정").font(.caption2).foregroundStyle(.orange)};Text(status).font(.caption2).foregroundStyle(.secondary)}.padding(.vertical,3)}
}

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var reason="원문 확인 후 대응 수정"
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:16){Text("선택한 변경").font(.caption).foregroundStyle(.secondary);Text(changeNames[model.selected["kind"].string] ?? "변경을 선택하세요").font(.title3.weight(.semibold));if !model.selected.isNull{Text("이전 원문").font(.caption).foregroundStyle(.secondary);Text(model.selected["before"].isNull ? "해당 버전에서 원문 없음":model.selected["before"].string).foregroundStyle(.red).textSelection(.enabled);Text("이후 원문").font(.caption).foregroundStyle(.secondary);Text(model.selected["after"].isNull ? "해당 버전에서 원문 없음":model.selected["after"].string).foregroundStyle(.green).textSelection(.enabled);Divider();Text("원문 근거").font(.headline);ForEach(Array(model.selected["evidence"].array.enumerated()),id:\.offset){_,e in VStack(alignment:.leading,spacing:6){Text("page \(e["page"].int) · "+e["method"].string).font(.caption);Text(e["quote"].string).font(.caption).textSelection(.enabled)}.padding(9).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))};if !model.selected["appearance_assessment"].string.isEmpty{Text(model.selected["appearance_assessment"].string=="observed" ? "표시 상태: 관측":"표시 상태: 추정").font(.caption).foregroundStyle(.orange)};Text(model.selected["lineage"]["reasons"].array.map(\.string).joined(separator:" · ")).font(.caption2).foregroundStyle(.secondary)}
        Divider();Text("페이지 대응 검토").font(.headline);Text("인접 버전의 양쪽 페이지를 고르고 이유를 남기면 새 보고서를 만듭니다.").font(.caption).foregroundStyle(.secondary);TextField("수정 이유",text:$reason);HStack{Button("연결 확정"){Task{await model.correctMapping("link",reason:reason)}};Button("연결 해제"){Task{await model.correctMapping("unlink",reason:reason)}}}.disabled(model.busy||model.project["dirty"].bool||model.project["last_report_id"].string != model.report["report_id"].string||model.to != model.from+1||model.leftPageID.isEmpty||model.rightPageID.isEmpty||reason.trimmingCharacters(in:.whitespaces).isEmpty)
        Divider();Label("관측 한계",systemImage:"exclamationmark.triangle").font(.headline);Text("가려진 텍스트와 취소선은 표시 상태로 보존합니다. 박스나 선이 삭제 의도인지는 시각 근거와 함께 검토하세요. PDF에서 추정한 표 구조는 PPTX의 원래 표와 동일하다고 보장하지 않습니다.").font(.caption);Text("OCR 추정 값은 원본 화면과 대조하세요. PDF에 없는 노트·숨김 정보는 삭제로 집계하지 않습니다. PPTX는 LibreOffice 변환 화면이며 폰트 대체·변환 경고를 근거 패널에서 확인할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
    }.padding(17).frame(maxWidth:.infinity,alignment:.leading)}}
}
struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {VStack(alignment:.leading,spacing:14){HStack{VStack(alignment:.leading){Text("전체 버전 이력").font(.title2.weight(.semibold));Text("중간에 생겼다가 사라진 페이지와 관측 공백을 함께 보존합니다.").font(.caption).foregroundStyle(.secondary)};Spacer()}.padding(.horizontal,18).padding(.top,20)
        ScrollView([.vertical,.horizontal]){LazyVStack(alignment:.leading,spacing:1){HStack{Text("페이지 계보").frame(width:180,alignment:.leading);ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Text("v\(i+1) "+r["label"].string).frame(width:130)}}.font(.caption.weight(.semibold)).padding(9)
            ForEach(model.report["lineages"].array){lineage in
                let all=model.revisions.flatMap{model.primaryPages($0)},ids=lineage["page_ids"].array.map(\.string)
                if let first=all.first(where:{ids.contains($0["page_id"].string)}){
                    HStack{Text(first["text"].string.components(separatedBy:"\n").first ?? "페이지").font(.caption).lineLimit(1).frame(width:180,alignment:.leading);ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in let p=model.primaryPages(r).first{ids.contains($0["page_id"].string)};Button{if let p{model.openHistoryPage(i,p["page_id"].string)}}label:{Text(p.map{"p.\($0["page"].int)"} ?? "—").frame(width:115).padding(.vertical,7).background(p==nil ? Color.gray.opacity(0.06):Color.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:4))}.buttonStyle(.plain).disabled(p==nil)}}.padding(7);Divider()
                }
            }
        }.padding(12)}
        Text("— 관측 없음 · 실제 삭제 여부는 변경 이벤트와 원문 근거에서 확인하세요.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,20)
        ChangeListView().frame(height:230)
    }}
}
struct ExportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:22){Text("원문과 이력을 함께 전달하세요.").font(.largeTitle.weight(.semibold));Text("같은 고정 보고서를 파일과 읽기 전용 MCP에서 조회합니다.").foregroundStyle(.secondary)
        GroupBox("보고서 파일 저장"){VStack(alignment:.leading,spacing:12){Text("전체 report, 변경 JSONL, 페이지·요소 원문, 버전·계보, 페이지별 Markdown과 근거 링크를 저장합니다.");Button("JSON·Markdown 내보내기"){Task{await model.exportReport()}}.buttonStyle(.borderedProminent)}.padding(12).frame(maxWidth:.infinity,alignment:.leading)}
        GroupBox("읽기 전용 MCP 연결"){VStack(alignment:.leading,spacing:12){Text("앱에 포함된 Node 런타임과 현재 프로젝트의 보관소를 사용합니다. 앱 위치를 옮기면 설정을 다시 복사하세요.").font(.caption).foregroundStyle(.secondary);Text(model.mcp.isEmpty ? "설정을 준비하고 있습니다…":model.mcp).font(.system(.caption,design:.monospaced)).textSelection(.enabled).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.textBackgroundColor));Button("설정 복사"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(model.mcp,forType:.string);model.status="MCP 설정을 복사했습니다"}}.padding(12)}
        GroupBox("표시 상태와 표 구조의 한계"){Text("취소선 주석은 관측 사실로, 납작해진 선·박스 가림은 기하·그림 순서에 기반한 추정으로 구분합니다. 부분 가림·마스크·회전·이미지는 불확실성을 남깁니다. PDF 격자는 추정된 구조이며 원래 PPTX 표의 셀 의미를 복원했다고 단정하지 않습니다. 스캔 OCR과 화면 표는 추정 근거로 보존하며 낮은 점수·대안 충돌·누락 영역은 보류합니다. 원문 화면에서 확인하세요.").font(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading)}
    }.padding(35).frame(maxWidth:1000,alignment:.leading)}.task{await model.loadMCP()}}
}
struct ImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var title="새 문서 프로젝트"
    @State private var rows:[ImportRow]=[]
    @State private var saving=false
    @State private var failure=""
    var body: some View {VStack(alignment:.leading,spacing:17){HStack{Text("문서 버전 가져오기").font(.title2.weight(.semibold));Spacer();Button("닫기"){dismiss()}.keyboardShortcut(.cancelAction).disabled(saving)};Text("각 버전은 PPTX 또는 PDF 하나로 유효합니다. 수백 페이지 문서는 선택한 페이지부터 지연 표시합니다.").font(.callout).foregroundStyle(.secondary);TextField("프로젝트 이름",text:$title).textFieldStyle(.roundedBorder);Button{choose()}label:{Label("PPTX·PDF 파일 선택",systemImage:"plus")}.disabled(saving)
        List{ForEach(Array(rows.enumerated()),id:\.element.id){i,r in HStack{Text("\(i+1)").foregroundStyle(.secondary);VStack(alignment:.leading){TextField("버전 이름",text:Binding(get:{rows.indices.contains(i) ? rows[i].label:""},set:{if rows.indices.contains(i){rows[i].label=$0}}));Text(r.urls.map(\.lastPathComponent).joined(separator:" + ")).font(.caption2).foregroundStyle(.secondary)};Button{rows.swapAt(i,i-1)}label:{Image(systemName:"chevron.up")}.disabled(i==0||saving);Button{rows.swapAt(i,i+1)}label:{Image(systemName:"chevron.down")}.disabled(i==rows.count-1||saving);Button("위와 묶기"){rows[i-1].urls += rows[i].urls;rows.remove(at:i)}.disabled(saving||i==0||r.urls.count != 1||(i>0 && (rows[i-1].urls.count != 1||rows[i-1].urls.first?.pathExtension.lowercased()==r.urls.first?.pathExtension.lowercased())));Button{rows.remove(at:i)}label:{Image(systemName:"xmark")}.disabled(saving)}}}.frame(minHeight:230,maxHeight:360)
        if !failure.isEmpty{Text(failure).foregroundStyle(.red).font(.caption)}
        HStack{Text("원본은 앱 전용 보관소에 복사합니다.").font(.caption).foregroundStyle(.secondary);Spacer();if saving{ProgressView().controlSize(.small)};Button("이 순서로 분석 시작"){Task{await create()}}.buttonStyle(.borderedProminent).disabled(saving||rows.isEmpty||title.trimmingCharacters(in:.whitespaces).isEmpty||rows.contains{$0.label.trimmingCharacters(in:.whitespaces).isEmpty})}
    }.padding(25).frame(width:860)}
    func choose(){let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.allowedContentTypes=[.pdf,UTType(filenameExtension:"pptx") ?? .data];panel.canChooseDirectories=false;if panel.runModal() == .OK{rows += panel.urls.map{ImportRow(label:$0.deletingPathExtension().lastPathComponent,urls:[$0])}}}
    func create() async {saving=true;do{let p=try await model.create(title:title,rows:rows);model.report=JSON();try await model.refresh();model.projectID=p["project_id"].string;dismiss();await model.run(model.projectID)}catch{failure=error.localizedDescription};saving=false}
}
