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
func documentReportTimestamp(_ report:JSON,reports:[JSON])->String {
    if !report["created_at"].string.isEmpty {return report["created_at"].string}
    return reports.first{$0["report_id"].string==report["report_id"].string}?["created_at"].string ?? ""
}
func documentGapScope(_ gap:JSON)->String {
    [gap["revision_occurrence_id"].string.isEmpty ? gap["revision_id"].string:gap["revision_occurrence_id"].string,gap["page_id"].string].filter{!$0.isEmpty}.joined(separator:" · ")
}
@MainActor func selectedCoverageCaption(_ gap:JSON)->String {
    [gap["feature"].string,coverageReasonName(gap["reason"].string)].filter{!$0.isEmpty}.joined(separator:" · ")
}
func documentChangeExcerpt(_ change:JSON)->String {
    // A bounded navigation excerpt; canonical change/source strings stay exact.
    func excerpt(_ value:String)->String {let compact=value.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ");return String(compact.prefix(100))+(compact.count>100 ? "…":"")}
    if change["before"].isNull {return excerpt(change["after"].string)}
    if change["after"].isNull {return excerpt(change["before"].string)}
    return excerpt(change["before"].string)+" → "+excerpt(change["after"].string)
}

struct CoverageGapEvidence:View {
    let gaps:[JSON]
    var body:some View {
        if !gaps.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Text(L("doc.coverage.heading")).readableFont(.headline)
                ForEach(Array(gaps.enumerated()),id:\.offset){_,gap in
                    Label(coverageReasonName(gap["reason"].string),systemImage:"exclamationmark.circle")
                        .readableFont(.caption).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
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
    @EnvironmentObject private var layout:WorkspaceLayoutStore
    var body: some View {
        VStack(spacing:0) {
            if !model.error.isEmpty { HStack { Image(systemName:"exclamationmark.triangle.fill");Text(model.error).textSelection(.enabled);Spacer();Button(L("doc.common.close")){model.error=""} }.padding(10).background(.red.opacity(0.1)) }
            if !model.documentRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.documentRecoveryWarning).textSelection(.enabled);Spacer();Button(L("doc.common.close")){model.documentRecoveryWarning=""}}.readableFont(.caption).padding(10).background(.orange.opacity(0.1))}
            if !model.workbookRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.workbookRecoveryWarning);Spacer();Button(L("doc.common.close")){model.workbookRecoveryWarning=""}}.readableFont(.caption).padding(10).background(.orange.opacity(0.1))}
            if !model.sidecarRecoveryWarning.isEmpty {HStack {Image(systemName:"info.circle");Text(model.sidecarRecoveryWarning);Spacer();Button(L("doc.recovery.temporaryFolder")){NSWorkspace.shared.open(model.bridge.library.appendingPathComponent("sidecars-v1"))};Button(L("doc.common.close")){model.sidecarRecoveryWarning=""}}.readableFont(.caption).padding(10).background(.orange.opacity(0.1))}
            if model.busy { HStack { ProgressView().controlSize(.small);Text(model.status);Text("\(model.progress["current"].int)/\(max(1,model.progress["total"].int))").foregroundStyle(.secondary);Spacer();Button(model.committing ? L("doc.analysis.saving") : L("doc.analysis.cancel")){model.cancel()}.disabled(model.committing) }.padding(10).background(.blue.opacity(0.06)) }
            WorkspacePaneSplit(name:"document.projects",auxiliaryFirst:true,auxiliaryVisible:layout.configuration.sidebarVisible,extent:.points(layout.configuration.sidebarWidth),primaryMinimum:760,auxiliaryMinimum:180,onResize:{value in if case .points(let width)=value {layout.update{$0.sidebarWidth=min(380,max(180,width))}}}) {
                VStack(spacing:0) {
                    if model.report.isNull { EmptyWorkspace() }
                    else {
                        WorkspaceReadingGuide(expanded:$layout.readingGuideExpanded).environmentObject(model).environmentObject(layout)
                        ReportBar().background(WorkspaceLayoutMarker(name:"Reviset.document.reportBar"));Divider()
                        CompareWorkspace()
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity).environmentObject(model).environmentObject(layout)
            } auxiliary:{SidebarView().environmentObject(model)}
            Divider();HStack { Label(L("doc.privacy.localMac"),systemImage:"internaldrive");Spacer();Text(!model.evidenceWarning.isEmpty ? model.evidenceWarning:model.status.isEmpty ? L("doc.evidence.footer") : model.status);Spacer();Text("Reviset · Native macOS") }.readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,14).padding(.vertical,5)
        }.disabled(!model.libraryAvailable || model.initializing).preferredColorScheme(.light).background(Color(nsColor:.windowBackgroundColor)).frame(minWidth:1100,minHeight:740)
        .toolbar {
            ToolbarItem(placement:.navigation){Button {layout.toggleFocus()} label:{Image(systemName:layout.isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")}.help(layout.isFocused ? L("doc.workspace.standard") : L("doc.workspace.focus")).accessibilityLabel(layout.isFocused ? L("doc.workspace.standard") : L("doc.workspace.focus"))}
            ToolbarItem { WorkspaceLayoutMenu(layout:layout) }
            ToolbarItem { ReadabilityMenu() }
            ToolbarItem { if !model.report.isNull {Button {layout.readingGuideExpanded.toggle()} label:{Label(L("git.guide.open"),systemImage:"questionmark.circle")}.labelStyle(.titleAndIcon).help(L("git.guide.title"))} }
            ToolbarItem { Menu {ForEach(model.projects){project in Button(project["title"].string){Task{await model.selectProject(project["project_id"].string)}}};Divider();Button(L("git.manageVersions")){layout.update{$0.sidebarVisible=true}}} label:{Label(model.project["title"].string.isEmpty ? "Reviset":model.project["title"].string,systemImage:"folder").background(WorkspaceLayoutMarker(name:"Reviset.document.toolbar.projects"))}.disabled(model.busy || model.loading || !model.libraryAvailable || model.initializing) }
            ToolbarItemGroup(placement:.primaryAction) {
                Button{model.importSheet=true}label:{Label(L("doc.import.documents"),systemImage:"plus").background(WorkspaceLayoutMarker(name:"Reviset.document.toolbar.import"))}.labelStyle(.titleAndIcon).disabled(model.busy || model.loading || !model.libraryAvailable || model.initializing)
                Menu {
                    Button(L("doc.workspace.spreadsheets")){openWindow(id:"workbooks")}
                    if !model.report.isNull {
                        Button(L("doc.common.export")){Task{await model.exportReport()}}
                        Button(L("git.aiTools")){model.toolsSheet=true}
                        Divider()
                        Button(L("git.lineage")){model.lineageSheet=true}
                        Button(L("doc.mapping.reviewHeading")){model.inspector=true}
                    }
                } label:{Label(L("git.actions"),systemImage:"ellipsis.circle").background(WorkspaceLayoutMarker(name:"Reviset.document.toolbar.actions"))}.disabled(!model.libraryAvailable || model.initializing)
            }
        }.focusedSceneObject(layout)
        .onChange(of:model.focus){if model.focus != layout.isFocused {layout.setFocus(model.focus)}}
        .onChange(of:model.inspector){layout.update{$0.inspectorVisible=model.inspector}}
        .onChange(of:model.showChanges){layout.update{$0.changesVisible=model.showChanges}}
        .onChange(of:layout.configuration){syncLayoutFlags()}
        .onChange(of:layout.isFocused){syncLayoutFlags()}
        .onChange(of:model.tab){if model.tab == "export" {model.toolsSheet=true} else {model.changeRange()}}
        .sheet(isPresented:$model.toolsSheet){NativeDetailSheet(title:L("git.aiTools")){ExportView().environmentObject(model)}}
        .sheet(isPresented:$model.lineageSheet){NativeDetailSheet(title:L("git.lineage")){VStack(spacing:0){VersionBar().environmentObject(model);HistoryGraphView().environmentObject(model)}}}
        .sheet(isPresented:$model.importSheet){ImportView(intent:model.importIntent)}
        .alert(item:$model.reorderConfirmation){request in Alert(title:Text(L("doc.reorder.title")),message:Text(request.message),primaryButton:.destructive(Text(L("doc.reorder.confirm"))){Task{await model.confirmReorder(request)}},secondaryButton:.cancel(Text(L("doc.common.cancel"))))}
        .sheet(item:$model.sidecarRequest){request in OnlyOfficeSidecarSheet(request:request).environmentObject(model)}
        .sheet(isPresented:$model.bundleSheet){BundleSheet(projectID:model.bundleProjectID,reportID:model.bundleReportID,occurrence:model.bundleOccurrence,initialSource:model.bundleSourceID).environmentObject(model)}
        .task {syncLayoutFlags();await model.start()}
    }
    private func syncLayoutFlags() {
        model.focus=layout.isFocused;model.inspector=layout.configuration.inspectorVisible;model.showChanges=layout.configuration.changesVisible
    }
}
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack{Text(L("doc.project.heading")).readableFont(.caption).foregroundStyle(.secondary);Spacer();Button{model.importSheet=true}label:{Image(systemName:"plus").background(WorkspaceLayoutMarker(name:"Reviset.document.import.environment.plus"))}.buttonStyle(.borderless).disabled(model.busy || model.loading).accessibilityIdentifier("Reviset.document.import.plus")}.padding(.horizontal,14).padding(.top,18)
            List(model.projects){p in Button{Task{await model.selectProject(p["project_id"].string)}}label:{HStack{Image(systemName:"folder.fill").foregroundStyle(.blue);VStack(alignment:.leading,spacing:3){Text(p["title"].string).lineLimit(1);Text(p["unreadable"].bool ? L("doc.project.unreadableBadge"):(p["dirty"].bool ? L("doc.project.revisionsPending", .verbatim(LC("doc.project.revisionCount",p["revisions"].array.count))) : LC("doc.project.revisionCount",p["revisions"].array.count))).readableFont(.caption2).foregroundStyle(.secondary)}}.padding(.vertical,5)}.buttonStyle(.plain).disabled(model.busy||model.loading).help(p["unreadable"].bool ? L("doc.project.unreadableHelp"):p["title"].string).listRowBackground(p["project_id"].string==model.projectID ? Color.blue.opacity(0.12):Color.clear)}.listStyle(.sidebar).frame(minHeight:80,maxHeight:220)
            if !model.project.isNull {
                if model.project["unreadable"].bool {
                    Label(L("doc.project.readOnly"),systemImage:"lock.doc").readableFont(.caption).padding(.horizontal,14)
                    Text(L("doc.project.unreadableDescription")).readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,14)
                }else{
                Text(L("doc.project.importOrder")).readableFont(.caption).foregroundStyle(.secondary).padding(.horizontal,14)
                ScrollView { LazyVStack(spacing:0){ForEach(Array(model.project["revisions"].array.enumerated()),id:\.offset){i,r in HStack(spacing:8){Text(String(format:"%02d",i+1)).foregroundStyle(.secondary).readableFont(.caption2);VStack(alignment:.leading,spacing:4){Text(r["label"].string).lineLimit(1).readableFont(.caption);Text(r["files"].array.map{$0["blob"].string.hasSuffix("pdf") ? "PDF":"PPTX"}.joined(separator:" + ")).readableFont(.caption2).foregroundStyle(.secondary)};Spacer();VStack(spacing:3){Button{Task{await model.reorder(i,delta:-1)}}label:{Image(systemName:"chevron.up")}.disabled(i==0||model.busy||model.loading||model.reorderConfirmation != nil);Button{Task{await model.reorder(i,delta:1)}}label:{Image(systemName:"chevron.down")}.disabled(i==model.project["revisions"].array.count-1||model.busy||model.loading||model.reorderConfirmation != nil)}.buttonStyle(.borderless).readableFont(.caption2)}.padding(.horizontal,14).padding(.vertical,9);Divider()}} }
                Button(model.project["dirty"].bool ? L("doc.analysis.changedInputs"):L("doc.analysis.rerun")){Task{await model.run(model.projectID)}}.disabled(model.busy || model.loading || model.project["unreadable"].bool).frame(maxWidth:.infinity).padding(.horizontal,14)
                }
            }
            Spacer(minLength:5)
            Button{model.importSheet=true}label:{Label {Text(L("doc.import.documents")).lineLimit(2).fixedSize(horizontal:false,vertical:true)} icon:{Image(systemName:"plus")}.background(WorkspaceLayoutMarker(name:"Reviset.document.import.environment.sidebar"))}.disabled(model.busy || model.loading).accessibilityIdentifier("Reviset.document.import.sidebar").frame(maxWidth:.infinity).padding(14)
        }.background(Color(nsColor:.underPageBackgroundColor)).background(WorkspaceLayoutMarker(name:"Reviset.document.sidebar"))
    }
}
struct EmptyWorkspace: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Label(L("git.empty.title"),systemImage:"doc.on.doc").readableFont(.title2,weight:.semibold)
                Text(L("git.empty.subtitle")).readableFont(.body).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                VStack(alignment:.leading,spacing:20) {
                    ReadingGuideStep(number:1,title:L("git.guide.import.title"),detail:L("git.guide.import.detail"))
                    ReadingGuideStep(number:2,title:L("git.guide.compare.title"),detail:L("git.guide.compare.detail"))
                    ReadingGuideStep(number:3,title:L("git.guide.inspect.title"),detail:L("git.guide.inspect.detail"))
                }
                HStack(spacing:14) {
                    ReadableActionButton(L("doc.import.documents"),prominent:true,identifier:"Reviset.document.empty.import"){model.importSheet=true}
                    ReadableActionButton(L("git.empty.workbooks"),identifier:"Reviset.document.empty.workbooks"){openWindow(id:"workbooks")}
                }.disabled(model.busy || model.loading)
                if model.projects.isEmpty {Button(L("doc.empty.demo")){Task{await model.demo()}}.buttonStyle(.link).disabled(model.busy || model.loading)}
                Text(L("doc.empty.privacy")).readableFont(.caption).foregroundStyle(.secondary)
            }.padding(36).frame(maxWidth:800,alignment:.leading).frame(maxWidth:.infinity,alignment:.center)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).readableInterface()
    }
}

