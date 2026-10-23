import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor func matchingReasonName(_ value:String,humanConfirmed:Bool=false)->String {
    // Reasons have no per-item origin tag. Preserve human-confirmed reasons
    // verbatim, including engine-like prefixes, rather than rewrite user input.
    if humanConfirmed { return value }
    if value.hasPrefix("appearance:") {
        let states=String(value.dropFirst("appearance:".count)).components(separatedBy:"→")
        return L("doc.matching.appearanceChange", .verbatim(states.map { appearanceStateName($0) }.joined(separator:" → ")))
    }
    switch value {
    case "exact_source_page": return L("doc.matching.exactSource")
    case "exact_native_raster": return L("doc.matching.exactRaster")
    case "normalized_text_bigrams": return L("doc.matching.textSimilarity")
    case "competing_duplicate_or_split_merge_candidate": return L("doc.matching.competingCandidates")
    case "candidate_pool_limited_to_top_8_per_direction": return L("doc.matching.limitedCandidates")
    case "gap_applies_to_entire_revision_interval": return L("doc.matching.intervalGap")
    case "unmatched_page": return L("doc.matching.unmatched")
    case "directed_lineage_range_net": return L("doc.matching.directedLineage")
    case "structural_lineage_does_not_confirm_text": return L("doc.matching.noTextConfirmation")
    case "snapshot_lineage_range_net": return L("doc.matching.snapshotLineage")
    default: return L("doc.matching.otherCode", .verbatim(value))
    }
}
@MainActor func evidenceMethodName(_ value:String,provenance:String)->String {
    let label:String
    switch value {
    case "pdf_text": label=L("doc.evidence.pdfText")
    case "vision_ocr": label=L("doc.evidence.ocr")
    case "native_raster": label=L("doc.evidence.raster")
    case "provided_pdf_native_raster": label=L("doc.evidence.providedPDFRaster")
    case "page_observation": label=L("doc.evidence.page")
    case "pdf_page_annotation": label=L("doc.evidence.annotation")
    default: label=value.hasPrefix("pptx") || value.hasPrefix("ooxml") ? L("doc.evidence.pptxStructure") : L("doc.evidence.documentCode", .verbatim(value))
    }
    if value == "vision_ocr" || provenance == "inferred" { return L("doc.evidence.inferred", .verbatim(label)) }
    return provenance == "observed" ? L("doc.evidence.observed", .verbatim(label)) : L("doc.evidence.unknownProvenance", .verbatim(label), .verbatim(provenance))
}

@MainActor func lineageReasonText(_ reasons:[JSON],humanConfirmed:Bool)->String {
    var seen=Set<String>()
    return reasons.map { matchingReasonName($0.string,humanConfirmed:humanConfirmed) }.filter { seen.insert($0).inserted }.joined(separator:" · ")
}

