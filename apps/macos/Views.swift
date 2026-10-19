import SwiftUI
import AppKit
import UniformTypeIdentifiers

func appearanceStateName(_ value:String)->String {
    let names=["visible":"보임","occluded":"가림","partially_occluded":"일부 가림","struck_through":"취소선","struck_inferred":"취소선 추정","partially_struck_through":"일부 취소선","hidden_render_mode":"비표시 모드","uncertain":"미확정","unverified":"미검증"]
    return names[value] ?? "알 수 없는 표시 상태"
}
func matchingReasonName(_ value:String,humanConfirmed:Bool=false)->String {
    // Reasons have no per-item origin tag. Preserve human-confirmed reasons
    // verbatim, including engine-like prefixes, rather than rewrite user input.
    if humanConfirmed { return value }
    if value.hasPrefix("appearance:") {
        let states=String(value.dropFirst("appearance:".count)).components(separatedBy:"→")
        return "표시 상태 변화: "+states.map { appearanceStateName($0) }.joined(separator:" → ")
    }
    switch value {
    case "exact_source_page": return "같은 원본 페이지"
    case "exact_native_raster": return "같은 화면 관측"
    case "normalized_text_bigrams": return "문구 유사성으로 추정한 대응"
    case "competing_duplicate_or_split_merge_candidate": return "중복·분할·병합 후보 검토 필요"
    case "candidate_pool_limited_to_top_8_per_direction": return "상위 후보만 검토한 대응"
    case "gap_applies_to_entire_revision_interval": return "두 버전 전체에 적용되는 관측 공백"
    case "unmatched_page": return "대응 페이지를 찾지 못함"
    case "directed_lineage_range_net": return "실제 연결 경로를 따른 버전 이력"
    case "structural_lineage_does_not_confirm_text": return "페이지 대응은 문구 변경의 확정이 아닙니다"
    case "snapshot_lineage_range_net": return "선택한 두 버전의 페이지 이력"
    default: return "기타 근거"
    }
}
func evidenceMethodName(_ value:String,provenance:String)->String {
    let label:String
    switch value {
    case "pdf_text": label="PDF 원문 텍스트"
    case "vision_ocr": label="화면 OCR"
    case "native_raster": label="렌더 화면"
    case "page_observation": label="페이지 근거"
    case "pdf_page_annotation": label="PDF 주석 정보"
    default: label=value.hasPrefix("pptx") || value.hasPrefix("ooxml") ? "PPTX 원본 구조" : "문서 근거"
    }
    if value == "vision_ocr" { return label+" · 추정" }
    return label+(provenance == "inferred" ? " · 추정" : provenance == "observed" ? " · 관측" : " · 근거 수준 미상")
}

func lineageReasonText(_ reasons:[JSON],humanConfirmed:Bool)->String {
    var seen=Set<String>()
    return reasons.map { matchingReasonName($0.string,humanConfirmed:humanConfirmed) }.filter { seen.insert($0).inserted }.joined(separator:" · ")
}