private struct ReadingGuideStep:View {
    let number:Int
    let title:String
    let detail:String
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            Text(String(number)).readableFont(.body,weight:.semibold).foregroundStyle(.blue)
                .frame(width:30,height:30).background(Color.blue.opacity(0.09)).clipShape(Circle())
            VStack(alignment:.leading,spacing:5) {
                Text(title).readableFont(.body,weight:.semibold)
                Text(detail).readableFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

private struct WorkspaceReadingGuide:View {
    @EnvironmentObject var model:AppModel
    @EnvironmentObject var layout:WorkspaceLayoutStore
    @Binding var expanded:Bool
    var body:some View {
        Button{expanded.toggle()} label:{
            HStack(spacing:14) {
                Label(L("git.guide.title"),systemImage:"lightbulb").readableFont(.callout,weight:.semibold)
                Text(L("git.guide.summary")).readableFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength:8)
                Image(systemName:"questionmark.circle").foregroundStyle(.secondary)
            }
            .frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain).help(L("git.guide.open")).accessibilityIdentifier("Reviset.document.readingGuide.open")
            .readableFont(.callout).padding(.horizontal,18).padding(.vertical,6)
            .background(Color.blue.opacity(0.035)).background(WorkspaceLayoutMarker(name:"Reviset.document.readingGuide"))
            .popover(isPresented:$expanded,arrowEdge:.bottom) {
                VStack(spacing:0) {
                    HStack(spacing:16) {
                        Label(L("git.guide.title"),systemImage:"lightbulb").readableFont(.headline)
                        Spacer()
                        ReadableActionButton(L("doc.common.close"),identifier:"Reviset.document.readingGuide.close",isCancel:true){expanded=false}
                    }.padding(20)
                    Divider()
                    ScrollView {
                        VStack(alignment:.leading,spacing:24) {
                            ReadingGuideStep(number:1,title:L("git.guide.import.title"),detail:L("git.guide.import.short"))
                            ReadingGuideStep(number:2,title:L(model.revisions.count==1 ? "git.reading":"git.guide.compare.title"),detail:L(model.revisions.count==1 ? "git.guide.singleRead":"git.guide.compare.short"))
                            ReadingGuideStep(number:3,title:L(model.revisions.count==1 ? "git.guide.compare.title":"git.guide.inspect.title"),detail:L(model.revisions.count==1 ? "git.guide.singleCompare":"git.guide.inspect.short"))
                            if !layout.configuration.changesVisible {
                                ReadableActionButton(L("git.guide.showChanges"),identifier:"Reviset.document.readingGuide.showChanges"){layout.update{$0.changesVisible=true};expanded=false}
                            }
                        }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.frame(width:620,height:400).readableInterface()
                    .background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light)
                    .background(WorkspaceLayoutMarker(name:"Reviset.document.readingGuide.popover"))
            }
    }
}
struct ReportBar: View {
    @EnvironmentObject var model: AppModel
    @State private var details=false
    var body: some View {
        HStack(spacing:10){
            NativeWorkspaceIdentity(name:"Reviset.document.projectTitle",title:workspaceIdentityTitle(projectTitle:model.project["title"].string,reportTitle:model.report["title"].string,fallback:L("doc.project.heading")),reportID:model.report["report_id"].string).frame(minWidth:140,maxWidth:.infinity,alignment:.leading)
            Menu {
                ForEach(model.reports){r in Button(localizedISODate(r["created_at"].string)+" · "+String(r["report_id"].string.suffix(12))){Task{await model.selectProject(model.projectID,snapshot:r["report_id"].string)}}}
                Divider();Button(L("git.reportDetails")){details=true}
            } label:{Image(systemName:"lock.doc")}.accessibilityLabel(L("git.reportChip",.verbatim(String(model.report["report_id"].string.suffix(12))))).help(L("doc.report.saved")+"\n"+model.report["report_id"].string).disabled(model.busy || model.loading)
            Text(LC("doc.project.revisionCount",model.revisions.count)).readableFont(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.project["dirty"].bool {Label(L("doc.report.pending"),systemImage:"exclamationmark.circle").readableFont(.caption).foregroundStyle(.orange)}
        }.controlSize(.small).padding(.horizontal,14).padding(.vertical,5)
        .sheet(isPresented:$details){NativeDetailSheet(title:L("git.reportDetails")){DocumentReportDetailsView().environmentObject(model)}}
    }
}
struct DocumentReportDetailsView:View {
    @EnvironmentObject var model:AppModel
    private func qualityLabel(_ count:DocumentReportQualityCount)->String {
        switch count.key {
        case "ocr_inferred_pages":return L("git.quality.ocr_inferred_pages",.count(count.count))
        case "ocr_failed_pages":return L("git.quality.ocr_failed_pages",.count(count.count))
        case "unresolved_comparison_pages":return L("git.quality.unresolved_comparison_pages",.count(count.count))
        case "reference_pdf_pages":return L("git.quality.reference_pdf_pages",.count(count.count))
        case "human_reference_pdf_pages":return L("git.quality.human_reference_pdf_pages",.count(count.count))
        case "inferred_reference_pdf_pages":return L("git.quality.inferred_reference_pdf_pages",.count(count.count))
        case "pptx_without_render":return L("git.quality.pptx_without_render",.count(count.count))
        default:return ""
        }
    }
    var body:some View {
        let details=documentReportDetails(model.report)
        ScrollView{LazyVStack(alignment:.leading,spacing:14){
            Text(model.report["report_id"].string).readableFont(.body,design:.monospaced).textSelection(.enabled)
            if !documentReportTimestamp(model.report,reports:model.reports).isEmpty {Text(localizedISODate(documentReportTimestamp(model.report,reports:model.reports))).readableFont(.caption).foregroundStyle(.secondary)}
            Text(L("git.reportQuality")).readableFont(.headline)
            ForEach(details.quality,id:\.key){count in Text(qualityLabel(count)).readableFont(.callout)}
            Text(L("git.reportGapCount",.count(details.totalCoverageGaps))).readableFont(.headline)
            if details.gaps.isEmpty {Text(L("git.reportGapsEmpty")).readableFont(.caption).foregroundStyle(.secondary)}
            ForEach(Array(details.gaps.enumerated()),id:\.offset){_,gap in VStack(alignment:.leading,spacing:3){Text(coverageReasonName(gap["reason"].string)).readableFont(.callout);if !gap["feature"].string.isEmpty {Text(verbatim:gap["feature"].string).readableFont(.caption).foregroundStyle(.secondary)};if !documentGapScope(gap).isEmpty {Text(verbatim:documentGapScope(gap)).readableFont(.caption,design:.monospaced).textSelection(.enabled)}}}
            if details.coverageTruncated {Text(L("git.reportGapProjection",.count(details.gaps.count),.count(details.totalCoverageGaps))).readableFont(.caption).foregroundStyle(.secondary)}
            Divider();Text(L("doc.limitations.appearance"));Text(L("doc.limitations.ocr"))
            Button(L("git.exportCompleteReport")){Task{await model.exportReport()}}
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading)}
    }
}
struct VersionBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in Button{model.selectVersion(i)}label:{VStack(spacing:5){Circle().fill(i==model.from||i==model.to ? Color.blue:Color.gray.opacity(0.3)).frame(width:11,height:11);Text(versionDisplayName(i,r)).readableFont(.caption,weight:.semibold);Text(L("doc.revision.pagesAndFormats", .verbatim(LC("doc.revision.pageCount",model.primaryPages(r).count)), .verbatim(r["assets"].array.map{$0["format"].string.uppercased()}.joined(separator:"+")))).readableFont(.caption2).foregroundStyle(.secondary);if r["status"].string != "success"{Text(L("doc.revision.partial")).readableFont(.caption2).foregroundStyle(.orange)}}.frame(minWidth:135).padding(7)}.buttonStyle(.plain)}}.padding(.horizontal,15).padding(.vertical,9)}}
}
struct ComparePagesView:View {
    @EnvironmentObject var model:AppModel
    @EnvironmentObject var layout:WorkspaceLayoutStore
    var body:some View {
        WorkspacePaneSplit(name:"document.pages",isVertical:layout.configuration.pageArrangement == .horizontal,primaryVisible:model.readingSingleVersion || model.pageMode != "after",auxiliaryVisible:!model.readingSingleVersion && model.pageMode != "before",extent:.fraction(layout.configuration.pageFraction),primaryMinimum:150,auxiliaryMinimum:150,onResize:{value in if case .fraction(let fraction)=value {layout.update{$0.pageFraction=min(0.8,max(0.2,fraction))}}}) {
            PageColumn(revision:model.revision(model.sourceFrom),side:model.readingSingleVersion ? L("doc.common.source"):L("doc.common.before"),pageID:$model.leftPageID).environmentObject(model)
        } auxiliary:{PageColumn(revision:model.revision(model.sourceTo),side:L("doc.common.after"),pageID:$model.rightPageID).environmentObject(model)}
        .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

struct CompareWorkspace: View {
    @ObservedObject private var readability=ReadabilityPreferences.shared
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var layout:WorkspaceLayoutStore
    var body: some View {
        VStack(spacing:0){
            ViewThatFits(in:.horizontal) {
                HStack(spacing:14){queryVersions;queryMode;Spacer(minLength:8);queryTools}
                VStack(alignment:.leading,spacing:12){queryVersions;HStack(spacing:14){queryMode;Spacer(minLength:8);queryTools}}
            }.readableInterface().padding(.horizontal,16).padding(.vertical,6)
                .background(WorkspaceLayoutMarker(name:"Reviset.document.versionBar"))
                .onChange(of:model.from){model.changeRange()}.onChange(of:model.to){model.changeRange()}
            if model.revisions.count>1 {
                Text(model.changeListProvenance).readableFont(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.bottom,8)
            }
            SelectedChangeContext().environmentObject(model)
            WorkspacePaneSplit(name:"document.inspector",auxiliaryFirst:layout.configuration.inspectorDock == .left,auxiliaryVisible:layout.configuration.inspectorVisible,extent:.points(layout.configuration.inspectorWidth),primaryMinimum:layout.configuration.changesVisible && layout.configuration.changesDock != .bottom ? 500:300,auxiliaryMinimum:260,onResize:{value in if case .points(let width)=value {layout.update{$0.inspectorWidth=min(480,max(260,width))}}}) {
                WorkspacePaneSplit(name:"document.changes",isVertical:layout.configuration.changesDock != .bottom,auxiliaryFirst:layout.configuration.changesDock == .left,auxiliaryVisible:layout.configuration.changesVisible,extent:.points(layout.configuration.changesDock == .bottom ? layout.configuration.changesHeight:layout.configuration.changesWidth),primaryMinimum:240,auxiliaryMinimum:layout.configuration.changesDock == .bottom ? 110:260,onResize:{value in if case .points(let size)=value {layout.update{if $0.changesDock == .bottom {$0.changesHeight=min(600,max(110,size))}else{$0.changesWidth=min(600,max(260,size))}}}}) {
                    ComparePagesView().environmentObject(model).environmentObject(layout)
                        .disabled(model.effectiveDiffMode != "source")
                        .opacity(model.effectiveDiffMode=="source" ? 1:0).allowsHitTesting(model.effectiveDiffMode=="source").accessibilityHidden(model.effectiveDiffMode != "source")
                        .overlay {if model.effectiveDiffMode=="text" {DocumentUnifiedDiff().environmentObject(model)}}
                } auxiliary:{ChangeListView().environmentObject(model).environmentObject(layout)}
            } auxiliary:{InspectorView().environmentObject(model)}
        }.onChange(of:model.selectedChangeID){Task {await Task.yield();model.selectEvidence()}}
    }
    @ViewBuilder private var queryVersions:some View {
        HStack(spacing:12) {
            Text(L("git.query")).readableFont(.callout,weight:.semibold)
            if model.revisions.count==1 {Text(versionDisplayName(0,model.revision(0))).readableFont(.body,weight:.semibold)} else {
                Menu {ForEach(Array(model.revisions.enumerated()),id:\.offset){index,revision in Button(versionDisplayName(index,revision)){model.selectVersion(index)}}} label:{Label(L("git.versionList"),systemImage:"clock.arrow.circlepath")}.help(L("git.versions"))
                VStack(alignment:.leading,spacing:3){
                    Text(L("doc.common.before")).readableFont(.caption2).foregroundStyle(.secondary)
                    Picker(L("doc.common.before"),selection:$model.from){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i<=model.to{Text(versionDisplayName(i,r)).tag(i)}}}.labelsHidden().frame(width:165)
                }
                Image(systemName:"arrow.right").foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:3){
                    Text(L("doc.common.after")).readableFont(.caption2).foregroundStyle(.secondary)
                    Picker(L("doc.common.after"),selection:$model.to){ForEach(Array(model.revisions.enumerated()),id:\.offset){i,r in if i>=model.from{Text(versionDisplayName(i,r)).tag(i)}}}.labelsHidden().frame(width:165)
                }
            }
        }.fixedSize(horizontal:true,vertical:false)
    }
    @ViewBuilder private var queryMode:some View {
        if model.revisions.count>1 {
            Picker(L("git.mode"),selection:$model.tab){Text(L("git.net")).tag("compare");Text(L("git.history")).tag("history")}
                .labelsHidden().pickerStyle(.segmented).frame(width:335 + (readability.pointSize(.body)-16)*18).disabled(model.from==model.to)
        }
    }
    private var queryTools:some View {
        HStack(spacing:10) {
            Menu {
                Picker(L("git.view"),selection:Binding(get:{model.effectiveDiffMode},set:{model.setDiffMode($0)})){Text(L("git.original")).tag("source");Text(L("git.textDiff")).tag("text")}.disabled(model.readingSingleVersion)
                Picker(L("doc.compare.documentView"),selection:$model.pageMode){Text(L("doc.compare.both")).tag("both");Text(L("doc.compare.beforeOnly")).tag("before");Text(L("doc.compare.afterOnly")).tag("after")}
                Picker(L("doc.common.zoom"),selection:$model.zoom){Text(L("doc.common.fit")).tag(0.0);Text("100%").tag(1.0);Text("150%").tag(1.5);Text("200%").tag(2.0)}
            } label:{Label(model.effectiveDiffMode=="source" ? L("git.original"):L("git.textDiff"),systemImage:"rectangle.split.2x1")}
            Button{model.showChanges.toggle()}label:{Label(L("layout.panel.changes"),systemImage:"list.bullet")}.help(L("layout.panel.changes"))
            Button{model.inspector.toggle()}label:{Image(systemName:"sidebar.right")}.help(L("doc.compare.evidence")).accessibilityLabel(L("doc.compare.evidence"))
        }.fixedSize(horizontal:true,vertical:false)
    }

}
struct SelectedChangeContext:View {
    @EnvironmentObject var model:AppModel
    @State private var detailsPresented=false
    private func label(_ item:DocumentSelectedContextItem)->String {
        let heading:String
        switch item.category {
        case .pageCorrespondence:heading=L("git.pageCorrespondence")
        case .textAssessment:heading=L("git.textAssessment")
        case .regionCorrespondence:heading=L("git.regionCorrespondence")
        case .appearanceAssessment:heading=L("git.appearanceAssessment")
        }
        let status:String
        switch item.status {
        case "human_confirmed":status=L("doc.matching.humanConfirmed")
        case "needs_review":status=L("doc.matching.needsReview")
        case "inferred":status=L("git.inferred")
        case "observed":status=L("git.observed")
        default:status=L("doc.matching.otherCode",.verbatim(item.status))
        }
        let reason=lineageReasonText(item.reasons.map(JSON.init),humanConfirmed:item.status=="human_confirmed" && model.selected["topology"]["semantics"].string != "directed_reachability")
        return heading+" · "+status+(reason.isEmpty ? "":" · "+reason)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:3){
            HStack(spacing:10){
                if !model.selected.isNull {
                    Text(changeDisplayName(model.selected)).readableFont(.caption,weight:.medium).lineLimit(1)
                    if model.eventInsideQuery {Text(L("git.selectedEvent")+" · "+changeVersionSummary(model.selected,revisions:model.revisions)).readableFont(.caption,weight:.semibold);Text(L("git.eventInsideQuery")).readableFont(.caption2).foregroundStyle(.secondary)}
                    if !model.selected["coverage_gaps"].array.isEmpty {Menu {ForEach(Array(model.selected["coverage_gaps"].array.enumerated()),id:\.offset){_,gap in Text(verbatim:String(selectedCoverageCaption(gap).prefix(240)))}}label:{Label(L("doc.coverage.heading"),systemImage:"exclamationmark.circle")}.readableFont(.caption2)}
                    Spacer(minLength:4)
                    if model.manuallyBrowsing {Button(L("git.returnToChange")){model.returnToChange()}.readableFont(.caption)}
                    ReadableActionButton(L("git.contextDetails"),identifier:"Reviset.document.contextDetails"){detailsPresented=true}
                }else {Text(model.readingSingleVersion ? L("git.reading"):model.unselectedChangeMessage).readableFont(.caption).foregroundStyle(.secondary);Spacer()}
            }.lineLimit(1).frame(minHeight:28)
            ForEach(documentSelectedContext(model.selected),id:\.category.rawValue){item in
                NativeContextSummaryLine(text:label(item),symbol:item.status=="observed" || item.status=="human_confirmed" ? "checkmark.circle":"exclamationmark.circle",warning:item.status=="needs_review" || item.status=="inferred")
            }
            if !model.selected["appearance_assessment"].string.isEmpty {Text(L("doc.coverage.noSemanticDeletion")).readableFont(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal:false,vertical:true)}
        }.padding(.horizontal,14).padding(.vertical,5).fixedSize(horizontal:false,vertical:true).frame(minHeight:28).clipped().background(Color(nsColor:.controlBackgroundColor)).background(WorkspaceLayoutMarker(name:"Reviset.document.selectedContext"))
        .sheet(isPresented:$detailsPresented){NativeDetailSheet(title:L("git.contextDetails")){SelectedChangeContextDetails().environmentObject(model)}}
    }
}
struct SelectedChangeContextDetails:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        ScrollView{LazyVStack(alignment:.leading,spacing:16){
            Text(changeDisplayName(model.selected)).readableFont(.headline)
            Text(changeVersionSummary(model.selected,revisions:model.revisions)).readableFont(.callout)
            if !model.selected["coverage_gaps"].array.isEmpty {
                Text(L("doc.coverage.heading")).readableFont(.headline)
                ForEach(Array(model.selected["coverage_gaps"].array.enumerated()),id:\.offset){_,gap in
                    VStack(alignment:.leading,spacing:5){Text(verbatim:gap["feature"].string).readableFont(.caption);NativeVerbatimReasonReader(text:gap["reason"].string).frame(height:120)}
                }
            }
            ForEach(documentSelectedContext(model.selected),id:\.category.rawValue){item in
                VStack(alignment:.leading,spacing:5){
                    Text(contextHeading(item.category)).readableFont(.headline)
                    Text(verbatim:item.status).readableFont(.caption).textSelection(.enabled)
                    ForEach(Array(item.reasons.enumerated()),id:\.offset){_,reason in NativeVerbatimReasonReader(text:reason).frame(height:220)}
                }
            }
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading)}
    }
    private func contextHeading(_ category:DocumentSelectedContextCategory)->String {
        switch category {case .pageCorrespondence:return L("git.pageCorrespondence");case .textAssessment:return L("git.textAssessment");case .regionCorrespondence:return L("git.regionCorrespondence");case .appearanceAssessment:return L("git.appearanceAssessment")}
    }
}
struct DocumentUnifiedDiff:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        let diff=documentTextDiff(model.selected)
        VStack(alignment:.leading,spacing:12){
            Text(L("git.textDiff")).readableFont(.headline)
            if !model.selected.isNull {Text(L("git.selectedEvent")+" · "+versionDisplayName(model.sourceFrom,model.revision(model.sourceFrom))+" → "+versionDisplayName(model.sourceTo,model.revision(model.sourceTo))+" · "+evidencePageSummary(model.selected)).readableFont(.headline).background(WorkspaceLayoutMarker(name:"Reviset.document.selectedEventHeader"))}
            Text(L("git.excerptNote")).readableFont(.caption).foregroundStyle(.secondary)
            if model.selected.isNull {Text(L("doc.tail.change.selectPrompt")).foregroundStyle(.secondary)}
            else if !diff.bounded {Text(L("git.diffBound")).foregroundStyle(.secondary)}
            else {
                if !diff.semantic {Text(L("git.neutralDiff")).readableFont(.caption).foregroundStyle(.secondary)}
                if diff.terminatorsDiffer {Text(L("git.terminatorsDiffer")).readableFont(.caption).foregroundStyle(.secondary)}
                if model.selected["before"].isNull {Text(L("doc.common.before")+" · "+L("doc.inspector.noSource")).readableFont(.caption).foregroundStyle(.secondary)}
                if model.selected["after"].isNull {Text(L("doc.common.after")+" · "+L("doc.inspector.noSource")).readableFont(.caption).foregroundStyle(.secondary)}
                if !diff.semantic {
                    ScrollView([.horizontal,.vertical]){VStack(alignment:.leading,spacing:14){neutralSource(model.selected["before"],title:L("doc.common.before"));neutralSource(model.selected["after"],title:L("doc.common.after"))}}
                } else {
                ScrollView([.horizontal,.vertical]){LazyVStack(alignment:.leading,spacing:1){ForEach(Array(diff.lines.enumerated()),id:\.offset){index,line in NativeDiffSourceLine(prefix:line.prefix,text:line.text,semantic:diff.semantic,terminator:line.terminator,markerName:"Reviset.document.diffLine.\(index)")}}}
                }
            }
            Spacer(minLength:0)
        }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:.textBackgroundColor)).background(WorkspaceLayoutMarker(name:"Reviset.document.unifiedDiff"))
    }
    private func neutralSource(_ source:JSON,title:String)->some View {
        VStack(alignment:.leading,spacing:5){Text(title).readableFont(.caption).foregroundStyle(.secondary);if source.isNull {Text(L("doc.inspector.noSource")).readableFont(.caption).foregroundStyle(.secondary)}else if source.string.isEmpty {Text(L("workbook.cell.emptyString")).readableFont(.caption).foregroundStyle(.secondary)}else {NativeNeutralSourceText(text:source.string,lines:neutralSourceLines(source.string,complete:true)?.map{(text:$0.text,terminator:$0.terminator)})}}
    }
}