@MainActor func coverageReasonName(_ value:String)->String {
    switch value {
    case "split_merge_text_comparison_withheld": return L("doc.coverage.splitMerge")
    case "ocr_fragment_reflow_region_withheld": return L("doc.coverage.ocrReflow")
    case "other_page_regions_unresolved": return L("doc.coverage.otherRegions")
    case "ocr_inferred_text_requires_source_review": return L("doc.coverage.ocrReview")
    case "pdf_visibility_unresolved_text_comparison_withheld": return L("doc.coverage.visibilityUnresolved")
    case "contextual_ocr_disagreement_primary_retained": return L("doc.coverage.contextDisagreement")
    case "borderline_ocr_context_unverified_primary_retained": return L("doc.coverage.contextIncomplete")
    case "page_annotation_prevents_inferred_raster_edit": return L("doc.coverage.annotation")
    case "ocr_or_text_disagrees_for_identical_native_raster": return L("doc.coverage.identicalImageDisagreement")
    case "ocr_region_missing_or_numeric_ambiguity_withheld": return L("doc.coverage.numericAmbiguity")
    case "ocr_reading_order_changed_without_text_region_change": return L("doc.coverage.ocrOrder")
    case "ocr_disagrees_with_unlocalized_source_text": return L("doc.coverage.unlocalizedDisagreement")
    case "estimated_source_geometry_not_used_for_raster_pairing": return L("doc.coverage.estimatedGeometry")
    case "unlocalized_source_text_review_budget_exceeded": return L("doc.coverage.sourceBudget")
    case "revision_interval_render_appearance_not_comparable": return L("doc.coverage.incomparableRender")
    case "reference_pdf_changed_without_pptx_source_change": return L("doc.coverage.referenceChanged")
    case "pptx_source_changed_despite_identical_reference_pixels": return L("doc.coverage.sourceChanged")
    case "reference_appearance_unavailable_or_unverified_for_page": return L("doc.coverage.referenceUnavailable")
    case "provided_pdf_visual_difference_with_inferred_source_association": return L("doc.coverage.inferredReferenceDifference")
    case "pdf_source_run_layout_equivalent": return L("doc.coverage.sourceRunLayout")
    case "pdf_visual_difference_without_text_change": return L("doc.coverage.visualWithoutText")
    case "provided_pdf_association_inferred_not_powerpoint_equivalence": return L("doc.coverage.inferredReference")
    case "reference_pdf_reused_for_different_pptx": return L("doc.coverage.reusedReference")
    case "reference_rotation_requires_review": return L("doc.coverage.referenceRotation")
    case "reference_geometry_mismatch": return L("doc.coverage.referenceGeometry")
    case "manual_reference_not_powerpoint_equivalence": return L("doc.coverage.manualReference")
    case "manual_reference_text_unresolved_or_different": return L("doc.coverage.manualText")
    case "manual_reference_geometry_mismatch": return L("doc.coverage.manualGeometry")
    case "manual_reference_pdf_reused_for_different_pptx": return L("doc.coverage.manualReused")
    case "manual_reference_linked_hidden_source_slide": return L("doc.coverage.hiddenSlide")
    case "manual_reference_native_raster_unavailable": return L("doc.coverage.manualRaster")
    case "manual_reference_transform_unavailable": return L("doc.coverage.manualTransform")
    case "manual_reference_explicitly_unlinked": return L("doc.coverage.manualUnlink")
    case "manual_reference_displaced_by_another_source": return L("doc.coverage.manualDisplaced")
    case "native_raster_difference_is_not_semantic_deletion": return L("doc.coverage.noSemanticDeletion")
    case "render_difference_may_include_renderer_substitution": return L("doc.coverage.rendererSubstitution")
    case "failed_revision_no_comparison": return L("doc.coverage.failedRevision")
    case "raw_text_changed_in_suppressed_layer": return L("doc.coverage.suppressedTextChanged")
    default: return L("doc.coverage.unknownCode", .verbatim(value))
    }
}