func coverageReasonName(_ value:String)->String {
    switch value {
    case "split_merge_text_comparison_withheld": return "분할·병합의 페이지 대응을 기록했습니다. 문구의 삭제·수정은 확정하지 않았으므로 각 원문 페이지를 확인하세요."
    case "ocr_fragment_reflow_region_withheld": return "단어가 다른 줄이나 영역으로 이어졌을 가능성이 있어 이 문구의 수정 판정을 보류했습니다."
    case "other_page_regions_unresolved": return "페이지의 다른 영역은 판독을 보류했습니다. 표시된 문구만 영역별로 비교했습니다."
    case "ocr_inferred_text_requires_source_review": return "OCR로 추정한 문구입니다. 원문 화면을 확인하세요."
    case "pdf_visibility_unresolved_text_comparison_withheld": return "가림이나 판독 불확실성이 있어 페이지 전체의 텍스트 비교를 보류했습니다."
    case "contextual_ocr_disagreement_primary_retained": return "같은 영역의 판독 결과가 서로 달라 최초 OCR을 보존하고 비교를 보류했습니다."
    case "borderline_ocr_context_unverified_primary_retained": return "문맥 판독을 완료하지 못해 최초 OCR을 보존하고 비교를 보류했습니다."
    case "page_annotation_prevents_inferred_raster_edit": return "PDF 주석이 이 영역에 영향을 줄 수 있어 OCR 수정 판정을 보류했습니다."
    case "ocr_or_text_disagrees_for_identical_native_raster": return "같은 화면에서 텍스트 판독이 달라 실제 수정으로 판정하지 않았습니다."
    case "ocr_region_missing_or_numeric_ambiguity_withheld": return "대응 영역이 누락되거나 숫자 판독이 불확실해 텍스트 비교를 보류했습니다."
    case "ocr_reading_order_changed_without_text_region_change": return "문구 영역은 같지만 OCR의 읽기 순서가 달라 수정 판정을 보류했습니다."
    case "ocr_disagrees_with_unlocalized_source_text": return "OCR과 위치가 불확실한 원문 텍스트가 달라 확인이 필요합니다."
    case "estimated_source_geometry_not_used_for_raster_pairing": return "원문 텍스트의 위치가 불확실해 화면에서 판독한 영역을 기준으로 대응했습니다."
    case "unlocalized_source_text_review_budget_exceeded": return "위치가 불확실한 원문 텍스트를 모두 검토하지 못해 비교를 보류했습니다."
    case "revision_interval_render_appearance_not_comparable": return "두 버전의 형식이나 렌더링 환경이 달라 화면 차이를 직접 비교할 수 없습니다."
    case "native_raster_difference_is_not_semantic_deletion": return "화면 차이는 관측했지만 내용의 삭제 여부는 확정하지 않았습니다."
    case "render_difference_may_include_renderer_substitution": return "화면 차이에 글꼴이나 변환기의 대체 결과가 포함될 수 있습니다."
    case "failed_revision_no_comparison": return "버전 처리에 실패해 비교하지 못했습니다."
    case "raw_text_changed_in_suppressed_layer": return "표시되지 않는 텍스트 계층에서 차이가 발견됐습니다."
    default: return "이 정보의 관측 범위가 충분하지 않습니다. 원문과 내보낸 상세 근거를 확인하세요."
    }
}