struct ChangeListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var layout:WorkspaceLayoutStore
    private var compact:Bool {layout.configuration.changesDock != .bottom}
    var body: some View {VStack(spacing:5){
        if model.revisions.count != 1 {
        ViewThatFits(in:.horizontal) {
            HStack{filters;Spacer();changeCount}
            VStack(alignment:.leading,spacing:8){filters;changeCount}
        }.padding(.horizontal,12).padding(.top,8)
        }
        if model.filteredChanges.isEmpty {
            if model.revisions.count==1 {NativeEmptyComparisonGuidance(message:model.emptyChangesMessage,showsImport:true,canImport:model.canStartNewComparison,onImport:{model.openNewComparisonImport()},actionIdentifier:"Reviset.document.newComparison").frame(maxWidth:.infinity,maxHeight:.infinity)}
            else {VStack(spacing:10){Text(model.emptyChangesMessage).readableFont(.callout).foregroundStyle(.secondary);if model.canOpenStoredHistory {Button(L("git.openStoredHistory")){Task{await model.openStoredHistory()}}}}.frame(maxWidth:.infinity,maxHeight:.infinity).padding(12)}
        }
        else {ScrollViewReader {reader in ScrollView { LazyVStack(spacing:1) { ForEach(model.filteredChanges) { c in Button {model.chooseChange(c["change_id"].string)} label: {ChangeRow(change:c,compact:compact).padding(.horizontal,10).padding(.vertical,4).contentShape(Rectangle())}.buttonStyle(.plain).disabled(model.loadingChanges || !model.changesFailure.isEmpty).background(model.selectedChangeID==c["change_id"].string ? Color.blue.opacity(0.12) : Color.clear).id(c["change_id"].string) } }.padding(6) }.onChange(of:model.selectedChangeID){if let id=model.selectedChangeID{reader.scrollTo(id,anchor:.center)}}}}
        if model.loadingChangeDetail {ProgressView(L("doc.changes.loadingDetail")).readableFont(.caption).padding(.horizontal,12)}
        if !model.changesPaginationFailure.isEmpty {Text(model.changesPaginationFailure).readableFont(.caption).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal,12)}
        if !model.nextChangesCursor.isEmpty {
            Button {Task{await model.loadMoreChanges()}} label: {
                HStack {if model.loadingMoreChanges {ProgressView().controlSize(.small)};Text(L("doc.changes.loadMore"))}
            }.disabled(model.loadingChanges || model.loadingMoreChanges).padding(.bottom,6)
        }
    }}
    private var filters:some View {
        let arrangement=compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:6)):AnyLayout(HStackLayout(spacing:8))
        return arrangement {
            Picker(L("doc.changes.kind"),selection:$model.kind){Text(L("doc.changes.all")).tag("all");ForEach(changeKinds,id:\.self){Text(changeKindName($0)).tag($0)}}.frame(minWidth:200,idealWidth:220,maxWidth:260)
            TextField(L("doc.changes.search"),text:$model.search).textFieldStyle(.roundedBorder).frame(maxWidth:250)
        }
    }
    private var changeCount:some View {HStack{Button{model.stepChange(-1)}label:{Image(systemName:"chevron.up")}.help(L("git.previousChange")).accessibilityLabel(L("git.previousChange"));Button{model.stepChange(1)}label:{Image(systemName:"chevron.down")}.help(L("git.nextChange")).accessibilityLabel(L("git.nextChange"));if model.loadingChanges{ProgressView().controlSize(.small)};Text(L("doc.changes.loadedCount",.integer(model.changes.count),.integer(model.changesTotalCount))).readableFont(.caption).foregroundStyle(.secondary)}}
}

