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
    case "reference_pdf_changed_without_pptx_source_change": return "PPTX 원본은 같지만 제공된 PDF 화면이 다릅니다. PDF가 해당 버전에서 내보낸 파일인지 확인하세요."
    case "pptx_source_changed_despite_identical_reference_pixels": return "PPTX 원본은 바뀌었지만 제공된 PDF 화면은 같습니다. 원본의 변경이 PDF에 반영됐는지 확인하세요."
    case "reference_appearance_unavailable_or_unverified_for_page": return "이 페이지의 화면 근거를 양쪽 모두 확인하지 못해 화면 비교를 보류했습니다. 다른 페이지의 비교는 유지합니다."
    case "provided_pdf_visual_difference_with_inferred_source_association": return "제공된 PDF 화면의 차이입니다. PDF와 PPTX 페이지의 대응은 추정이며 원본 화면의 충실도를 보증하지 않습니다."
    case "provided_pdf_association_inferred_not_powerpoint_equivalence": return "제공된 PDF 화면을 표시합니다. PPTX 페이지와의 대응은 추정이므로 해당 버전에서 내보낸 PDF인지 확인하세요."
    case "reference_pdf_reused_for_different_pptx": return "하나의 PDF가 서로 다른 PPTX 원본에 묶여 있어 자동 화면 대응을 보류했습니다."
    case "reference_rotation_requires_review": return "회전된 PDF의 자동 화면 대응을 보류했습니다. 원문 방향을 확인하세요."
    case "reference_geometry_mismatch": return "PPTX와 제공된 PDF의 페이지 비율이 달라 자동 화면 대응을 보류했습니다."
    case "manual_reference_not_powerpoint_equivalence": return "사용자가 연결한 PDF 화면입니다. 연결은 PowerPoint 원본 화면의 충실도를 보증하지 않습니다."
    case "manual_reference_text_unresolved_or_different": return "연결한 PPTX와 PDF의 문구가 다르거나 판독이 불확실합니다. 원문을 확인하세요."
    case "manual_reference_geometry_mismatch": return "연결한 PPTX와 PDF의 페이지 비율이 다릅니다."
    case "manual_reference_pdf_reused_for_different_pptx": return "이 PDF는 다른 PPTX 원본에도 사용되었습니다. 연결한 버전이 맞는지 확인하세요."
    case "manual_reference_linked_hidden_source_slide": return "숨김 슬라이드에 PDF 페이지를 연결했습니다. 내보내기 범위를 확인하세요."
    case "manual_reference_native_raster_unavailable": return "연결한 PDF의 화면 비교 근거를 확보하지 못했습니다."
    case "manual_reference_transform_unavailable": return "PDF 페이지의 좌표 변환을 확인하지 못해 연결 화면을 사용하지 않았습니다."
    case "manual_reference_explicitly_unlinked": return "사용자가 이 슬라이드의 PDF 연결을 해제하고 자동 연결을 차단했습니다."
    case "manual_reference_displaced_by_another_source": return "다른 슬라이드가 같은 PDF 페이지를 사용하도록 연결되어 기존 연결이 해제되었습니다."
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
            if !model.sidecarRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.sidecarRecoveryWarning);Spacer();Button("임시 작업 폴더"){NSWorkspace.shared.open(model.bridge.library.appendingPathComponent("sidecars-v1"))};Button("닫기"){model.sidecarRecoveryWarning=""}}.font(.caption).padding(10).background(.orange.opacity(0.1))}
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
            Divider();HStack { Label("내 Mac에만 저장",systemImage:"internaldrive");Spacer();Text(!model.evidenceWarning.isEmpty ? model.evidenceWarning:model.status.isEmpty ? "근거 · 추정 · 관측 공백을 구분합니다" : model.status);Spacer();Text("Docver · Native macOS") }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,14).padding(.vertical,5)
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
        }.onChange(of:model.tab){if model.tab != "export"{model.changeRange()}}
        .sheet(isPresented:$model.importSheet){ImportView()}
        .alert(item:$model.reorderConfirmation){request in Alert(title:Text("버전 순서를 바꿀까요?"),message:Text(request.message),primaryButton:.destructive(Text("순서 변경")){Task{await model.confirmReorder(request)}},secondaryButton:.cancel(Text("취소")))}
        .sheet(item:$model.sidecarRequest){request in OnlyOfficeSidecarSheet(request:request).environmentObject(model)}
        .sheet(isPresented:$model.bundleSheet){BundleSheet(projectID:model.bundleProjectID,reportID:model.bundleReportID,occurrence:model.bundleOccurrence,initialSource:model.bundleSourceID).environmentObject(model)}
        .task {await model.start()}
    }
}
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack{Text("프로젝트").font(.caption).foregroundStyle(.secondary);Spacer();Button{model.importSheet=true}label:{Image(systemName:"plus")}.buttonStyle(.borderless).disabled(model.busy || model.loading)}.padding(.horizontal,14).padding(.top,18)
            List(model.projects){p in Button{Task{await model.selectProject(p["project_id"].string)}}label:{HStack{Image(systemName:"folder.fill").foregroundStyle(.blue);VStack(alignment:.leading,spacing:3){Text(p["title"].string).lineLimit(1);Text(p["unreadable"].bool ? "입력 손상 · 기존 자료 보존":"\(p["revisions"].array.count)개 버전"+(p["dirty"].bool ? " · 분석 대기":"")).font(.caption2).foregroundStyle(.secondary)}}.padding(.vertical,5)}.buttonStyle(.plain).disabled(model.busy||model.loading).help(p["unreadable"].bool ? "입력 기록을 읽지 못했습니다. 기존 원문과 보고서는 보존했습니다.":p["title"].string).listRowBackground(p["project_id"].string==model.projectID ? Color.blue.opacity(0.12):Color.clear)}.listStyle(.sidebar).frame(minHeight:80,maxHeight:220)
            if !model.project.isNull {
                if model.project["unreadable"].bool {
                    Label("고정 보고서 읽기 전용",systemImage:"lock.doc").font(.caption).padding(.horizontal,14)
                    Text("입력 기록을 읽지 못했습니다. 기존 보고서와 원문은 계속 열 수 있습니다. 다시 분석하려면 새 프로젝트로 가져오세요.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,14)
                }else{
                Text("가져오기 순서").font(.caption).foregroundStyle(.secondary).padding(.horizontal,14)
                ScrollView { LazyVStack(spacing:0){ForEach(Array(model.project["revisions"].array.enumerated()),id:\.offset){i,r in HStack(spacing:8){Text(String(format:"%02d",i+1)).foregroundStyle(.secondary).font(.caption2);VStack(alignment:.leading,spacing:4){Text(r["label"].string).lineLimit(1).font(.caption);Text(r["files"].array.map{$0["blob"].string.hasSuffix("pdf") ? "PDF":"PPTX"}.joined(separator:" + ")).font(.caption2).foregroundStyle(.secondary)};Spacer();VStack(spacing:3){Button{Task{await model.reorder(i,delta:-1)}}label:{Image(systemName:"chevron.up")}.disabled(i==0||model.busy||model.loading||model.reorderConfirmation != nil);Button{Task{await model.reorder(i,delta:1)}}label:{Image(systemName:"chevron.down")}.disabled(i==model.project["revisions"].array.count-1||model.busy||model.loading||model.reorderConfirmation != nil)}.buttonStyle(.borderless).font(.caption2)}.padding(.horizontal,14).padding(.vertical,9);Divider()}} }
                Button(model.project["dirty"].bool ? "입력·대응 변경 분석":"다시 분석"){Task{await model.run(model.projectID)}}.disabled(model.busy || model.loading || model.project["unreadable"].bool).frame(maxWidth:.infinity).padding(.horizontal,14)
                }
            }
            Spacer(minLength:5)
            Button{model.importSheet=true}label:{Label("문서 버전 가져오기",systemImage:"plus")}.disabled(model.busy || model.loading).frame(maxWidth:.infinity).padding(14)
        }.background(Color(nsColor:.underPageBackgroundColor))
    }
}
struct EmptyWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View { VStack(spacing:22){Image(systemName:"doc.on.doc").font(.system(size:62,weight:.light)).foregroundStyle(.blue);Text("문서가 바뀐 모든 순간을\n한눈에 따라가세요.").font(.system(size:32,weight:.semibold)).multilineTextAlignment(.center);Text("PPTX와 PDF를 순서대로 모으면 숫자 수정부터\n중간에 사라진 페이지까지 원문과 함께 확인할 수 있습니다.").foregroundStyle(.secondary).multilineTextAlignment(.center);HStack{Button("문서 버전 가져오기"){model.importSheet=true}.buttonStyle(.borderedProminent);Button("5버전 합성 데모 열기"){Task{await model.demo()}}}.disabled(model.busy || model.loading);Text("계정 없이 · 업로드 없이 · 네이티브 macOS 앱").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity) }
}
struct ReportBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {HStack{Label("고정 보고서",systemImage:"lock.doc").font(.caption);Picker("보고서",selection:Binding(get:{model.report["report_id"].string},set:{id in Task{await model.selectProject(model.projectID,snapshot:id)}})){ForEach(model.reports){r in Text(String(r["report_id"].string.dropFirst(4).prefix(12))+" · "+String(r["created_at"].string.prefix(16))).tag(r["report_id"].string)}}.labelsHidden().frame(width:300).disabled(model.busy || model.loading);Spacer();if model.project["dirty"].bool{Text("입력/대응 변경 · 아래는 이전 보고서").font(.caption).foregroundStyle(.orange)};Text("\(model.revisions.count)개 버전").font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,16).padding(.vertical,8)}
}
struct VersionBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Button{model.from=min(i,max(0,model.revisions.count-2));model.to=min(model.revisions.count-1,model.from+1);model.changeRange()}label:{VStack(spacing:5){Circle().fill(i==model.from||i==model.to ? Color.blue:Color.gray.opacity(0.3)).frame(width:11,height:11);Text(versionDisplayName(i,r)).font(.caption.weight(.semibold));Text("\(model.primaryPages(r).count)쪽 · "+r["assets"].array.map{$0["format"].string.uppercased()}.joined(separator:"+")).font(.caption2).foregroundStyle(.secondary);if r["status"].string != "success"{Text("부분 실패 · 확인 필요").font(.caption2).foregroundStyle(.orange)}}.frame(minWidth:135).padding(7)}.buttonStyle(.plain)}}.padding(.horizontal,15).padding(.vertical,9)}}
}
struct ComparePagesView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        HSplitView {
            if model.revisions.count<2 {PageColumn(revision:model.revision(0),side:"원문",pageID:$model.leftPageID)}
            else {
                if model.pageMode != "after" {PageColumn(revision:model.revision(model.from),side:"이전",pageID:$model.leftPageID)}
                if model.pageMode != "before" {PageColumn(revision:model.revision(model.to),side:"이후",pageID:$model.rightPageID)}
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

struct CompareWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing:0){
            HStack(spacing:10){
                if model.revisions.count>1 {
                Picker("이전",selection:$model.from){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i<model.to{Text(versionDisplayName(i,r)).tag(i)}}}.frame(maxWidth:220)
                Image(systemName:"arrow.right").foregroundStyle(.secondary)
                Picker("이후",selection:$model.to){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i>model.from{Text(versionDisplayName(i,r)).tag(i)}}}.frame(maxWidth:220)
                Text(model.to==model.from+1 ? "인접 비교":"선택 구간의 순변경").font(.caption).foregroundStyle(.secondary);Spacer()
                }else{Text("원문 보기 · "+versionDisplayName(0,model.revision(0))).font(.headline);Spacer()}
                Button{model.inspector.toggle()}label:{Label("근거",systemImage:"sidebar.right")}
            }.padding(.horizontal,16).padding(.top,12).onChange(of:model.from){model.changeRange()}.onChange(of:model.to){model.changeRange()}
            HStack{
                if model.revisions.count>1 {Picker("문서 보기",selection:$model.pageMode){Text("두 페이지").tag("both");Text("이전만 크게").tag("before");Text("이후만 크게").tag("after")}.pickerStyle(.segmented).frame(width:295)}
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
        if model.filteredChanges.isEmpty {Text(model.emptyChangesMessage).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity).padding(12)}
        else {ScrollView { LazyVStack(spacing:1) { ForEach(model.filteredChanges) { c in Button {model.chooseChange(c["change_id"].string)} label: {ChangeRow(change:c).padding(.horizontal,10).padding(.vertical,4).contentShape(Rectangle())}.buttonStyle(.plain).disabled(model.loadingChanges || !model.changesFailure.isEmpty).background(model.selectedChangeID==c["change_id"].string ? Color.blue.opacity(0.12) : Color.clear) } }.padding(6) }}
    }}
}