struct CoverageGapEvidence:View {
    let gaps:[JSON]
    var body:some View {
        if !gaps.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Text("관측 공백 · 판독 보류 사유").font(.headline)
                ForEach(Array(gaps.enumerated()),id:\.offset){_,gap in
                    Label(coverageReasonName(gap["reason"].string),systemImage:"exclamationmark.circle")
                        .font(.caption).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                }
            }
            .padding(10).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:6))
        }
    }
}

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
                        if !model.focus { ReportBar();Divider();if model.tab != "compare" { VersionBar();Divider() } }
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
// Native draggable document/change panes. Only UI geometry is persisted;
// smoke libraries keep preferences in memory so validation cannot change user settings.
struct WorkspaceSplit<Top:View,Bottom:View>:NSViewControllerRepresentable {
    let name:String
    var defaultBottomHeight:CGFloat
    var compactTopHeight:CGFloat?=nil
    let top:()->Top
    let bottom:()->Bottom
    init(name:String,defaultBottomHeight:CGFloat,compactTopHeight:CGFloat?=nil,@ViewBuilder top:@escaping ()->Top,@ViewBuilder bottom:@escaping ()->Bottom) {
        self.name=name;self.defaultBottomHeight=defaultBottomHeight;self.compactTopHeight=compactTopHeight;self.top=top;self.bottom=bottom
    }
    func makeNSViewController(context:Context)->WorkspaceSplitController<Top,Bottom> {
        WorkspaceSplitController(name:name,defaultBottomHeight:defaultBottomHeight,compactTopHeight:compactTopHeight,top:top(),bottom:bottom())
    }
    func updateNSViewController(_ controller:WorkspaceSplitController<Top,Bottom>,context:Context) {
        controller.top.rootView=top();controller.bottom.rootView=bottom()
    }
}
@MainActor enum WorkspaceGeometryPreferences {
    private static var smokeHeights:[String:Double]=[:]
    static func height(_ key:String)->Double? {
        ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] == nil ? UserDefaults.standard.object(forKey:key) as? Double:smokeHeights[key]
    }
    static func save(_ height:Double,for key:String) {
        if ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] == nil {UserDefaults.standard.set(height,forKey:key)}
        else {smokeHeights[key]=height}
    }
}
@MainActor final class WorkspaceSplitController<Top:View,Bottom:View>:NSSplitViewController {
    let top:NSHostingController<Top>,bottom:NSHostingController<Bottom>
    private let preferenceKey:String
    private let defaultBottomHeight:CGFloat
    private let compactTopHeight:CGFloat?
    private var positioned=false
    private var positioning=false
    private var observer:NSObjectProtocol?
    init(name:String,defaultBottomHeight:CGFloat,compactTopHeight:CGFloat?,top:Top,bottom:Bottom) {
        self.top=NSHostingController(rootView:top);self.bottom=NSHostingController(rootView:bottom)
        preferenceKey="Docver.workspace."+name+".changesHeight";self.defaultBottomHeight=defaultBottomHeight;self.compactTopHeight=compactTopHeight
        super.init(nibName:nil,bundle:nil)
        splitView.isVertical=false;splitView.dividerStyle = .thin;splitView.identifier=NSUserInterfaceItemIdentifier("Docver.workspace."+name)
        let upper=NSSplitViewItem(viewController:self.top),lower=NSSplitViewItem(viewController:self.bottom)
        upper.minimumThickness=150;lower.minimumThickness=105;lower.maximumThickness=900
        upper.holdingPriority = .defaultLow;lower.holdingPriority=NSLayoutConstraint.Priority(260)
        addSplitViewItem(upper);addSplitViewItem(lower)
        observer=NotificationCenter.default.addObserver(forName:NSSplitView.didResizeSubviewsNotification,object:splitView,queue:.main) { [weak self] _ in
            guard let self,self.positioned,!self.positioning,self.splitView.subviews.count==2 else{return}
            let height=self.splitView.subviews[1].frame.height
            if height>=105 && height.isFinite {WorkspaceGeometryPreferences.save(Double(height),for:self.preferenceKey)}
        }
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    deinit {if let observer {NotificationCenter.default.removeObserver(observer)}}
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !positioned,splitView.bounds.height>260,splitView.subviews.count==2 else{return}
        positioning=true;positioned=true
        let available=splitView.bounds.height-splitView.dividerThickness
        let initial=compactTopHeight.map {available-$0} ?? defaultBottomHeight
        let saved=WorkspaceGeometryPreferences.height(preferenceKey)
        let height=min(max(105,CGFloat(saved ?? Double(initial))),max(105,available-150))
        splitView.setPosition(available-height,ofDividerAt:0)
        positioning=false
    }
}
struct ComparePagesView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        HSplitView {
            if model.pageMode != "after" {PageColumn(revision:model.revision(model.from),side:"이전",pageID:$model.leftPageID)}
            if model.pageMode != "before" {PageColumn(revision:model.revision(model.to),side:"이후",pageID:$model.rightPageID)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
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
                Group {
                    if model.showChanges {
                        WorkspaceSplit(name:"compare",defaultBottomHeight:140) {
                            ComparePagesView().environmentObject(model)
                        } bottom: {
                            ChangeListView().environmentObject(model)
                        }
                    } else { ComparePagesView() }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.inspector { InspectorView().frame(minWidth:275,idealWidth:300,maxWidth:360) }
            }
        }.onChange(of:model.selectedChangeID){Task {await Task.yield();model.selectEvidence()}}
    }
}
struct ChangeListView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {VStack(spacing:5){HStack{Picker("유형",selection:$model.kind){Text("전체 변경").tag("all");ForEach(changeNames.keys.sorted(),id:\.self){Text(changeNames[$0]!).tag($0)}}.frame(width:180);TextField("원문에서 검색",text:$model.search).textFieldStyle(.roundedBorder).frame(maxWidth:250);Spacer();if model.loadingChanges{ProgressView().controlSize(.small)};Text("\(model.filteredChanges.count)개").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,12).padding(.top,8)
        ScrollView { LazyVStack(spacing:1) { ForEach(model.filteredChanges) { c in Button {model.chooseChange(c["change_id"].string)} label: {ChangeRow(change:c).padding(.horizontal,10).padding(.vertical,4).contentShape(Rectangle())}.buttonStyle(.plain).disabled(model.loadingChanges).background(model.selectedChangeID==c["change_id"].string ? Color.blue.opacity(0.12) : Color.clear) } }.padding(6) }
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
    var mappingUnavailableReason: String? {
        if model.busy { return "분석이 끝난 뒤 대응을 수정할 수 있습니다." }
        if model.loading || model.loadingChanges { return "변경 목록을 불러오고 있습니다." }
        if model.project["dirty"].bool { return "대기 중인 수정을 재분석한 뒤 대응을 수정하세요." }
        if model.project["last_report_id"].string != model.report["report_id"].string { return "최신 보고서를 선택하세요." }
        if model.to != model.from+1 { return "서로 인접한 두 버전을 선택하세요." }
        if !model.primaryPages(model.revision(model.from)).contains(where:{$0["page_id"].string==model.leftPageID}) || !model.primaryPages(model.revision(model.to)).contains(where:{$0["page_id"].string==model.rightPageID}) { return "양쪽 원문 페이지를 하나씩 선택하세요." }
        return nil
    }
    var editable: Bool { mappingUnavailableReason == nil }
    var structural: Bool { !model.selected["topology"].isNull }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:16) {
                Text("선택한 변경").font(.caption).foregroundStyle(.secondary)
                Text(changeNames[model.selected["kind"].string] ?? "변경을 선택하세요").font(.title3.weight(.semibold))
                if !model.selected.isNull {
                    Text(structural ? "이전 구성" : "이전 원문").font(.caption).foregroundStyle(.secondary)
                    Text(model.selected["before"].isNull ? "해당 버전에서 원문 없음" : model.selected["before"].string).foregroundStyle(structural ? Color.primary : Color.red).textSelection(.enabled)
                    Text(structural ? "이후 구성" : "이후 원문").font(.caption).foregroundStyle(.secondary)
                    Text(model.selected["after"].isNull ? "해당 버전에서 원문 없음" : model.selected["after"].string).foregroundStyle(structural ? Color.primary : Color.green).textSelection(.enabled)
                    if structural { Text("아래의 각 페이지를 눌러 원문을 확인하세요. 계보의 같은 묶음에 있어도 모든 페이지가 서로 직접 연결되는 것은 아닙니다.").font(.caption).foregroundStyle(.secondary) }
                    Divider();Text("원문 근거").font(.headline)
                    ForEach(Array(model.selected["evidence"].array.enumerated()),id:\.offset) { _,e in
                        VStack(alignment:.leading,spacing:6) {
                            Button { model.navigateEvidence(e) } label: { Label("page \(e["page"].int) · "+evidenceMethodName(e["method"].string,provenance:e["provenance"].string),systemImage:"doc.text.magnifyingglass").font(.caption) }.buttonStyle(.plain)
                            Text(e["quote"].string).font(.caption).textSelection(.enabled)
                        }.padding(9).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
                    }
                    if !model.selected["appearance_assessment"].string.isEmpty { Text(model.selected["appearance_assessment"].string == "observed" ? "표시 상태: 관측" : "표시 상태: 추정").font(.caption).foregroundStyle(.orange) }
                    Text(lineageReasonText(model.selected["lineage"]["reasons"].array,humanConfirmed:model.selected["lineage"]["status"].string == "human_confirmed" && model.selected["topology"]["semantics"].string != "directed_reachability")).font(.caption2).foregroundStyle(.secondary)
                    CoverageGapEvidence(gaps:model.selected["coverage_gaps"].array)
                }
                Divider();Text("페이지 대응 검토").font(.headline)
                Text("인접 버전의 페이지를 연결·해제하거나 분할·병합 관계로 묶습니다. 이유를 남기면 새 보고서로 분석합니다.").font(.caption).foregroundStyle(.secondary)
                Button("연결·분할·병합 수정…") { model.mappingSheet=true }.disabled(!editable).accessibilityHint(Text(mappingUnavailableReason ?? "페이지 대응을 수정합니다"))
                if let message=mappingUnavailableReason { Text(message).font(.caption).foregroundStyle(.secondary) }
                Divider();Label("관측 한계",systemImage:"exclamationmark.triangle").font(.headline)
                Text("가려진 텍스트와 취소선은 표시 상태로 보존합니다. 박스나 선이 삭제 의도인지는 시각 근거와 함께 검토하세요. PDF에서 추정한 표 구조는 PPTX의 원래 표와 동일하다고 보장하지 않습니다.").font(.caption)
                Text("OCR 추정 값은 원본 화면과 대조하세요. PDF에 없는 노트·숨김 정보는 삭제로 집계하지 않습니다. PPTX는 LibreOffice 변환 화면이며 폰트 대체·변환 경고를 근거 패널에서 확인할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }.padding(17).frame(maxWidth:.infinity,alignment:.leading)
        }.sheet(isPresented:$model.mappingSheet) {
            MappingSheet(projectID:model.projectID,reportID:model.report["report_id"].string,draftHash:model.report["draft_hash"].string,before:model.revision(model.from),after:model.revision(model.to),left:Set(model.mappingSelection["from_page_ids"].array.map(\.string)),right:Set(model.mappingSelection["to_page_ids"].array.map(\.string)),mode:model.mappingSelection["kind"].string,reason:model.mappingSelection["reason"].string).environmentObject(model)
        }
    }
}
struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        WorkspaceSplit(name:"history",defaultBottomHeight:200,compactTopHeight:model.report["lineages"].array.count<6 ? CGFloat(model.report["lineages"].array.count)*65+115 : nil) {
            HistoryGraphView().environmentObject(model)
        } bottom: { ChangeListView().environmentObject(model) }
    }
}
struct HistoryGraphView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {VStack(alignment:.leading,spacing:14){HStack{VStack(alignment:.leading){Text("전체 버전 이력").font(.title2.weight(.semibold));Text("중간에 생겼다가 사라진 페이지와 관측 공백을 함께 보존합니다.").font(.caption).foregroundStyle(.secondary)};Spacer()}.padding(.horizontal,18).padding(.top,20)
        ScrollView([.vertical,.horizontal]){LazyVStack(alignment:.leading,spacing:1){HStack{Text("페이지 계보").frame(width:180,alignment:.leading);ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Text("v\(i+1) "+r["label"].string).frame(width:130)}}.font(.caption.weight(.semibold)).padding(9)
            ForEach(model.report["lineages"].array){lineage in
                let all=model.revisions.flatMap{model.primaryPages($0)},ids=lineage["page_ids"].array.map(\.string)
                if let first=all.first(where:{ids.contains($0["page_id"].string)}){
                    HStack(alignment:.top) {
                        Text(first["text"].string.components(separatedBy:"\n").first ?? "페이지").font(.caption).lineLimit(1).frame(width:180,alignment:.leading)
                        ForEach(Array(model.revisions.enumerated()),id:\.offset) { i,r in
                            let members=model.primaryPages(r).filter { ids.contains($0["page_id"].string) }
                            VStack(spacing:4) {
                                if members.isEmpty { Text("—").font(.caption).foregroundStyle(.secondary).padding(.vertical,7) }
                                ForEach(members) { page in
                                    Button { model.openHistoryPage(i,page["page_id"].string) } label: { Text("p.\(page["page"].int)").font(.caption).frame(width:115).padding(.vertical,7).background(Color.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).accessibilityLabel("\(r["label"].string) 페이지 \(page["page"].int) 열기")
                                }
                            }.frame(width:130)
                        }
                    }.padding(7);Divider()
                }
            }
            Text("— 관측 없음 · 실제 삭제 여부는 변경 이벤트와 원문 근거에서 확인하세요.").font(.caption).foregroundStyle(.secondary).padding(.top,8)
        }.padding(12)}
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
