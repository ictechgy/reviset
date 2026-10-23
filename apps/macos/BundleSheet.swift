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
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
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
    var keepsPair:Bool {mode=="link" && !pdfID.isEmpty && current["rendered_page_id"].string==pdfID}
    var activeDecisionIDs:Set<String> {Set(context["manual_states"].array.filter{!$0["displaced"].bool}.map{$0["decision_id"].string})}
    var proposedPair:String {
        let before=pdfs.first{$0["page_id"].string==current["rendered_page_id"].string}.map{"PDF p.\($0["page"].int)"} ?? L("doc.tail.noLink")
        let after=mode=="unlink" ? L("doc.tail.noLink"):pdfs.first{$0["page_id"].string==pdfID}.map{"PDF p.\($0["page"].int)"} ?? L("doc.tail.notSelected")
        return L("doc.tail.existingToAfterApply", .verbatim(before), .verbatim(after))
    }
    var selectionWarnings:[String] {
        let source=sources.first{$0["page_id"].string==sourceID} ?? JSON(),target=pdfs.first{$0["page_id"].string==pdfID} ?? JSON()
        var warnings=(source["coverage_gaps"].array+target["coverage_gaps"].array).map{coverageReasonName($0["reason"].string)}
        if mode=="link",!source.isNull,!target.isNull {
            if source["comparison_text_hash"].string != target["comparison_text_hash"].string || target["comparison_unresolved"].bool {warnings.append(coverageReasonName("manual_reference_text_unresolved_or_different"))}
            if source["height"].number>0,target["height"].number>0,abs((source["width"].number/source["height"].number)/(target["width"].number/target["height"].number)-1)>0.001 {warnings.append(coverageReasonName("manual_reference_geometry_mismatch"))}
            if source["hidden"].bool {warnings.append(coverageReasonName("manual_reference_linked_hidden_source_slide"))}
            if !target["native_raster_available"].bool {warnings.append(coverageReasonName("manual_reference_native_raster_unavailable"))}
            if !target["reference_transform_available"].bool {warnings.append(coverageReasonName("manual_reference_transform_unavailable"))}
            if revision["coverage_gaps"].array.contains(where:{$0["reason"].string=="reference_pdf_reused_for_different_pptx"}) {warnings.append(coverageReasonName("manual_reference_pdf_reused_for_different_pptx"))}
        }
        var seen=Set<String>();return warnings.filter{seen.insert($0).inserted}
    }
    var validation:String? {
        if context.isNull {return L("doc.tail.loadingLinkInfo")}
        if !context["current_snapshot"].bool {return L("doc.tail.editLinksInLatestAnalysis")}
        if !sources.contains(where:{$0["page_id"].string==sourceID}) {return L("doc.tail.selectPptxSlide")}
        if mode=="link" && !pdfs.contains(where:{$0["page_id"].string==pdfID}) {return L("doc.tail.selectPdfPageToLink")}
        if reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return L("doc.tail.enterChangeReason")}
        if reason.utf16.count>2000 {return L("doc.tail.changeReasonWithin2000Units")}
        return nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text(L("doc.tail.providedPdfPageLink")).font(.title2.weight(.semibold));Text(revision["label"].string).foregroundStyle(.secondary);Spacer();Button(LC("doc.tail.linkHistoryCount", context["decision_count"].int)){showHistory=true}.disabled(context.isNull || context["decision_count"].int==0 || saving);Button(L("doc.common.cancel")){dismiss()}.keyboardShortcut(.cancelAction).disabled(saving)}
            Text(L("doc.tail.pairSameVersionPptxPdfNoFidelity")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:16) {
                pageList(sources,search:$sourceSearch,selection:$sourceID,title:L("doc.tail.pptxSourceSlide"))
                Image(systemName:mode=="link" ? "link":"link.badge.plus").foregroundStyle(.secondary).frame(width:20)
                pageList(pdfs,search:$pdfSearch,selection:$pdfID,title:L("doc.tail.providedPdfPage")).disabled(mode=="unlink")
            }.frame(height:170).disabled(saving)
            HStack(spacing:16) {
                BundlePagePreview(projectID:projectID,reportID:reportID,pageID:sourceID,basis:"source",title:L("doc.tail.pptxSourceStructureOrConversionView"))
                Color.clear.frame(width:20)
                BundlePagePreview(projectID:projectID,reportID:reportID,pageID:pdfID,basis:"source",title:L("doc.tail.providedPdfSource"))
            }.frame(maxHeight:.infinity)
            if !selectionWarnings.isEmpty {
                DisclosureGroup(LC("doc.tail.selectedSourceLinkCautionCount", selectionWarnings.count),isExpanded:$warningsExpanded){ScrollView{VStack(alignment:.leading,spacing:4){ForEach(selectionWarnings,id:\.self){Text($0).font(.caption).foregroundStyle(.orange)}}.frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:65)}.font(.caption)
            }
            HStack {Picker(L("doc.tail.linkMethod"),selection:$mode){Text(L("doc.tail.linkPdfPage")).tag("link");Text(L("doc.tail.unlinkBlockSlidePdf")).tag("unlink")}.labelsHidden().pickerStyle(.segmented).disabled(saving);Text(statusText).font(.caption).foregroundStyle(.secondary)}
            Text(proposedPair).font(.caption.weight(.medium))
            if keepsPair {Text(L("doc.tail.keepLinkRecordReasonConfirmation")).font(.caption).foregroundStyle(.secondary)}
            if !conflicts.isEmpty {
                DisclosureGroup(keepsPair ? L("doc.tail.previousChangeReasonForCurrentLink"):LC("doc.tail.replacesExistingLinksConfirmReason", conflicts.count),isExpanded:$conflictsExpanded) {
                    ScrollView {VStack(alignment:.leading,spacing:6){ForEach(Array(conflicts.enumerated()),id:\.offset){_,entry in
                        Text(L("doc.bundle.pairAssociation", .verbatim(pairLabel(entry)), .verbatim(entry["association"].string=="human_confirmed" ? L("doc.bundle.userLinked"):L("doc.bundle.inferred")))).font(.caption.weight(.medium))
                        if !entry["reason"].string.isEmpty {Text(L("doc.tail.previouslyRecordedChangeReason")).font(.caption2).foregroundStyle(.secondary);Text(entry["reason"].string).font(.caption).textSelection(.enabled)}
                    }}.frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:65)
                }.font(.caption)
            }
            TextField(L("doc.tail.changeReasonRequiredKeptVerbatim"),text:$reason,axis:.vertical).lineLimit(2...3).textFieldStyle(.roundedBorder).disabled(saving)
            HStack {Text(validation ?? L("doc.tail.applyPreservesHistoryAnalyzesFixedReport")).foregroundStyle(validation == nil ? Color.secondary:Color.orange);Spacer();Text("\(reason.utf16.count)/2000").help(L("doc.tail.someEmojiCountAsMultipleUnits"))}.font(.caption)
            if !failure.isEmpty {Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
            HStack {Text(L("doc.tail.cancelBeforeApplyDoesNotSave")).font(.caption).foregroundStyle(.secondary);Spacer();if saving{ProgressView().controlSize(.small)};Button(L("doc.tail.applyAndReanalyze")){Task{await apply()}}.buttonStyle(.borderedProminent).disabled(validation != nil || saving || model.busy)}
        }.padding(22).frame(width:1040,height:780).background(Color(nsColor:.windowBackgroundColor))
        .sheet(isPresented:$showHistory){BundleHistorySheet(projectID:projectID,reportID:reportID,occurrence:occurrence,activeDecisionIDs:activeDecisionIDs).environmentObject(model)}
        .onChange(of:sourceID){selectCurrentPDF()}
        .task {
            do {
                context=try await model.bundleContext(project:projectID,report:reportID,occurrence:occurrence)
                sourceID=sources.contains(where:{$0["page_id"].string==initialSource}) ? initialSource:sources.first?["page_id"].string ?? ""
                selectCurrentPDF()
            }catch{failureMessage=bridgeErrorMessage(error)}
        }
    }
    var statusText:String {
        if !current.isNull {return L("doc.bundle.currentAssociation", .verbatim(pairLabel(current)), .verbatim(current["association"].string=="human_confirmed" ? L("doc.bundle.userLinked"):L("doc.bundle.inferred")))}
        let state=context["manual_states"].array.first{$0["source_page_id"].string==sourceID}
        return state == nil ? L("doc.tail.noCurrentLink"):state!["displaced"].bool ? L("doc.tail.removedDueToAnotherLink"):L("doc.tail.unlinkedBlockedByUser")
    }
    func selectCurrentPDF(){pdfID=current["rendered_page_id"].string}
    func pairLabel(_ entry:JSON)->String {
        let source=sources.first{$0["page_id"].string==entry["source_page_id"].string}?["page"].int ?? 0
        let target=pdfs.first{$0["page_id"].string==entry["rendered_page_id"].string}?["page"].int ?? 0
        return L("doc.tail.slideToPdfPage", .integer(source), .integer(target))
    }
    func pageList(_ all:[JSON],search:Binding<String>,selection:Binding<String>,title:String)->some View {
        let pages=all.filter{search.wrappedValue.isEmpty || String($0["page"].int).contains(search.wrappedValue) || $0["text"].string.localizedCaseInsensitiveContains(search.wrappedValue)}
        let selected=all.first{$0["page_id"].string==selection.wrappedValue}
        return ScrollViewReader {proxy in
            VStack(alignment:.leading,spacing:6){
                HStack{Text(title).font(.headline);Spacer();Text(LC("doc.tail.pageCount", all.count)).font(.caption).foregroundStyle(.secondary)}
                TextField(L("doc.tail.searchNumberOrWording"),text:search).textFieldStyle(.roundedBorder)
                List(selection:Binding<String?>(get:{selection.wrappedValue.isEmpty ? nil:selection.wrappedValue},set:{selection.wrappedValue=$0 ?? ""})) {
                    ForEach(pages){page in HStack(alignment:.top){Text("p.\(page["page"].int)").monospacedDigit().frame(width:50,alignment:.leading);Text(page["text"].string.isEmpty ? L("doc.tail.noSummaryRead"):page["text"].string).font(.caption).lineLimit(2);if page["hidden"].bool{Text(L("doc.tail.hidden")).font(.caption2).foregroundStyle(.secondary)}}.tag(page["page_id"].string).id(page["page_id"].string)}
                }
                if let selected {Button(L("doc.tail.selectedPageViewInList", .integer(selected["page"].int))){search.wrappedValue="";Task{@MainActor in await Task.yield();proxy.scrollTo(selection.wrappedValue,anchor:.center)}}.buttonStyle(.plain).font(.caption).foregroundStyle(.blue)}
            }.frame(maxWidth:.infinity).onChange(of:selection.wrappedValue){proxy.scrollTo(selection.wrappedValue,anchor:.center)}
        }
    }
    func apply() async {
        guard validation == nil,!saving else{return};saving=true;failure=""
        do {
            try await model.applyBundle(project:projectID,report:reportID,draftHash:context["draft_hash"].string,occurrence:occurrence,sourceAsset:sourceAsset,pdfAsset:pdfAsset,source:sourceID,pdf:mode=="link" ? pdfID:nil,action:mode,reason:reason)
            dismiss();await model.run(projectID)
        }catch{failureMessage=bridgeErrorMessage(error);saving=false}
    }
}