struct ChangeRow: View {
    @EnvironmentObject var model:AppModel
    let change: JSON
    var kindName: String {changeDisplayName(change)}
    var text: String {(change["after"].isNull ? change["before"].string:change["after"].string).replacingOccurrences(of:"\n",with:" ")}
    var status: String {let value=change["lineage"]["status"].string;return value=="human_confirmed" ? "사용자 확정":value=="needs_review" ? "검토 필요":"추정 대응"}
    var body: some View {HStack(spacing:10){Text(kindName).font(.caption).foregroundStyle(change["kind"].string=="coverage_gap" ? Color.secondary:Color.blue).frame(width:85,alignment:.leading);VStack(alignment:.leading,spacing:3){Text(text).lineLimit(1).font(.caption);if model.tab=="history"{Text(changeVersionSummary(change,revisions:model.revisions)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)};Text(evidencePageSummary(change)).font(.caption2).foregroundStyle(.secondary)};Spacer();if change["region_pairing_assessment"].string == "inferred"{Text("영역 대응 추정").font(.caption2).foregroundStyle(.orange)};if change["text_assessment"].string == "inferred"{Text("OCR 추정 · 원문 확인").font(.caption2).foregroundStyle(.orange)};if !change["appearance_assessment"].string.isEmpty{Text(change["appearance_assessment"].string=="observed" ? "표시 관측":"표시 추정").font(.caption2).foregroundStyle(.orange)};Text(status).font(.caption2).foregroundStyle(.secondary)}.padding(.vertical,3)}
}

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    var mappingUnavailableReason: String? {
        if model.project["unreadable"].bool{return "입력 기록 손상 · 고정 보고서 읽기 전용입니다."}
        if model.busy { return "분석이 끝난 뒤 대응을 수정할 수 있습니다." }
        if model.loading || model.loadingChanges { return "변경 목록을 불러오고 있습니다." }
        if model.project["dirty"].bool { return "대기 중인 수정을 재분석한 뒤 대응을 수정하세요." }
        if model.project["last_report_id"].string != model.report["report_id"].string { return "최신 보고서를 선택하세요." }
        if model.revisions.count<2 {return "다른 버전을 가져오면 페이지 대응을 검토할 수 있습니다."}
        if model.to != model.from+1 { return "서로 인접한 두 버전을 선택하세요." }
        if !model.primaryPages(model.revision(model.from)).contains(where:{$0["page_id"].string==model.leftPageID}) || !model.primaryPages(model.revision(model.to)).contains(where:{$0["page_id"].string==model.rightPageID}) { return "양쪽 원문 페이지를 하나씩 선택하세요." }
        return nil
    }
    var editable: Bool { mappingUnavailableReason == nil }
    var structural: Bool { !model.selected["topology"].isNull }
    var neutralText:Bool {structural || ["coverage_gap","text_occluded","text_struck_through","text_revealed"].contains(model.selected["kind"].string) || isReferenceAppearanceChange(model.selected)}
    func sourceText(_ value:JSON,other:JSON,before:Bool)->Text {
        if value.isNull{return Text("해당 버전에서 원문 없음").foregroundColor(.secondary)}
        if neutralText{return Text(value.string).foregroundColor(.primary)}
        return changeTextRuns(value.string,comparedWith:other.isNull ? "":other.string).reduce(Text("")){text,run in
            text+Text(run.text).foregroundColor(run.changed ? (before ? .red:.green):.primary).underline(run.changed)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                Text("선택한 변경").font(.caption).foregroundStyle(.secondary)
                Text(model.selected.isNull && model.filteredChanges.isEmpty ? model.emptyChangesMessage:changeDisplayName(model.selected)).font(.title3.weight(.semibold))
                if !model.selected.isNull {
                    Text(structural ? "이전 구성" : "이전 원문").font(.caption).foregroundStyle(.secondary)
                    sourceText(model.selected["before"],other:model.selected["after"],before:true).textSelection(.enabled)
                    Text(structural ? "이후 구성" : "이후 원문").font(.caption).foregroundStyle(.secondary)
                    sourceText(model.selected["after"],other:model.selected["before"],before:false).textSelection(.enabled)
                    if !neutralText {Text("색과 밑줄은 비교에서 달라진 문구입니다. 긴 원문은 강조를 생략할 수 있습니다.").font(.caption2).foregroundStyle(.secondary)}
                    if structural { Text("아래의 각 페이지를 눌러 원문을 확인하세요. 계보의 같은 묶음에 있어도 모든 페이지가 서로 직접 연결되는 것은 아닙니다.").font(.caption).foregroundStyle(.secondary) }
                    Divider();Text("원문 근거").font(.headline)
                    ForEach(Array(model.selected["evidence"].array.enumerated()),id:\.offset) { _,e in
                        VStack(alignment:.leading,spacing:6) {
                            Button { model.navigateEvidence(e) } label: { Label(evidenceVersionLabel(e,change:model.selected,revisions:model.revisions)+" · "+evidenceMethodName(e["method"].string,provenance:e["provenance"].string),systemImage:"doc.text.magnifyingglass").font(.caption) }.buttonStyle(.plain)
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
                Text("OCR 추정 값은 원본 화면과 대조하세요. PDF에 없는 노트·숨김 정보는 삭제로 집계하지 않습니다. PPTX 화면에는 제공된 PDF 또는 LibreOffice 변환본을 사용합니다. 페이지 위의 출처와 근거 패널의 대응·변환 경고를 확인하세요.").font(.caption).foregroundStyle(.secondary)
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
    var body:some View {VStack(alignment:.leading,spacing:14){HStack{VStack(alignment:.leading){Text("전체 버전 이력").font(.title2.weight(.semibold));Text("중간에 생겼다가 사라진 페이지와 관측 공백을 함께 보존합니다.").font(.caption).foregroundStyle(.secondary);Text("— 관측 없음 · 실제 삭제 여부는 변경 이벤트와 원문 근거에서 확인하세요.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)};Spacer()}.padding(.horizontal,18).padding(.top,20)
        ScrollView([.vertical,.horizontal]){LazyVStack(alignment:.leading,spacing:1){HStack{Text("페이지 계보").frame(width:180,alignment:.leading);ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Text(versionDisplayName(i,r)).frame(width:130)}}.font(.caption.weight(.semibold)).padding(9)
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
        }.padding(12)}
    }}
}
struct ExportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:22){Text("원문과 이력을 함께 전달하세요.").font(.largeTitle.weight(.semibold));Text("같은 고정 보고서를 파일과 읽기 전용 MCP에서 조회합니다.").foregroundStyle(.secondary)
        GroupBox("보고서 파일 저장"){VStack(alignment:.leading,spacing:12){Text("전체 report, 변경 JSONL, 페이지·요소 원문, 버전·계보, 페이지별 Markdown과 근거 링크를 저장합니다.");Button("JSON·Markdown 내보내기"){Task{await model.exportReport()}}.buttonStyle(.borderedProminent)}.padding(12).frame(maxWidth:.infinity,alignment:.leading)}
        GroupBox("읽기 전용 MCP 연결"){VStack(alignment:.leading,spacing:12){Text("앱에 포함된 Node 런타임과 현재 프로젝트의 보관소를 사용합니다. 앱 위치를 옮기면 설정을 다시 복사하세요.").font(.caption).foregroundStyle(.secondary);Text(model.currentMCPConfig ?? (model.mcpFailure.isEmpty ? "현재 프로젝트의 설정을 준비하고 있습니다…":"설정을 불러오지 못했습니다. "+model.mcpFailure)).font(.system(.caption,design:.monospaced)).textSelection(.enabled).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.textBackgroundColor));Button("설정 복사"){guard let config=model.currentMCPConfig else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(config,forType:.string);model.status="현재 프로젝트의 MCP 설정을 복사했습니다"}.disabled(model.currentMCPConfig == nil);if !model.mcpFailure.isEmpty {Button("설정 다시 불러오기"){Task{await model.loadMCP()}}}}.padding(12)}
        GroupBox("표시 상태와 표 구조의 한계"){Text("취소선 주석은 관측 사실로, 납작해진 선·박스 가림은 기하·그림 순서에 기반한 추정으로 구분합니다. 부분 가림·마스크·회전·이미지는 불확실성을 남깁니다. PDF 격자는 추정된 구조이며 원래 PPTX 표의 셀 의미를 복원했다고 단정하지 않습니다. 스캔 OCR과 화면 표는 추정 근거로 보존하며 낮은 점수·대안 충돌·누락 영역은 보류합니다. 원문 화면에서 확인하세요.").font(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading)}
    }.padding(35).frame(maxWidth:1000,alignment:.leading)}.task(id:model.projectID){await model.loadMCP()}}
}
struct ImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var title="새 문서 프로젝트"
    @State private var rows:[ImportRow]=[]
    @State private var saving=false
    @State private var choosing=false
    @State private var failure=""
    init(initialRows:[ImportRow]=[]){_rows=State(initialValue:initialRows)}
    var locked:Bool{saving || choosing}
    var body: some View {
        VStack(alignment:.leading,spacing:17){
            HStack{Text("문서 버전 가져오기").font(.title2.weight(.semibold));Spacer();Button("닫기"){dismiss()}.keyboardShortcut(.cancelAction).disabled(locked)}
            Text("PPTX 또는 PDF 하나로 시작하고, 같은 버전의 PPTX + PDF를 묶을 수도 있습니다. 수백 페이지 문서는 선택한 페이지부터 지연 표시합니다.").font(.callout).foregroundStyle(.secondary)
            TextField("프로젝트 이름",text:$title).textFieldStyle(.roundedBorder).disabled(locked)
            Button{choose()}label:{Label("PPTX·PDF 파일 선택",systemImage:"plus")}.disabled(locked)
            List{
                ForEach(Array(rows.enumerated()),id:\.element.id){i,r in
                    HStack{
                        Text("\(i+1)").foregroundStyle(.secondary)
                        VStack(alignment:.leading){
                            TextField("버전 이름",text:Binding(get:{rows.indices.contains(i) ? rows[i].label:""},set:{if rows.indices.contains(i){rows[i].label=$0}})).disabled(locked)
                            Text(r.urls.map(\.lastPathComponent).joined(separator:" + ")).font(.caption2).foregroundStyle(.secondary)
                            if r.members.count==2{Label("같은 버전 · PPTX + PDF",systemImage:"link").font(.caption).foregroundStyle(.secondary)}
                        }
                        Button{ImportRow.move(&rows,at:i,by:-1)}label:{Image(systemName:"chevron.up")}.disabled(i==0 || locked).accessibilityLabel("버전 위로 이동")
                        Button{ImportRow.move(&rows,at:i,by:1)}label:{Image(systemName:"chevron.down")}.disabled(i==rows.count-1 || locked).accessibilityLabel("버전 아래로 이동")
                        if r.members.count==2{
                            Button("묶음 해제"){ImportRow.ungroup(&rows,at:i)}.disabled(locked).help("파일을 바로 아래 두 버전으로 나눕니다. 수정한 묶음 이름은 첫 파일에 남습니다.")
                        }else{
                            Button("위와 묶기"){ImportRow.group(&rows,at:i)}.disabled(locked || ImportRow.groupingUnavailable(rows,at:i) != nil).help(ImportRow.groupingUnavailable(rows,at:i) ?? "두 파일을 같은 버전으로 묶습니다. 파일별 이름과 순서를 보존합니다.")
                        }
                        Button{if rows.indices.contains(i){rows.remove(at:i)}}label:{Image(systemName:"xmark")}.disabled(locked).accessibilityLabel("버전 제거")
                    }
                }
            }.frame(minHeight:230,maxHeight:360)
            if !failure.isEmpty{Text(failure).foregroundStyle(.red).font(.caption)}
            HStack{
                Text("선택한 파일의 내용이 바뀌지 않았는지 확인한 뒤 앱 전용 보관소에 복사합니다.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if locked{ProgressView().controlSize(.small);Text(choosing ? "파일 확인 중…":"가져오는 중…").font(.caption)}
                Button("이 순서로 분석 시작"){Task{await create()}}.buttonStyle(.borderedProminent).disabled(locked || rows.isEmpty || title.trimmingCharacters(in:.whitespaces).isEmpty || rows.contains{$0.label.trimmingCharacters(in:.whitespaces).isEmpty})
            }
        }.padding(25).frame(width:900)
    }
    func choose(){
        let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.allowedContentTypes=[.pdf,UTType(filenameExtension:"pptx") ?? .data];panel.canChooseDirectories=false
        if panel.runModal() == .OK{
            let urls=panel.urls;choosing=true;failure=""
            Task{
                do{let selected=try await Task.detached(priority:.userInitiated){try urls.map{try ImportRow.selected($0)}}.value;rows += selected}
                catch{failure=error.localizedDescription}
                choosing=false
            }
        }
    }
    func create() async {saving=true;do{let p=try await model.create(title:title,rows:rows);model.report=JSON();try await model.refresh();model.projectID=p["project_id"].string;dismiss();await model.run(model.projectID)}catch{failure=error.localizedDescription};saving=false}
}