struct CoverageGapEvidence:View {
    let gaps:[JSON]
    var body:some View {
        if !gaps.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Text(L("doc.coverage.heading")).font(.headline)
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
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing:0) {
            if !model.error.isEmpty { HStack { Image(systemName:"exclamationmark.triangle.fill");Text(model.error).textSelection(.enabled);Spacer();Button(L("doc.common.close")){model.error=""} }.padding(10).background(.red.opacity(0.1)) }
            if !model.documentRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.documentRecoveryWarning).textSelection(.enabled);Spacer();Button(L("doc.common.close")){model.documentRecoveryWarning=""}}.font(.caption).padding(10).background(.orange.opacity(0.1))}
            if !model.workbookRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.workbookRecoveryWarning);Spacer();Button(L("doc.common.close")){model.workbookRecoveryWarning=""}}.font(.caption).padding(10).background(.orange.opacity(0.1))}
            if !model.sidecarRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.sidecarRecoveryWarning);Spacer();Button(L("doc.recovery.temporaryFolder")){NSWorkspace.shared.open(model.bridge.library.appendingPathComponent("sidecars-v1"))};Button(L("doc.common.close")){model.sidecarRecoveryWarning=""}}.font(.caption).padding(10).background(.orange.opacity(0.1))}
            if model.busy { HStack { ProgressView().controlSize(.small);Text(model.status);Text("\(model.progress["current"].int)/\(max(1,model.progress["total"].int))").foregroundStyle(.secondary);Spacer();Button(model.committing ? L("doc.analysis.saving") : L("doc.analysis.cancel")){model.cancel()}.disabled(model.committing) }.padding(10).background(.blue.opacity(0.06)) }
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
            Divider();HStack { Label(L("doc.privacy.localMac"),systemImage:"internaldrive");Spacer();Text(!model.evidenceWarning.isEmpty ? model.evidenceWarning:model.status.isEmpty ? L("doc.evidence.footer") : model.status);Spacer();Text("Reviset · Native macOS") }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,14).padding(.vertical,5)
        }.disabled(!model.libraryAvailable || model.initializing).preferredColorScheme(.light).background(Color(nsColor:.windowBackgroundColor)).frame(minWidth:1100,minHeight:740)
        .toolbar {
            ToolbarItem(placement:.navigation){Button {model.focus.toggle()} label:{Image(systemName:model.focus ? "sidebar.left" : "arrow.up.left.and.arrow.down.right")}.help(model.focus ? L("doc.workspace.standard") : L("doc.workspace.focus"))}
            ToolbarItem { Text(model.project["title"].string.isEmpty ? "Reviset" : model.project["title"].string).font(.headline) }
            ToolbarItemGroup(placement:.primaryAction) {
                Button{openWindow(id:"workbooks")}label:{Label(L("doc.workspace.spreadsheets"),systemImage:"tablecells")}.help(L("doc.workspace.spreadsheetsHelp")).disabled(!model.libraryAvailable || model.initializing)
                if !model.report.isNull {
                    Picker(L("doc.workspace.task"),selection:$model.tab){Text(L("doc.workspace.compare")).tag("compare");Text(L("doc.workspace.history")).tag("history");Text(L("doc.workspace.export")).tag("export")}.pickerStyle(.segmented).frame(minWidth:265,idealWidth:320,maxWidth:360)
                    Button {Task{await model.exportReport()}} label:{Label(L("doc.common.export"),systemImage:"square.and.arrow.up")}
                }
            }
        }.onChange(of:model.tab){if model.tab != "export"{model.changeRange()}}
        .sheet(isPresented:$model.importSheet){ImportView()}
        .alert(item:$model.reorderConfirmation){request in Alert(title:Text(L("doc.reorder.title")),message:Text(request.message),primaryButton:.destructive(Text(L("doc.reorder.confirm"))){Task{await model.confirmReorder(request)}},secondaryButton:.cancel(Text(L("doc.common.cancel"))))}
        .sheet(item:$model.sidecarRequest){request in OnlyOfficeSidecarSheet(request:request).environmentObject(model)}
        .sheet(isPresented:$model.bundleSheet){BundleSheet(projectID:model.bundleProjectID,reportID:model.bundleReportID,occurrence:model.bundleOccurrence,initialSource:model.bundleSourceID).environmentObject(model)}
        .task {await model.start()}
    }
}
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack{Text(L("doc.project.heading")).font(.caption).foregroundStyle(.secondary);Spacer();Button{model.importSheet=true}label:{Image(systemName:"plus")}.buttonStyle(.borderless).disabled(model.busy || model.loading)}.padding(.horizontal,14).padding(.top,18)
            List(model.projects){p in Button{Task{await model.selectProject(p["project_id"].string)}}label:{HStack{Image(systemName:"folder.fill").foregroundStyle(.blue);VStack(alignment:.leading,spacing:3){Text(p["title"].string).lineLimit(1);Text(p["unreadable"].bool ? L("doc.project.unreadableBadge"):(p["dirty"].bool ? L("doc.project.revisionsPending", .verbatim(LC("doc.project.revisionCount",p["revisions"].array.count))) : LC("doc.project.revisionCount",p["revisions"].array.count))).font(.caption2).foregroundStyle(.secondary)}}.padding(.vertical,5)}.buttonStyle(.plain).disabled(model.busy||model.loading).help(p["unreadable"].bool ? L("doc.project.unreadableHelp"):p["title"].string).listRowBackground(p["project_id"].string==model.projectID ? Color.blue.opacity(0.12):Color.clear)}.listStyle(.sidebar).frame(minHeight:80,maxHeight:220)
            if !model.project.isNull {
                if model.project["unreadable"].bool {
                    Label(L("doc.project.readOnly"),systemImage:"lock.doc").font(.caption).padding(.horizontal,14)
                    Text(L("doc.project.unreadableDescription")).font(.caption2).foregroundStyle(.secondary).padding(.horizontal,14)
                }else{
                Text(L("doc.project.importOrder")).font(.caption).foregroundStyle(.secondary).padding(.horizontal,14)
                ScrollView { LazyVStack(spacing:0){ForEach(Array(model.project["revisions"].array.enumerated()),id:\.offset){i,r in HStack(spacing:8){Text(String(format:"%02d",i+1)).foregroundStyle(.secondary).font(.caption2);VStack(alignment:.leading,spacing:4){Text(r["label"].string).lineLimit(1).font(.caption);Text(r["files"].array.map{$0["blob"].string.hasSuffix("pdf") ? "PDF":"PPTX"}.joined(separator:" + ")).font(.caption2).foregroundStyle(.secondary)};Spacer();VStack(spacing:3){Button{Task{await model.reorder(i,delta:-1)}}label:{Image(systemName:"chevron.up")}.disabled(i==0||model.busy||model.loading||model.reorderConfirmation != nil);Button{Task{await model.reorder(i,delta:1)}}label:{Image(systemName:"chevron.down")}.disabled(i==model.project["revisions"].array.count-1||model.busy||model.loading||model.reorderConfirmation != nil)}.buttonStyle(.borderless).font(.caption2)}.padding(.horizontal,14).padding(.vertical,9);Divider()}} }
                Button(model.project["dirty"].bool ? L("doc.analysis.changedInputs"):L("doc.analysis.rerun")){Task{await model.run(model.projectID)}}.disabled(model.busy || model.loading || model.project["unreadable"].bool).frame(maxWidth:.infinity).padding(.horizontal,14)
                }
            }
            Spacer(minLength:5)
            Button{model.importSheet=true}label:{Label {Text(L("doc.import.documents")).lineLimit(2).fixedSize(horizontal:false,vertical:true)} icon:{Image(systemName:"plus")}}.disabled(model.busy || model.loading).frame(maxWidth:.infinity).padding(14)
        }.background(Color(nsColor:.underPageBackgroundColor))
    }
}
struct EmptyWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View { VStack(spacing:22){Image(systemName:"doc.on.doc").font(.system(size:62,weight:.light)).foregroundStyle(.blue);Text(L("doc.empty.headline")).font(.system(size:32,weight:.semibold)).multilineTextAlignment(.center);Text(L("doc.empty.description")).foregroundStyle(.secondary).multilineTextAlignment(.center);HStack{Button(L("doc.import.documents")){model.importSheet=true}.buttonStyle(.borderedProminent);Button(L("doc.empty.demo")){Task{await model.demo()}}}.disabled(model.busy || model.loading);Text(L("doc.empty.privacy")).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity) }
}
struct ReportBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {HStack{Label(L("doc.report.saved"),systemImage:"lock.doc").font(.caption);Picker(L("doc.report.label"),selection:Binding(get:{model.report["report_id"].string},set:{id in Task{await model.selectProject(model.projectID,snapshot:id)}})){ForEach(model.reports){r in Text(String(r["report_id"].string.dropFirst(4).prefix(12))+" · "+localizedISODate(r["created_at"].string)).tag(r["report_id"].string)}}.labelsHidden().frame(width:300).disabled(model.busy || model.loading);Spacer();if model.project["dirty"].bool{Text(L("doc.report.pending")).font(.caption).foregroundStyle(.orange)};Text(LC("doc.project.revisionCount", model.revisions.count)).font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,16).padding(.vertical,8)}
}
struct VersionBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Button{model.from=min(i,max(0,model.revisions.count-2));model.to=min(model.revisions.count-1,model.from+1);model.changeRange()}label:{VStack(spacing:5){Circle().fill(i==model.from||i==model.to ? Color.blue:Color.gray.opacity(0.3)).frame(width:11,height:11);Text(versionDisplayName(i,r)).font(.caption.weight(.semibold));Text(L("doc.revision.pagesAndFormats", .verbatim(LC("doc.revision.pageCount",model.primaryPages(r).count)), .verbatim(r["assets"].array.map{$0["format"].string.uppercased()}.joined(separator:"+")))).font(.caption2).foregroundStyle(.secondary);if r["status"].string != "success"{Text(L("doc.revision.partial")).font(.caption2).foregroundStyle(.orange)}}.frame(minWidth:135).padding(7)}.buttonStyle(.plain)}}.padding(.horizontal,15).padding(.vertical,9)}}
}
struct ComparePagesView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        HSplitView {
            if model.revisions.count<2 {PageColumn(revision:model.revision(0),side:L("doc.common.source"),pageID:$model.leftPageID)}
            else {
                if model.pageMode != "after" {PageColumn(revision:model.revision(model.from),side:L("doc.common.before"),pageID:$model.leftPageID)}
                if model.pageMode != "before" {PageColumn(revision:model.revision(model.to),side:L("doc.common.after"),pageID:$model.rightPageID)}
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
                Picker(L("doc.common.before"),selection:$model.from){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i<model.to{Text(versionDisplayName(i,r)).tag(i)}}}.frame(maxWidth:220)
                Image(systemName:"arrow.right").foregroundStyle(.secondary)
                Picker(L("doc.common.after"),selection:$model.to){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i>model.from{Text(versionDisplayName(i,r)).tag(i)}}}.frame(maxWidth:220)
                Text(model.to==model.from+1 ? L("doc.compare.adjacent"):L("doc.compare.range")).font(.caption).foregroundStyle(.secondary);Spacer()
                }else{Text(L("doc.compare.sourceRevision", .verbatim(versionDisplayName(0,model.revision(0))))).font(.headline);Spacer()}
                Button{model.inspector.toggle()}label:{Label(L("doc.compare.evidence"),systemImage:"sidebar.right")}
            }.padding(.horizontal,16).padding(.top,12).onChange(of:model.from){model.changeRange()}.onChange(of:model.to){model.changeRange()}
            HStack{
                if model.revisions.count>1 {Picker(L("doc.compare.documentView"),selection:$model.pageMode){Text(L("doc.compare.both")).tag("both");Text(L("doc.compare.beforeOnly")).tag("before");Text(L("doc.compare.afterOnly")).tag("after")}.pickerStyle(.segmented).frame(width:295)}
                Picker(L("doc.common.zoom"),selection:$model.zoom){Text(L("doc.common.fit")).tag(0.0);Text("100%").tag(1.0);Text("150%").tag(1.5);Text("200%").tag(2.0)}.frame(width:160)
                Spacer();Button(model.showChanges ? L("doc.changes.collapse"):L("doc.changes.expand")){model.showChanges.toggle()}
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
    var body: some View {VStack(spacing:5){HStack{Picker(L("doc.changes.kind"),selection:$model.kind){Text(L("doc.changes.all")).tag("all");ForEach(changeKinds,id:\.self){Text(changeKindName($0)).tag($0)}}.frame(width:180);TextField(L("doc.changes.search"),text:$model.search).textFieldStyle(.roundedBorder).frame(maxWidth:250);Spacer();if model.loadingChanges{ProgressView().controlSize(.small)};Text(LC("doc.changes.count", model.filteredChanges.count)).font(.caption).foregroundStyle(.secondary)}.padding(.horizontal,12).padding(.top,8)
        if model.filteredChanges.isEmpty {Text(model.emptyChangesMessage).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity).padding(12)}
        else {ScrollView { LazyVStack(spacing:1) { ForEach(model.filteredChanges) { c in Button {model.chooseChange(c["change_id"].string)} label: {ChangeRow(change:c).padding(.horizontal,10).padding(.vertical,4).contentShape(Rectangle())}.buttonStyle(.plain).disabled(model.loadingChanges || !model.changesFailure.isEmpty).background(model.selectedChangeID==c["change_id"].string ? Color.blue.opacity(0.12) : Color.clear) } }.padding(6) }}
    }}
}