struct BundleHistorySheet:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    let projectID:String
    let reportID:String
    let occurrence:String
    var activeDecisionIDs:Set<String>=[]
    @State private var entries:[JSON]=[]
    @State private var cursor:String?=nil
    @State private var loading=false
    @State private var loaded=false
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    @State private var reasons:[String:String]=[:]
    @State private var expanding=Set<String>()
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{Text(L("doc.tail.providedPdfLinkHistory")).font(.title2.weight(.semibold));Spacer();Button(L("doc.common.close")){dismiss()}.keyboardShortcut(.cancelAction)}
            Text(L("doc.tail.linkHistoryOldestFirstFixedReport")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:14) {
                    ForEach(Array(entries.enumerated()),id:\.offset){_,entry in historyRow(entry)}
                    if cursor != nil {Button(L("doc.tail.showMoreRecords")){Task{await load()}}.disabled(loading)}
                    if loading {ProgressView()}
                    if loaded && entries.isEmpty {Text(L("doc.tail.noSavedLinkHistory")).foregroundStyle(.secondary)}
                }
            }
            if !failure.isEmpty{Text(failure).font(.caption).foregroundStyle(.red);if !loaded{Button(L("doc.tail.reload")){Task{await load()}}.disabled(loading)}}
            Text(L("doc.tail.userLinkNotExportOrFidelityCertification")).font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width:800,height:580).background(Color(nsColor:.windowBackgroundColor)).task{await load()}
    }
    func historyRow(_ entry:JSON)->some View {
        let id=entry["decision_id"].string
        return VStack(alignment:.leading,spacing:6){
            Text(L("doc.bundle.historyEntry", .integer(entry["ordinal"].int+1), .integer(entry["source_page"].int), .verbatim(entry["action"].string=="unlink" ? L("doc.tail.noPdfLink"):"PDF p.\(entry["rendered_page"].int)"))).font(.headline)
            if activeDecisionIDs.contains(id) {Label(L("doc.tail.currentAppliedState"),systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.blue)}
            Text(L("doc.tail.changeReason")).font(.caption).foregroundStyle(.secondary)
            Text(reasons[id] ?? entry["reason"].string).font(.callout).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
            if !entry["next_reason_offset"].isNull && reasons[id]==nil {Button(expanding.contains(id) ? L("doc.tail.loadingReason"):L("doc.tail.viewFullChangeReason")){Task{await expand(entry)}}.disabled(expanding.contains(id))}
            Text(L("doc.bundle.displacedWithID", .verbatim(LC("doc.bundle.displaced",entry["displaced"].array.count)), .verbatim(String(id.prefix(17))+"…"))).font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
    }
    func request(_ extra:[String:Any]=[:]) async throws->JSON {
        var args:[String:Any]=["project_id":projectID,"report_id":reportID,"revision_id":occurrence,"max_output_tokens":8000,"limit":10]
        args.merge(extra){_,value in value};return try await model.bridge.call("bundleDecisions",args)
    }
    func load() async {
        guard !loading else{return};loading=true;failure="";defer{loading=false}
        do{let response=try await request(cursor.map{["cursor":$0]} ?? [:]);entries += response["items"].array;cursor=response["next_cursor"].string.isEmpty ? nil:response["next_cursor"].string;loaded=true}catch{failureMessage=bridgeErrorMessage(error)}
    }
    func expand(_ entry:JSON) async {
        let id=entry["decision_id"].string;guard !expanding.contains(id) else{return};expanding.insert(id);defer{expanding.remove(id)}
        do{var text="",offset=0
            for _ in 0..<8 {let response=try await request(["decision_id":id,"reason_offset":offset,"reason_length":500]),part=response["items"].array.first ?? JSON();guard !part.isNull,part["omitted_fields"].array.isEmpty else{throw BridgeError(code:"HISTORY_REASON",message:UIMessage("doc.tail.changeReasonLoadFailed"))};text+=part["reason"].string;if part["next_reason_offset"].isNull{reasons[id]=text;return};let next=part["next_reason_offset"].int;guard next>offset else{break};offset=next}
            throw BridgeError(code:"HISTORY_REASON",message:UIMessage("doc.tail.changeReasonRemainderCheckFailed"))
        }catch{failureMessage=bridgeErrorMessage(error)}
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
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    @State private var loadingPage=false
    @State private var loadedScope=""
    var sourceCaption:String {payload["source"]["origin"].string=="pptx_converted" ? L("doc.tail.libreOfficeRender"):payload["source"]["kind"].string=="pptx" ? L("doc.tail.structureViewSourceScreenUnverified"):" "}
    var body:some View {
        VStack(alignment:.leading,spacing:5){
            VStack(alignment:.leading,spacing:3){Text(title);Text(sourceCaption).accessibilityHidden(sourceCaption==" ")}.font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            if !payload["source"]["warnings"].array.isEmpty {Text(payload["source"]["warnings"].array.map{renderWarningName($0.string)}.joined(separator:" · ")).font(.caption2).foregroundStyle(.orange).lineLimit(2)}
            GeometryReader{geometry in
                if pageID.isEmpty {ContentUnavailableView(L("doc.tail.selectPage"),systemImage:"doc")}
                else if !failure.isEmpty {Text(failure).foregroundStyle(.red).font(.caption)}
                else if payload.isNull {ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity)}
                else if payload["source"]["kind"].string=="pdf" {OriginalPDFView(path:payload["source"]["path"].string,pageNumber:payload["page"]["page"].int,zoom:0,evidence:JSON(),page:payload["display_page"])}
                else if let size=fittedPageSize(width:payload["page"]["width"].number,height:payload["page"]["height"].number,available:geometry.size,inset:8) {StructureCanvas(page:payload["page"],evidence:JSON()).frame(width:size.width,height:size.height).frame(maxWidth:.infinity,maxHeight:.infinity)}
                else {ContentUnavailableView(L("doc.tail.page.sizeUndeterminable"),systemImage:"exclamationmark.triangle")}
            }.background(Color(nsColor:.windowBackgroundColor).overlay(Color.primary.opacity(0.045))).clipShape(RoundedRectangle(cornerRadius:5))
                .overlay{if loadingPage && !payload.isNull && failure.isEmpty{VStack{ProgressView();Text(L("doc.tail.verifyingPagePreviousLookupView")).font(.caption)}.padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:6))}}.allowsHitTesting(!loadingPage)
        }.frame(maxWidth:.infinity).task(id:projectID+reportID+pageID+basis){
            let scope=projectID+"|"+reportID+"|"+basis;if loadedScope != scope{payload=JSON()};failure="";loadingPage=true;defer{if !Task.isCancelled{loadingPage=false}};guard !pageID.isEmpty else{payload=JSON();return}
            do{let result=try await model.bridge.call("page",["project_id":projectID,"report_id":reportID,"page_id":pageID,"basis":basis]);if !Task.isCancelled{payload=result;loadedScope=scope}}catch{if !Task.isCancelled{payload=JSON();failureMessage=bridgeErrorMessage(error)}}
        }
    }
}