struct ChangeRow: View {
    @EnvironmentObject var model:AppModel
    let change: JSON
    var compact=false
    var kindName: String {changeDisplayName(change)}
    var text: String {documentChangeExcerpt(change)}
    var status: String {let value=change["lineage"]["status"].string;return value=="human_confirmed" ? L("doc.matching.humanConfirmed"):value=="needs_review" ? L("doc.matching.needsReview"):L("doc.matching.inferred")}
    var body:some View {
        let arrangement=compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:5)):AnyLayout(HStackLayout(spacing:10))
        arrangement {
            Text(kindName).readableFont(.body,weight:.semibold).foregroundStyle(change["kind"].string=="coverage_gap" ? Color.secondary:Color.blue).lineLimit(2).fixedSize(horizontal:false,vertical:true).frame(width:compact ? nil:155,alignment:.leading).help(kindName)
            VStack(alignment:.leading,spacing:3){Text(verbatim:text).lineLimit(compact ? 4:2).readableFont(.body);if model.tab=="history"{Text(changeVersionSummary(change,revisions:model.revisions)).readableFont(.caption2).foregroundStyle(.secondary).lineLimit(1)};Text(evidencePageSummary(change)).readableFont(.caption2).foregroundStyle(.secondary)}
            if !compact {Spacer()}
            if change["region_pairing_assessment"].string == "inferred"{Text(L("doc.matching.regionInferred")).readableFont(.caption2).foregroundStyle(.orange)}
            if change["text_assessment"].string == "inferred"{Text(L("doc.ocr.inferredReview")).readableFont(.caption2).foregroundStyle(.orange)}
            if !change["appearance_assessment"].string.isEmpty{Text(change["appearance_assessment"].string=="observed" ? L("doc.appearance.observed"):L("doc.appearance.inferred")).readableFont(.caption2).foregroundStyle(.orange)}
            Text(status).readableFont(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading)
    }
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
        if model.sourceTo != model.sourceFrom+1 { return L("doc.mapping.chooseAdjacent") }
        if !model.primaryPages(model.revision(model.sourceFrom)).contains(where:{$0["page_id"].string==model.leftPageID}) || !model.primaryPages(model.revision(model.sourceTo)).contains(where:{$0["page_id"].string==model.rightPageID}) { return L("doc.mapping.selectBoth") }
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
                Text(L("doc.inspector.selectedChange")).readableFont(.caption).foregroundStyle(.secondary)
                Text(model.selected.isNull && model.filteredChanges.isEmpty ? model.emptyChangesMessage:changeDisplayName(model.selected)).readableFont(.title3,weight:.semibold)
                if !model.selected.isNull {
                    Text(structural ? L("doc.inspector.beforeStructure") : L("doc.inspector.beforeText")).readableFont(.caption).foregroundStyle(.secondary)
                    sourceText(model.selected["before"],other:model.selected["after"],before:true).textSelection(.enabled)
                    Text(structural ? L("doc.inspector.afterStructure") : L("doc.inspector.afterText")).readableFont(.caption).foregroundStyle(.secondary)
                    sourceText(model.selected["after"],other:model.selected["before"],before:false).textSelection(.enabled)
                    if !neutralText {Text(L("doc.inspector.highlightHelp")).readableFont(.caption2).foregroundStyle(.secondary)}
                    if structural { Text(L("doc.inspector.lineageHelp")).readableFont(.caption).foregroundStyle(.secondary) }
                    Divider();Text(L("doc.inspector.sourceEvidence")).readableFont(.headline)
                    ForEach(Array(model.selected["evidence"].array.enumerated()),id:\.offset) { _,e in
                        VStack(alignment:.leading,spacing:6) {
                            Button { model.navigateEvidence(e) } label: { Label(evidenceVersionLabel(e,change:model.selected,revisions:model.revisions)+" · "+evidenceMethodName(e["method"].string,provenance:e["provenance"].string),systemImage:"doc.text.magnifyingglass").readableFont(.caption) }.buttonStyle(.plain)
                            Text(e["quote"].string).readableFont(.caption).textSelection(.enabled)
                        }.padding(9).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
                    }
                    if !model.selected["appearance_assessment"].string.isEmpty { Text(model.selected["appearance_assessment"].string == "observed" ? L("doc.appearance.stateObserved") : L("doc.appearance.stateInferred")).readableFont(.caption).foregroundStyle(.orange) }
                    Text(lineageReasonText(model.selected["lineage"]["reasons"].array,humanConfirmed:model.selected["lineage"]["status"].string == "human_confirmed" && model.selected["topology"]["semantics"].string != "directed_reachability")).readableFont(.caption2).foregroundStyle(.secondary)
                    CoverageGapEvidence(gaps:model.selected["coverage_gaps"].array)
                }
                Divider();Text(L("doc.mapping.reviewHeading")).readableFont(.headline)
                Text(L("doc.mapping.reviewDescription")).readableFont(.caption).foregroundStyle(.secondary)
                Button(L("doc.mapping.edit")) { model.mappingSheet=true }.disabled(!editable).accessibilityHint(Text(mappingUnavailableReason ?? L("doc.mapping.editHint")))
                if let message=mappingUnavailableReason { Text(message).readableFont(.caption).foregroundStyle(.secondary) }

            }.padding(17).frame(maxWidth:.infinity,alignment:.leading)
        }.sheet(isPresented:$model.mappingSheet) {
            MappingSheet(projectID:model.projectID,reportID:model.report["report_id"].string,draftHash:model.report["draft_hash"].string,before:model.revision(model.sourceFrom),after:model.revision(model.sourceTo),left:Set(model.mappingSelection["from_page_ids"].array.map(\.string)),right:Set(model.mappingSelection["to_page_ids"].array.map(\.string)),mode:model.mappingSelection["kind"].string,reason:model.mappingSelection["reason"].string).environmentObject(model)
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
        VStack(alignment:.leading,spacing:14){HStack{VStack(alignment:.leading){Text(L("doc.history.heading")).readableFont(.title2,weight:.semibold);Text(L("doc.history.description")).readableFont(.caption).foregroundStyle(.secondary);Text(L("doc.history.absenceHelp")).readableFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)};Spacer()}.padding(.horizontal,18).padding(.top,20)
        ScrollView([.vertical,.horizontal]){LazyVStack(alignment:.leading,spacing:1){HStack{Text(L("doc.history.lineage")).frame(width:180,alignment:.leading);ForEach(Array(revisions.enumerated()),id:\.offset){i,r in Text(versionDisplayName(i,r)).frame(width:130)}}.readableFont(.caption,weight:.semibold).padding(9)
            ForEach(model.report["lineages"].array){lineage in
                if let pages=pageIndex.lineage(lineage){
                    HStack(alignment:.top) {
                        Text(pages.first["text"].string.components(separatedBy:"\n").first ?? L("doc.common.page")).readableFont(.caption).lineLimit(1).frame(width:180,alignment:.leading)
                        ForEach(Array(revisions.enumerated()),id:\.offset) { i,r in
                            let members=pages.pagesByRevision[i] ?? []
                            VStack(spacing:4) {
                                if members.isEmpty { Text("—").readableFont(.caption).foregroundStyle(.secondary).padding(.vertical,7) }
                                ForEach(members) { page in
                                    Button { model.openHistoryPage(i,page["page_id"].string) } label: { Text("p.\(page["page"].int)").readableFont(.caption).frame(width:115).padding(.vertical,7).background(Color.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).accessibilityLabel(L("doc.history.openPage", .verbatim(r["label"].string), .integer(page["page"].int)))
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
        GroupBox(L("doc.export.mcpHeading")){VStack(alignment:.leading,spacing:12){Text(L("doc.export.mcpDescription")).readableFont(.caption).foregroundStyle(.secondary);Text(L("git.reportScope")).readableFont(.caption).foregroundStyle(.secondary);Text(model.currentMCPConfig ?? (model.mcpFailure.isEmpty ? L("doc.export.mcpLoading"):L("doc.export.mcpFailure", .verbatim(model.mcpFailure)))).readableFont(.caption,design:.monospaced).textSelection(.enabled).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.textBackgroundColor));Button(L("doc.export.copyConfig")){guard let config=model.currentMCPConfig else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(config,forType:.string);model.statusMessage=UIMessage("doc.export.configCopied")}.disabled(model.currentMCPConfig == nil);if !model.mcpFailure.isEmpty {Button(L("doc.export.reloadConfig")){Task{await model.loadMCP()}}}}.padding(12)}
        GroupBox(L("doc.export.limitsHeading")){Text(L("doc.export.limitsDescription")).readableFont(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading)}
    }.padding(35).frame(maxWidth:1000,alignment:.leading)}.task(id:model.projectID){await model.loadMCP()}}
}
struct ImportView: View {
    // Initialized once per sheet; parent redraws and dismissal cannot replace
    // the route used by a submission already belonging to this dialog.
    @State private var intent:ImportIntent
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var title=""
    @State private var titleEdited=false
    private var effectiveTitle:String { titleEdited ? title : L("doc.import.defaultTitle") }
    private var titleBinding:Binding<String> { Binding(get:{effectiveTitle},set:{value in guard titleEdited || value != effectiveTitle else{return};title=value;titleEdited=true}) }
    @State private var rows:[ImportRow]=[]
    @State private var saving=false
    @State private var choosing=false
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    init(intent:ImportIntent = .ordinary,initialRows:[ImportRow]=[],initialTitle:String?=nil){_intent=State(initialValue:intent);_rows=State(initialValue:initialRows);_title=State(initialValue:initialTitle ?? "");_titleEdited=State(initialValue:initialTitle != nil)}
    var locked:Bool{saving || choosing}
    var body: some View {
        VStack(alignment:.leading,spacing:17){
            HStack{Text(L("doc.import.documents")).readableFont(.title2,weight:.semibold);Spacer();Button(L("doc.common.close")){dismiss()}.keyboardShortcut(.cancelAction).disabled(locked)}
            Text(L("doc.import.description")).readableFont(.callout).foregroundStyle(.secondary)
            if intent == .newComparison {Text(L("git.importComparisonMinimum")).readableFont(.callout).foregroundStyle(.secondary)}
            TextField(L("doc.import.projectName"),text:titleBinding).textFieldStyle(.roundedBorder).disabled(locked).accessibilityIdentifier("Reviset.import.projectTitle")
            Button{choose()}label:{Label(L("doc.import.chooseFiles"),systemImage:"plus")}.disabled(locked)
            List{
                ForEach(Array(rows.enumerated()),id:\.element.id){i,r in
                    HStack{
                        Text("\(i+1)").foregroundStyle(.secondary)
                        VStack(alignment:.leading){
                            TextField(L("doc.import.revisionName"),text:Binding(get:{rows.indices.contains(i) ? rows[i].label:""},set:{if rows.indices.contains(i){rows[i].label=$0}})).disabled(locked)
                            Text(r.urls.map(\.lastPathComponent).joined(separator:" + ")).readableFont(.caption2).foregroundStyle(.secondary)
                            if r.members.count==2{Label(L("doc.import.bundleBadge"),systemImage:"link").readableFont(.caption).foregroundStyle(.secondary)}
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
            if !failure.isEmpty{Text(failure).foregroundStyle(.red).readableFont(.caption)}
            HStack{
                Text(L("doc.import.integrityHelp")).readableFont(.caption).foregroundStyle(.secondary)
                Spacer()
                if locked{ProgressView().controlSize(.small);Text(choosing ? L("doc.import.checking"):L("doc.import.saving")).readableFont(.caption)}
                Button(L("doc.import.analyze")){Task{await create()}}.buttonStyle(.borderedProminent).disabled(locked || rows.count<intent.minimumVersionEntries || effectiveTitle.trimmingCharacters(in:.whitespaces).isEmpty || rows.contains{$0.label.trimmingCharacters(in:.whitespaces).isEmpty})
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
    func create() async {saving=true;do{let p=try await model.create(title:effectiveTitle,rows:rows,intent:intent);model.report=JSON();try await model.refresh();model.projectID=p["project_id"].string;dismiss();await model.run(model.projectID)}catch{failureMessage=bridgeErrorMessage(error)};saving=false}
}