struct ChangeRow: View {
    @EnvironmentObject var model:AppModel
    let change: JSON
    var kindName: String {changeDisplayName(change)}
    var text: String {(change["after"].isNull ? change["before"].string:change["after"].string).replacingOccurrences(of:"\n",with:" ")}
    var status: String {let value=change["lineage"]["status"].string;return value=="human_confirmed" ? L("doc.matching.humanConfirmed"):value=="needs_review" ? L("doc.matching.needsReview"):L("doc.matching.inferred")}
    var body: some View {HStack(spacing:10){Text(kindName).font(.caption).foregroundStyle(change["kind"].string=="coverage_gap" ? Color.secondary:Color.blue).lineLimit(2).fixedSize(horizontal:false,vertical:true).frame(width:155,alignment:.leading).help(kindName);VStack(alignment:.leading,spacing:3){Text(text).lineLimit(1).font(.caption);if model.tab=="history"{Text(changeVersionSummary(change,revisions:model.revisions)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)};Text(evidencePageSummary(change)).font(.caption2).foregroundStyle(.secondary)};Spacer();if change["region_pairing_assessment"].string == "inferred"{Text(L("doc.matching.regionInferred")).font(.caption2).foregroundStyle(.orange)};if change["text_assessment"].string == "inferred"{Text(L("doc.ocr.inferredReview")).font(.caption2).foregroundStyle(.orange)};if !change["appearance_assessment"].string.isEmpty{Text(change["appearance_assessment"].string=="observed" ? L("doc.appearance.observed"):L("doc.appearance.inferred")).font(.caption2).foregroundStyle(.orange)};Text(status).font(.caption2).foregroundStyle(.secondary)}.padding(.vertical,3)}
}

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    var mappingUnavailableReason: String? {
        if model.project["unreadable"].bool{return L("doc.project.readOnlyReason")}
        if model.busy { return L("doc.mapping.waitAnalysis") }
        if model.loading || model.loadingChanges { return L("doc.changes.loading") }
        if model.project["dirty"].bool { return L("doc.mapping.analyzePending") }
        if model.project["last_report_id"].string != model.report["report_id"].string { return L("doc.mapping.chooseLatest") }
        if model.revisions.count<2 {return L("doc.mapping.needRevisions")}
        if model.to != model.from+1 { return L("doc.mapping.chooseAdjacent") }
        if !model.primaryPages(model.revision(model.from)).contains(where:{$0["page_id"].string==model.leftPageID}) || !model.primaryPages(model.revision(model.to)).contains(where:{$0["page_id"].string==model.rightPageID}) { return L("doc.mapping.selectBoth") }
        return nil
    }
    var editable: Bool { mappingUnavailableReason == nil }
    var structural: Bool { !model.selected["topology"].isNull }
    var neutralText:Bool {structural || ["coverage_gap","text_occluded","text_struck_through","text_revealed"].contains(model.selected["kind"].string) || isReferenceAppearanceChange(model.selected) || (model.selected["kind"].string == "visual_region_changed" && model.selected["coverage_gaps"].array.contains(where:{$0["reason"].string == "pdf_visual_difference_without_text_change"}))}
    func sourceText(_ value:JSON,other:JSON,before:Bool)->Text {
        if value.isNull{return Text(L("doc.inspector.noSource")).foregroundColor(.secondary)}
        if neutralText{return Text(value.string).foregroundColor(.primary)}
        return changeTextRuns(value.string,comparedWith:other.isNull ? "":other.string).reduce(Text("")){text,run in
            text+Text(run.text).foregroundColor(run.changed ? (before ? .red:.green):.primary).underline(run.changed)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                Text(L("doc.inspector.selectedChange")).font(.caption).foregroundStyle(.secondary)
                Text(model.selected.isNull && model.filteredChanges.isEmpty ? model.emptyChangesMessage:changeDisplayName(model.selected)).font(.title3.weight(.semibold))
                if !model.selected.isNull {
                    Text(structural ? L("doc.inspector.beforeStructure") : L("doc.inspector.beforeText")).font(.caption).foregroundStyle(.secondary)
                    sourceText(model.selected["before"],other:model.selected["after"],before:true).textSelection(.enabled)
                    Text(structural ? L("doc.inspector.afterStructure") : L("doc.inspector.afterText")).font(.caption).foregroundStyle(.secondary)
                    sourceText(model.selected["after"],other:model.selected["before"],before:false).textSelection(.enabled)
                    if !neutralText {Text(L("doc.inspector.highlightHelp")).font(.caption2).foregroundStyle(.secondary)}
                    if structural { Text(L("doc.inspector.lineageHelp")).font(.caption).foregroundStyle(.secondary) }
                    Divider();Text(L("doc.inspector.sourceEvidence")).font(.headline)
                    ForEach(Array(model.selected["evidence"].array.enumerated()),id:\.offset) { _,e in
                        VStack(alignment:.leading,spacing:6) {
                            Button { model.navigateEvidence(e) } label: { Label(evidenceVersionLabel(e,change:model.selected,revisions:model.revisions)+" · "+evidenceMethodName(e["method"].string,provenance:e["provenance"].string),systemImage:"doc.text.magnifyingglass").font(.caption) }.buttonStyle(.plain)
                            Text(e["quote"].string).font(.caption).textSelection(.enabled)
                        }.padding(9).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
                    }
                    if !model.selected["appearance_assessment"].string.isEmpty { Text(model.selected["appearance_assessment"].string == "observed" ? L("doc.appearance.stateObserved") : L("doc.appearance.stateInferred")).font(.caption).foregroundStyle(.orange) }
                    Text(lineageReasonText(model.selected["lineage"]["reasons"].array,humanConfirmed:model.selected["lineage"]["status"].string == "human_confirmed" && model.selected["topology"]["semantics"].string != "directed_reachability")).font(.caption2).foregroundStyle(.secondary)
                    CoverageGapEvidence(gaps:model.selected["coverage_gaps"].array)
                }
                Divider();Text(L("doc.mapping.reviewHeading")).font(.headline)
                Text(L("doc.mapping.reviewDescription")).font(.caption).foregroundStyle(.secondary)
                Button(L("doc.mapping.edit")) { model.mappingSheet=true }.disabled(!editable).accessibilityHint(Text(mappingUnavailableReason ?? L("doc.mapping.editHint")))
                if let message=mappingUnavailableReason { Text(message).font(.caption).foregroundStyle(.secondary) }
                Divider();Label(L("doc.limitations.heading"),systemImage:"exclamationmark.triangle").font(.headline)
                Text(L("doc.limitations.appearance")).font(.caption)
                Text(L("doc.limitations.ocr")).font(.caption).foregroundStyle(.secondary)
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
    struct PageIndex {
        struct Entry {
            let revisionIndex:Int
            let order:Int
            let page:JSON
        }
        struct LineagePages {
            let first:JSON
            let pagesByRevision:[Int:[JSON]]
        }
        private var pagesByID:[String:[Entry]]=[:]
        init(revisions:[JSON],primaryPages:(JSON)->[JSON]) {
            var order=0
            for (revisionIndex,revision) in revisions.enumerated() {
                for page in primaryPages(revision) {
                    pagesByID[page["page_id"].string,default:[]].append(Entry(revisionIndex:revisionIndex,order:order,page:page))
                    order += 1
                }
            }
        }
        func lineage(_ lineage:JSON)->LineagePages? {
            // Preserve source order even when lineage IDs are reversed or repeated.
            let members=Set(lineage["page_ids"].array.map(\.string)).flatMap { pagesByID[$0] ?? [] }.sorted { $0.order<$1.order }
            guard let first=members.first else { return nil }
            return LineagePages(first:first.page,pagesByRevision:Dictionary(grouping:members,by:\.revisionIndex).mapValues { $0.map(\.page) })
        }
    }
    @EnvironmentObject var model:AppModel
    var body:some View {
        let revisions=model.revisions
        let pageIndex=PageIndex(revisions:revisions,primaryPages:model.primaryPages)
        VStack(alignment:.leading,spacing:14){HStack{VStack(alignment:.leading){Text(L("doc.history.heading")).font(.title2.weight(.semibold));Text(L("doc.history.description")).font(.caption).foregroundStyle(.secondary);Text(L("doc.history.absenceHelp")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)};Spacer()}.padding(.horizontal,18).padding(.top,20)
        ScrollView([.vertical,.horizontal]){LazyVStack(alignment:.leading,spacing:1){HStack{Text(L("doc.history.lineage")).frame(width:180,alignment:.leading);ForEach(Array(revisions.enumerated()),id:\.offset){i,r in Text(versionDisplayName(i,r)).frame(width:130)}}.font(.caption.weight(.semibold)).padding(9)
            ForEach(model.report["lineages"].array){lineage in
                if let pages=pageIndex.lineage(lineage){
                    HStack(alignment:.top) {
                        Text(pages.first["text"].string.components(separatedBy:"\n").first ?? L("doc.common.page")).font(.caption).lineLimit(1).frame(width:180,alignment:.leading)
                        ForEach(Array(revisions.enumerated()),id:\.offset) { i,r in
                            let members=pages.pagesByRevision[i] ?? []
                            VStack(spacing:4) {
                                if members.isEmpty { Text("—").font(.caption).foregroundStyle(.secondary).padding(.vertical,7) }
                                ForEach(members) { page in
                                    Button { model.openHistoryPage(i,page["page_id"].string) } label: { Text("p.\(page["page"].int)").font(.caption).frame(width:115).padding(.vertical,7).background(Color.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).accessibilityLabel(L("doc.history.openPage", .verbatim(r["label"].string), .integer(page["page"].int)))
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
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:22){Text(L("doc.export.heading")).font(.largeTitle.weight(.semibold));Text(L("doc.export.description")).foregroundStyle(.secondary)
        GroupBox(L("doc.export.filesHeading")){VStack(alignment:.leading,spacing:12){Text(L("doc.export.filesDescription"));Button(L("doc.export.files")){Task{await model.exportReport()}}.buttonStyle(.borderedProminent)}.padding(12).frame(maxWidth:.infinity,alignment:.leading)}
        GroupBox(L("doc.export.mcpHeading")){VStack(alignment:.leading,spacing:12){Text(L("doc.export.mcpDescription")).font(.caption).foregroundStyle(.secondary);Text(model.currentMCPConfig ?? (model.mcpFailure.isEmpty ? L("doc.export.mcpLoading"):L("doc.export.mcpFailure", .verbatim(model.mcpFailure)))).font(.system(.caption,design:.monospaced)).textSelection(.enabled).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.textBackgroundColor));Button(L("doc.export.copyConfig")){guard let config=model.currentMCPConfig else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(config,forType:.string);model.statusMessage=UIMessage("doc.export.configCopied")}.disabled(model.currentMCPConfig == nil);if !model.mcpFailure.isEmpty {Button(L("doc.export.reloadConfig")){Task{await model.loadMCP()}}}}.padding(12)}
        GroupBox(L("doc.export.limitsHeading")){Text(L("doc.export.limitsDescription")).font(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading)}
    }.padding(35).frame(maxWidth:1000,alignment:.leading)}.task(id:model.projectID){await model.loadMCP()}}
}
struct ImportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var title=""
    @State private var titleEdited=false
    private var effectiveTitle:String { titleEdited ? title : L("doc.import.defaultTitle") }
    private var titleBinding:Binding<String> { Binding(get:{effectiveTitle},set:{title=$0;titleEdited=true}) }
    @State private var rows:[ImportRow]=[]
    @State private var saving=false
    @State private var choosing=false
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    init(initialRows:[ImportRow]=[],initialTitle:String?=nil){_rows=State(initialValue:initialRows);_title=State(initialValue:initialTitle ?? "");_titleEdited=State(initialValue:initialTitle != nil)}
    var locked:Bool{saving || choosing}
    var body: some View {
        VStack(alignment:.leading,spacing:17){
            HStack{Text(L("doc.import.documents")).font(.title2.weight(.semibold));Spacer();Button(L("doc.common.close")){dismiss()}.keyboardShortcut(.cancelAction).disabled(locked)}
            Text(L("doc.import.description")).font(.callout).foregroundStyle(.secondary)
            TextField(L("doc.import.projectName"),text:titleBinding).textFieldStyle(.roundedBorder).disabled(locked).accessibilityIdentifier("Reviset.import.projectTitle")
            Button{choose()}label:{Label(L("doc.import.chooseFiles"),systemImage:"plus")}.disabled(locked)
            List{
                ForEach(Array(rows.enumerated()),id:\.element.id){i,r in
                    HStack{
                        Text("\(i+1)").foregroundStyle(.secondary)
                        VStack(alignment:.leading){
                            TextField(L("doc.import.revisionName"),text:Binding(get:{rows.indices.contains(i) ? rows[i].label:""},set:{if rows.indices.contains(i){rows[i].label=$0}})).disabled(locked)
                            Text(r.urls.map(\.lastPathComponent).joined(separator:" + ")).font(.caption2).foregroundStyle(.secondary)
                            if r.members.count==2{Label(L("doc.import.bundleBadge"),systemImage:"link").font(.caption).foregroundStyle(.secondary)}
                        }
                        Button{ImportRow.move(&rows,at:i,by:-1)}label:{Image(systemName:"chevron.up")}.disabled(i==0 || locked).accessibilityLabel(L("doc.import.moveUp"))
                        Button{ImportRow.move(&rows,at:i,by:1)}label:{Image(systemName:"chevron.down")}.disabled(i==rows.count-1 || locked).accessibilityLabel(L("doc.import.moveDown"))
                        if r.members.count==2{
                            Button(L("doc.import.ungroup")){ImportRow.ungroup(&rows,at:i)}.disabled(locked).help(L("doc.import.ungroupHelp"))
                        }else{
                            Button(L("doc.import.group")){ImportRow.group(&rows,at:i)}.disabled(locked || ImportRow.groupingUnavailable(rows,at:i) != nil).help(ImportRow.groupingUnavailable(rows,at:i) ?? L("doc.import.groupHelp"))
                        }
                        Button{if rows.indices.contains(i){rows.remove(at:i)}}label:{Image(systemName:"xmark")}.disabled(locked).accessibilityLabel(L("doc.import.remove"))
                    }
                }
            }.frame(minHeight:230,maxHeight:360)
            if !failure.isEmpty{Text(failure).foregroundStyle(.red).font(.caption)}
            HStack{
                Text(L("doc.import.integrityHelp")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if locked{ProgressView().controlSize(.small);Text(choosing ? L("doc.import.checking"):L("doc.import.saving")).font(.caption)}
                Button(L("doc.import.analyze")){Task{await create()}}.buttonStyle(.borderedProminent).disabled(locked || rows.isEmpty || effectiveTitle.trimmingCharacters(in:.whitespaces).isEmpty || rows.contains{$0.label.trimmingCharacters(in:.whitespaces).isEmpty})
            }
        }.padding(25).frame(width:900)
    }
    func choose(){
        let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.allowedContentTypes=[.pdf,UTType(filenameExtension:"pptx") ?? .data];panel.canChooseDirectories=false
        if panel.runModal() == .OK{
            let urls=panel.urls;choosing=true;failure=""
            Task{
                do{let selected=try await Task.detached(priority:.userInitiated){try urls.map{try ImportRow.selected($0)}}.value;rows += selected}
                catch{failureMessage=bridgeErrorMessage(error)}
                choosing=false
            }
        }
    }
    func create() async {saving=true;do{let p=try await model.create(title:effectiveTitle,rows:rows);model.report=JSON();try await model.refresh();model.projectID=p["project_id"].string;dismiss();await model.run(model.projectID)}catch{failureMessage=bridgeErrorMessage(error)};saving=false}
}
