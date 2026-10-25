import Foundation
import AppKit
import SwiftUI

enum Smoke { @MainActor static func captureView(_ window:NSWindow,_ url:URL)throws {throw NSError(domain:"UnexpectedScreenshotInModelProbe",code:1)} }

private struct PageColumnProbeHarness:View {
    @ObservedObject var model:AppModel
    var body:some View {PageColumn(revision:model.revision(0),side:"Source",pageID:$model.leftPageID).environmentObject(model)}
}
private struct SoleDocumentImportProbeHarness:View {
    @ObservedObject var model:AppModel
    let layout:WorkspaceLayoutStore
    var body:some View {ChangeListView().environmentObject(model).environmentObject(layout).sheet(isPresented:$model.importSheet){ImportView(intent:model.importIntent).environmentObject(model)}}
}
private struct SoleWorkbookImportProbeHarness:View {
    @ObservedObject var model:WorkbookModel
    var body:some View {WorkbookEmptyChangesState(model:model).sheet(isPresented:$model.importPresented){WorkbookImportSheet(model:model,intent:model.importIntent)}}
}

@main struct GitDiffWorkspaceProbe {
    // AppKit owns this probe's event loop. An async @main drain can return when
    // a real SwiftUI modal stops CFRunLoop, before the remaining checks finish.
    @MainActor static func main() {
        let application=NSApplication.shared
        application.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {try await runChecks();fflush(stdout);exit(0)}
            catch {FileHandle.standardError.write(Data(("FAIL native Git diff workspace: \(error)\n").utf8));exit(1)}
        }
        application.run()
        FileHandle.standardError.write(Data("FAIL native Git diff workspace: AppKit loop returned before checks completed\n".utf8))
        exit(1)
    }
    @MainActor static func runChecks() async throws {
        configureLegacyNativeLocalization()
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        for (before,after) in [("100","120"),("a\nb\na","a\na\nb"),("", ""),("a\n","\na"),("문서 👨‍👩‍👧‍👦\r\n금액 100", "문서 👨‍👩‍👧‍👦\r\n금액 120"),("a\r\nb", "a\nb"),("a\rb", "a\rc"),("é", "e\u{301}"),("e\u{301}","é"),("각\n내용", "\u{1100}\u{1161}\u{11a8}\n내용")] {
            let diff=unifiedTextDiff(before:before,after:after,semantic:true)
            try require(diff.bounded && diff.semantic,"UnexpectedDiffFallback")
            try require(Array(diff.lines.filter{$0.prefix != "+"}.map(\.rawText).joined().utf16)==Array(before.utf16),"BeforeTextChangedByDiff")
            try require(Array(diff.lines.filter{$0.prefix != "−"}.map(\.rawText).joined().utf16)==Array(after.utf16),"AfterTextChangedByDiff")
        }
        for long in [String(repeating:"가",count:4097),String(repeating:"😀",count:2049),String(repeating:"x\n",count:129)] {
            let diff=unifiedTextDiff(before:long,after:"short",semantic:true)
            try require(!diff.bounded && diff.lines.isEmpty && !diff.semantic,"ExceededDiffBoundOrPresentedTruncatedText")
        }
        let terminated=unifiedTextDiff(before:"a\n",after:"a\n",semantic:true)
        try require(terminated.bounded && terminated.lines.count==1 && terminated.lines[0].text=="a" && terminated.lines[0].terminator=="\n","TrailingTerminatorInventedEOFTail")
        for ending in ["\n","\r","\r\n"] {
            let inside=String(repeating:"x"+ending,count:128),outside=String(repeating:"x"+ending,count:129)
            let accepted=unifiedTextDiff(before:inside,after:inside,semantic:true),refused=unifiedTextDiff(before:outside,after:outside,semantic:true)
            try require(accepted.bounded && accepted.lines.count==128 && accepted.lines.map(\.rawText).joined().utf16.elementsEqual(inside.utf16) && !refused.bounded && refused.lines.isEmpty,"TerminatedLineBudgetBoundaryOrRawSourceChanged")
            let neutral=neutralSourceLines(inside,complete:true)
            try require(neutral?.count==128 && neutral?.map(\.rawText).joined().utf16.elementsEqual(inside.utf16)==true && neutralSourceLines(outside,complete:true)==nil,"NeutralAnnotationChangedLineBudgetOrRawSource")
        }
        try require(neutralSourceLines("partial\r",complete:false)==nil && neutralSourceLines(String(repeating:"x",count:4097),complete:true)==nil,"IncompleteOrOverBudgetNeutralTextClaimedEOF")
        for kind in ["text_occluded","text_struck_through","text_revealed","coverage_gap","page_deleted","page_merged","visual_region_changed"] {
            let diff=documentTextDiff(JSON(["kind":kind,"before":"hidden 100","after":"hidden 120"]))
            try require(!diff.semantic && diff.lines.allSatisfy{$0.prefix.isEmpty},"AppearanceInterpretedAsTextDeletion")
        }
        let absent=documentTextDiff(JSON(["kind":"text_modified","before":"100"]))
        try require(!absent.semantic,"MissingObservationInterpretedAsEmptyText")
        let structural=documentTextDiff(JSON(["kind":"text_modified","before":"100","after":"120","topology":["semantics":"directed_reachability"]]))
        try require(!structural.semantic,"TopologyInterpretedAsTextDeletion")

        // Canonical equivalence is not raw source equality: preserve each exact
        // UTF-16 sequence even when Swift String == considers it the same text.
        let canonical=unifiedTextDiff(before:"é",after:"e\u{301}",semantic:true)
        try require(canonical.lines.contains(where:{$0.prefix=="−"}) && canonical.lines.contains(where:{$0.prefix=="+"}),"CanonicalEquivalentSourceDifferenceHidden")
        for (before,after) in [("a","a\n"),("a\r\nb","a\nb"),("a\rb","a\nb"),("é\r\ne\u{301}\r","é\ne\u{301}\n")] {
            let diff=unifiedTextDiff(before:before,after:after,semantic:true)
            try require(diff.terminatorsDiffer && diff.lines.filter{$0.prefix != "+"}.map(\.rawText).joined().utf16.elementsEqual(before.utf16) && diff.lines.filter{$0.prefix != "−"}.map(\.rawText).joined().utf16.elementsEqual(after.utf16),"TerminatorOnlyChangeLostExactSource")
            try require(diff.lines.allSatisfy{!$0.text.contains("\r") && !$0.text.contains("\n")} && Set(diff.lines.map{sourceTerminatorLabel($0.terminator)}).isSubset(of:["⟦CR⟧","⟦LF⟧","⟦CRLF⟧","⟦EOF⟧"]),"TerminatorMarkersWereInsertedIntoRawText")
        }
        func cell(_ value:Any,state:String,total:Int,offset:Int=0,cache:String="present",role:String="explicit",type:String="string")->JSON {
            JSON(["address":"C3","source_ref":"source!C3","value":value,"value_type":type,"formula":"SUM(C1:C2)","formula_interpretation":role,"cached_result":cache,"cache_freshness":"unknown","text_continuations":["value":["state":state,"offset":offset,"next_offset":NSNull(),"total_length":total],"formula":["state":"complete","offset":0,"next_offset":NSNull(),"total_length":10]]])
        }
        let missing=cell(NSNull(),state:"missing",total:0,cache:"missing"),empty=cell("",state:"empty",total:0),zero=cell("0",state:"complete",total:1,type:"number")
        try require(workbookRawField(missing,field:"value").state == .missing && workbookRawField(missing,field:"value").text == nil,"MissingCacheBecameEmptyString")
        try require(workbookRawField(empty,field:"value").state == .empty && workbookRawField(empty,field:"value").text?.utf16.count==0,"ObservedEmptyStringBecameUnavailable")
        try require(workbookRawField(zero,field:"value").state == .complete && workbookRawField(zero,field:"value").text=="0","ZeroBecameMissingOrEmpty")
        try require(workbookFieldTextDiff(before:missing,after:empty,field:"value",textOffset:0,eligibility:.neutral)==nil,"MissingCacheDiffUsedInventedEmptyString")
        try require(workbookSelectedWarningMessages(missing).contains(L("git.cacheMissing")) && workbookSelectedWarningMessages(empty).contains(L("git.cacheUnknown")),"SelectedCacheWarningsHiddenByInspector")
        let unresolved=cell("100",state:"complete",total:3,role:"unresolved"),newValue=cell("120",state:"complete",total:3)
        let unresolvedDiff=workbookFieldTextDiff(before:unresolved,after:newValue,field:"value",textOffset:0,eligibility:.neutral)
        try require(unresolvedDiff?.semantic==false && unresolvedDiff?.lines.allSatisfy({$0.prefix.isEmpty})==true && workbookSelectedWarningMessages(unresolved).contains(L("workbook.cell.unresolvedFormula")),"UnresolvedFormulaClaimedSemanticValueEdit")
        var partialData=cell("abc",state:"truncated",total:10).dictionary;partialData["text_continuations"]=["value":["state":"truncated","offset":0,"next_offset":3,"total_length":10]]
        let partial=JSON(partialData),earlier=cell("",state:"truncated",total:10,offset:10),contradictory=cell("",state:"missing",total:0)
        try require(workbookRawField(partial,field:"value").state == .partial && workbookRawField(earlier,field:"value").state == .earlier && workbookRawField(contradictory,field:"value").state == .invalid,"ContinuationStatesWereFlattened")
        try require(workbookFieldTextDiff(before:partial,after:newValue,field:"value",textOffset:0,eligibility:.neutral)==nil && workbookFieldTextDiff(before:earlier,after:empty,field:"value",textOffset:10,eligibility:.neutral)==nil,"PartialOrEarlierFragmentPresentedAsCompleteDiff")
        try require(workbookRawField(cell("a",state:"complete",total:2),field:"value").state == .invalid,"InconsistentContinuationWasTrusted")
        try require(missing["address"].string=="C3" && missing["source_ref"].string=="source!C3" && earlier["text_continuations"]["value"]["offset"].int==10,"DisplayProjectionChangedPhysicalOrFragmentIdentity")

        // These contexts are generated by the real TypeScript diffWorkbooks
        // implementation in the integration wrapper, including withheld events.
        guard CommandLine.arguments.count==3 else{throw NSError(domain:"EngineContextFixtureMissing",code:1)}
        let engineCases=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))).array
        try require(engineCases.count>=4,"EngineContextCasesMissing")
        for item in engineCases {
            let before=item["before"],after=item["after"],change=item["change"]
            let scope=WorkbookSelectedEventScope(beforeOccurrence:change["from_revision_occurrence_id"].string,afterOccurrence:change["to_revision_occurrence_id"].string,beforeSheet:change["from_sheet_id"].string,afterSheet:change["to_sheet_id"].string)
            let eligibility=workbookFieldDiffEligibility(change:change,before:before,after:after,scope:scope)
            for field in ["formula","value"] {
                let diff=workbookFieldTextDiff(before:before,after:after,field:field,textOffset:0,eligibility:eligibility)
                let expected=item["eligible_field"].string==field
                let caption=workbookFieldCaption(change:change,before:before,after:after,field:field,textOffset:0,scope:scope)
                if item["name"].string=="stored_value-value",field=="formula" {try require(caption == .notAsserted,"OrdinaryUnchangedFormulaInventedUncertainty")}
                if item["name"].string=="formula-formula",field=="value" {try require(caption == .notAsserted,"OrdinarySavedValueInventedUncertainty")}
                if item["name"].string=="cross-format-cell_observation",field=="value" {try require(caption == .withheld,"CrossFormatObservationMislabelledFormulaOrCacheIssue")}
                try require(diff?.semantic==expected,"SelectedEngineEventEligibilityMismatch_"+item["name"].string+"_"+field)
                if !expected {try require(diff?.lines.allSatisfy({$0.prefix.isEmpty})==true,"WithheldEngineFieldColoredAsEdit")}
            }
        }
        let golden=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))))["cases"].array
        try require(golden.count>=38,"SharedPresentationCasesMissing")
        for item in golden {
            let scope=item["scope"],before=item["before"],after=item["after"]
            let current=WorkbookSelectedEventScope(beforeOccurrence:scope["before_occurrence"].string,afterOccurrence:scope["after_occurrence"].string,beforeSheet:scope["before_sheet"].string,afterSheet:scope["after_sheet"].string)
            let eligibility=workbookFieldDiffEligibility(change:item["change"],before:before,after:after,scope:current)
            for field in ["value","formula"] {
                let diff=workbookFieldTextDiff(before:before,after:after,field:field,textOffset:item["text_offset"].int,eligibility:eligibility)
                try require((diff?.semantic ?? false)==item["expected_"+field+"_eligible"].bool,"SharedEligibility_"+item["name"].string+"_"+field)
            }
            try require(workbookRawField(before,field:"value").state.rawValue==item["expected_value_state_before"].string && workbookRawField(after,field:"value").state.rawValue==item["expected_value_state_after"].string,"SharedObservationStates_"+item["name"].string)
        }
        let shared=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))))
        try require(shared["caption_cases"].array.count>=27 && shared["observation_caption_cases"].array.count>=6,"SharedCaptionCasesMissing")
        for test in shared["caption_cases"].array {
            guard let item=golden.first(where:{$0["name"].string==test["case"].string}) else{throw NSError(domain:"CaptionFixtureReferenceMissing",code:1)}
            let scope=item["scope"],context=WorkbookSelectedEventScope(beforeOccurrence:scope["before_occurrence"].string,afterOccurrence:scope["after_occurrence"].string,beforeSheet:scope["before_sheet"].string,afterSheet:scope["after_sheet"].string)
            let actual=workbookFieldCaption(change:item["change"],before:item["before"],after:item["after"],field:test["field"].string,textOffset:item["text_offset"].int,scope:context)
            try require(actual.rawValue==test["expected_gate"].string,"SharedCaptionGate_"+test["name"].string+"_actual_"+actual.rawValue)
        }
        for test in shared["observation_caption_cases"].array {try require(workbookObservationCaptionKey(cell:test["cell"],field:test["field"].string)==test["expected_observation_key"].string,"SharedObservationCaption_"+test["name"].string)}
        guard let eligible=golden.first(where:{$0["name"].string=="eligible-stored-value"}) else{throw NSError(domain:"EligibleFieldFixtureMissing",code:1)}
        var unknownBefore=eligible["before"].dictionary,unknownAfter=eligible["after"].dictionary;unknownBefore["value_type"]="future_unsupported_type";unknownAfter["value_type"]="future_unsupported_type"
        let unknownScope=eligible["scope"],unknownContext=WorkbookSelectedEventScope(beforeOccurrence:unknownScope["before_occurrence"].string,afterOccurrence:unknownScope["after_occurrence"].string,beforeSheet:unknownScope["before_sheet"].string,afterSheet:unknownScope["after_sheet"].string)
        try require(workbookFieldDiffEligibility(change:eligible["change"],before:JSON(unknownBefore),after:JSON(unknownAfter),scope:unknownContext) == .neutral && workbookFieldCaption(change:eligible["change"],before:JSON(unknownBefore),after:JSON(unknownAfter),field:"value",textOffset:0,scope:unknownContext) == .valueType,"SyntheticUnsupportedValueTypeClaimedSemanticEdit")
        let multiline=String(repeating:"x\n",count:129)
        var longOld=eligible["before"].dictionary,longNew=eligible["after"].dictionary
        for old in [true,false] {var cell=old ? longOld:longNew,metadata=JSON(cell["text_continuations"] ?? [:]).dictionary;let text=multiline+(old ? "100":"120");cell["value"]=text;metadata["value"]=["state":"complete","offset":0,"total_length":text.utf16.count,"next_offset":NSNull()];cell["text_continuations"]=metadata;if old{longOld=cell}else{longNew=cell}}
        let longScope=eligible["scope"],longContext=WorkbookSelectedEventScope(beforeOccurrence:longScope["before_occurrence"].string,afterOccurrence:longScope["after_occurrence"].string,beforeSheet:longScope["before_sheet"].string,afterSheet:longScope["after_sheet"].string)
        let longCaption=workbookFieldCaption(change:eligible["change"],before:JSON(longOld),after:JSON(longNew),field:"value",textOffset:0,scope:longContext),longDiff=workbookFieldTextDiff(before:JSON(longOld),after:JSON(longNew),field:"value",textOffset:0,eligibility:.storedValue)
        try require(longCaption == .compared && longDiff?.bounded==false && workbookFieldShowsRaw(caption:longCaption,diff:longDiff) && workbookRawField(JSON(longOld),field:"value").text?.utf16.elementsEqual((multiline+"100").utf16)==true,"DiffLineBudgetSuppressedCompleteRawObservations")
        let sharedWarnings=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))))["warning_cases"].array
        try require(sharedWarnings.count>=9,"SharedWarningCasesMissing")
        for item in sharedWarnings {try require(workbookSelectedWarningKeys(item["cell"])==item["expected_warning_keys"].array.map(\.string),"SharedWarningPolicy_"+item["name"].string)}
        var absentFormula=newValue.dictionary;absentFormula["formula"]=NSNull();absentFormula["text_continuations"]=["formula":["state":"missing","offset":0,"total_length":0,"next_offset":NSNull()]]
        let captionScope=WorkbookSelectedEventScope(beforeOccurrence:"a",afterOccurrence:"b",beforeSheet:"sa",afterSheet:"sb")
        try require(workbookFieldCaption(change:JSON(),before:JSON(absentFormula),after:JSON(absentFormula),field:"formula",textOffset:0,scope:captionScope) == .missing,"AbsentFormulaMislabelledPartialFragment")
        try require(workbookFieldCaption(change:JSON(),before:partial,after:newValue,field:"value",textOffset:0,scope:captionScope) == .fragment,"PartialFragmentLostTypedCaption")
        let neutralArrow=unifiedTextDiff(before:"raw source",after:"other raw source",semantic:false)
        try require(!neutralArrow.lines.contains(where:{$0.text=="→"}),"UIAnnotationInsertedIntoVerbatimSource")
        let observedTextWithInferredPage=JSON(["kind":"text_modified","text_assessment":"observed","lineage":["status":"inferred","reasons":["normalized_text_bigrams"]]])
        let context=documentSelectedContext(observedTextWithInferredPage)
        try require(context.contains(where:{$0.category == .pageCorrespondence && $0.status=="inferred" && $0.reasons==["normalized_text_bigrams"]}) && context.contains(where:{$0.category == .textAssessment && $0.status=="observed"}) && !context.contains(where:{$0.category == .regionCorrespondence}),"PageAndTextAssessmentWereConflated")
        let needsReview=JSON(["lineage":["status":"needs_review","reasons":["competing_duplicate_or_split_merge_candidate"]],"text_assessment":"observed","region_pairing_assessment":"inferred","appearance_assessment":"observed"])
        let reviewContext=documentSelectedContext(needsReview)
        try require(Set(reviewContext.map{$0.category.rawValue}).count==4 && reviewContext.first?.reasons==["competing_duplicate_or_split_merge_candidate"],"SeparateSelectedAssessmentsOrLineageReasonsLost")

        let fresh=WorkspaceLayoutStore(scope:.document),bookLayout=WorkspaceLayoutStore(scope:.workbook)
        for value in [fresh.configuration,bookLayout.configuration] {try require(!value.sidebarVisible && !value.inspectorVisible && value.changesVisible && value.changesDock == .left,"FreshWorkspaceNotSourceFirst")}
        var previous=WorkspaceLayoutConfiguration();previous.sidebarVisible=true;previous.inspectorVisible=true;previous.changesDock = .bottom;previous.sidebarWidth=299;previous.changesHeight=211
        let savedID=UUID(),legacy:[String:Any]=["schemaVersion":1,"current":try JSONSerialization.jsonObject(with:JSONEncoder().encode(previous)),"saved":[["id":savedID.uuidString,"name":"My old layout","configuration":try JSONSerialization.jsonObject(with:JSONEncoder().encode(previous))]]]
        let legacyData=try JSONSerialization.data(withJSONObject:legacy)
        WorkspaceLayoutPreferences.save(legacyData,scope:.document)
        let retained=WorkspaceLayoutStore(scope:.document)
        try require(retained.configuration==previous && retained.saved.count==1 && retained.saved[0].name=="My old layout" && retained.saved[0].configuration==previous && WorkspaceLayoutPreferences.data(.document)==legacyData,"ExistingCustomLayoutWasMigratedDestructively")
        retained.apply(.balanced);try require(retained.configuration.sidebarVisible && retained.configuration.changesDock == .bottom && retained.configuration.changesWidth==320,"BalancedPresetLostOriginalGeometry")
        let balancedBook=WorkspaceLayoutConfiguration.preset(.balanced,scope:.workbook);try require(balancedBook.sidebarVisible && balancedBook.inspectorVisible && balancedBook.changesDock == .bottom,"WorkbookBalancedPresetLostOriginalGeometry")
        retained.reset();try require(retained.configuration==fresh.configuration && retained.saved.count==1,"SourceFirstResetDeletedSavedLayouts")
        retained.setFocus(true)
        try require(!retained.configuration.changesVisible && !retained.configuration.inspectorVisible && documentSelectedContext(needsReview)==reviewContext,"FocusDiscardedSelectedCorrespondenceContext")

        let model=AppModel();model.initializing=false
        let revisions=(0..<3).map {index in JSON(["revision_occurrence_id":"occ_\(index)","label":"version \(index)","assets":[["asset_id":"asset_\(index)","format":"pdf"]],"pages":[["page_id":"page_\(index)","asset_id":"asset_\(index)","page":1],["page_id":"manual_\(index)","asset_id":"asset_\(index)","page":2]]])}
        model.report=JSON(["report_id":"rpt_fixed","revisions":revisions.map(\.raw)]);model.projectID="prj_fixed";model.from=0;model.to=2;model.tab="history"
        let changes=(0..<2).map{index in JSON(["change_id":"change_\(index)","kind":"text_modified","from_occurrence":"occ_\(index)","to_occurrence":"occ_\(index+1)","before":index==0 ? "100":"120","after":index==0 ? "120":"100","evidence":[["revision_occurrence_id":"occ_\(index)","page_id":"page_\(index)"],["revision_occurrence_id":"occ_\(index+1)","page_id":"page_\(index+1)"]]])}
        model.changes=changes;let rows=try JSON(changes.map(\.raw)).data(),report=try model.report.data()
        model.chooseChange("change_1")
        try require(model.from==0 && model.to==2 && model.tab=="history" && model.sourceFrom==1 && model.sourceTo==2 && model.leftPageID=="page_1" && model.rightPageID=="page_2" && model.eventInsideQuery && !model.loadingChanges,"HistorySelectionReplacedQueryOrWrongEvidence")
        model.navigatePage("manual_1",in:"occ_1");model.selectEvidence();try require(model.manuallyBrowsing && model.leftPageID=="manual_1","ManualHistoryViewportWasOverwritten")
        model.from=1;model.to=1;model.selectEvidence();try require(!model.manuallyBrowsing,"EqualEndpointsKeptManualPairAnchor")
        model.from=0;model.to=2;model.selectedChangeID="change_1";model.selectEvidence();try require(model.leftPageID=="page_1","LeavingSourcePairRevivedOldManualPage")
        model.returnToChange();try require(!model.manuallyBrowsing && model.leftPageID=="page_1","ReturnToSelectedChangeLostEvidence")
        model.stepChange(-1);try require(model.selectedChangeID=="change_0" && model.sourceFrom==0 && model.sourceTo==1 && model.from==0 && model.to==2,"PreviousChangeResetInterval")
        model.search="120";model.stepChange(1);try require(model.selectedChangeID=="change_1","FilteredNextChangeFailed")
        try require(try JSON(model.changes.map(\.raw)).data()==rows && model.report.data()==report,"NavigationChangedFixedReportOrRows")
        model.changes.append(JSON(["change_id":"foreign","from_occurrence":"unknown","to_occurrence":"occ_2"]))
        model.chooseChange("foreign");try require(model.selected.isNull && model.leftPageID.isEmpty && model.rightPageID.isEmpty && !model.evidenceWarning.isEmpty && model.from==0 && model.to==2,"UnknownHistoryEvidenceKeptStaleSource")
        try require(model.unselectedChangeMessage==model.evidenceWarning && model.unselectedChangeMessage != L("doc.changes.filteredNone"),"RejectedHistoryEventClaimedFilteredEmpty")
        model.evidenceWarning="";try require(model.unselectedChangeMessage==L("doc.tail.change.selectPrompt"),"PopulatedUnselectedListLackedNeutralPrompt")
        model.from=1;model.to=2;model.selectEvidence();try require(model.leftPageID=="page_1" && model.rightPageID=="page_2","NewIntervalKeptRejectedEventBlankPages")
        model.selectedChangeID=nil;model.leftPageID="stale";model.rightPageID="stale";model.evidenceWarning="Page unavailable";model.selectEvidence();try require(model.leftPageID=="page_1" && model.rightPageID=="page_2","OrdinaryWarningPreventedPageNormalization")
        model.diffMode="text";model.selectVersion(0);try require(model.effectiveDiffMode=="source" && model.diffMode=="source","DocumentVersionMenuKeptTextOverlay")
        try await model.updateChanges();try require(model.readingSingleVersion && model.changes.isEmpty && model.leftPageID=="page_0","SingleVersionReadRequestedDiff")
        model.from=0;model.to=2;model.diffMode="text";model.from=1;model.to=1
        try require(model.effectiveDiffMode=="source","EqualEndpointsDidNotImmediatelyShowSource")
        try await model.updateChanges();try require(model.diffMode=="source" && model.leftPageID=="page_1","DocumentEndpointPickerKeptTextOverlay")
        model.setDiffMode("text");try require(model.effectiveDiffMode=="source" && model.diffMode=="source","SingleDocumentReadAllowedTextPicker")
        // Mount the production persistent context and complete detail, including
        // a valid 1998-UTF16 human reason that previously painted over controls.
        _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let reason=String(repeating:"x\n",count:999),canonicalReason="e\u{301} · é"
        var longChange=changes[0].dictionary;longChange["lineage"]=["status":"human_confirmed","reasons":[reason,canonicalReason]];longChange["text_assessment"]="observed";longChange["region_pairing_assessment"]="inferred";longChange["appearance_assessment"]="observed"
        let contextModel=AppModel();contextModel.report=model.report;contextModel.projectID=model.projectID;contextModel.changes=[JSON(longChange)];contextModel.selectedChangeID="change_0";contextModel.from=0;contextModel.to=2;contextModel.tab="history"
        retained.setFocus(true)
        let contextWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
        contextWindow.isReleasedWhenClosed=false
        contextWindow.contentView=NSHostingView(rootView:VStack(spacing:0){Text("Query interval").frame(height:28).background(WorkspaceLayoutMarker(name:"probe.context.query"));SelectedChangeContext().environmentObject(contextModel);Color.clear.frame(maxHeight:.infinity).background(WorkspaceLayoutMarker(name:"probe.context.source"))})
        contextWindow.orderFront(nil);try await Task.sleep(nanoseconds:150_000_000);contextWindow.contentView?.layoutSubtreeIfNeeded()
        guard let contextRoot=contextWindow.contentView,
              let contextMarker=workspaceLayoutMarkers(in:contextRoot).first(where:{$0.identifier?.rawValue=="Reviset.document.selectedContext"}),
              let queryMarker=workspaceLayoutMarkers(in:contextRoot).first(where:{$0.identifier?.rawValue=="probe.context.query"}),
              let sourceMarker=workspaceLayoutMarkers(in:contextRoot).first(where:{$0.identifier?.rawValue=="probe.context.source"}) else{throw NSError(domain:"ContextGeometryMarkersMissing",code:1)}
        let contextRect=contextMarker.convert(contextMarker.bounds,to:contextRoot),queryRect=queryMarker.convert(queryMarker.bounds,to:contextRoot),sourceRect=sourceMarker.convert(sourceMarker.bounds,to:contextRoot)
        try require(contextRect.height>=46 && contextRect.height<=140 && (!contextRect.intersects(queryRect) || contextRect.intersection(queryRect).height<=1) && (!contextRect.intersects(sourceRect) || contextRect.intersection(sourceRect).height<=1) && sourceRect.height>400,"LongReasonEscapedPersistentContextGeometry_\(contextRect)_query_\(queryRect)_source_\(sourceRect)")
        let detailWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:400),styleMask:[.titled],backing:.buffered,defer:false)
        detailWindow.isReleasedWhenClosed=false;detailWindow.contentView=NSHostingView(rootView:SelectedChangeContextDetails().environmentObject(contextModel))
        detailWindow.orderFront(nil);try await Task.sleep(nanoseconds:150_000_000);detailWindow.contentView?.layoutSubtreeIfNeeded()
        func textReaders(_ view:NSView)->[NSTextView] {(view as? NSTextView).map{[$0]} ?? view.subviews.flatMap{textReaders($0)}}
        guard let reader=detailWindow.contentView.flatMap({textReaders($0).first(where:{$0.string.utf16.elementsEqual(reason.utf16)})}),let reasonScroll=reader.enclosingScrollView else{throw NSError(domain:"ExactFullReasonReaderMissing",code:1)}
        try require(!reader.isEditable && reader.isSelectable && reasonScroll.hasVerticalScroller && reader.bounds.height>reasonScroll.contentSize.height && reader.accessibilityIdentifier()=="Reviset.document.rawContextReasons","FullReasonNotAccessibleScrollableVerbatim")
        try require(documentSelectedContext(contextModel.selected).first?.reasons.first?.utf16.elementsEqual(reason.utf16)==true && reason.utf16.count==1998,"HumanReasonWasNormalizedOrTruncated")
        let contextEvidence:[String:Any]=["scope":"actual production SelectedChangeContext and native full-reason reader; synthetic valid human reason in Focus","summary_height":Double(contextRect.height),"query_height":Double(queryRect.height),"source_height":Double(sourceRect.height),"reason_utf16_count":reason.utf16.count,"full_reader_utf16":Array(reader.string.utf16).map(Int.init),"expected_utf16":Array(reason.utf16).map(Int.init),"reader_height":Double(reader.bounds.height),"reader_viewport_height":Double(reasonScroll.contentSize.height),"reader_selectable":reader.isSelectable,"reader_editable":reader.isEditable,"details_independent_of_focus_panels":retained.isFocused]
        if let userData=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:contextEvidence,options:[.sortedKeys]).write(to:URL(fileURLWithPath:userData).appendingPathComponent("context-geometry.json"))}
        detailWindow.close();contextWindow.close()
        try await checkOneBasedPager()
        try await checkGridSourceAndHiddenInput()
        try await checkHiddenSourceHeaders()
        try await checkReviewRefinements()
        print("CHECK source33 document CTA and controlled dismissal complete");fflush(stdout)
        guard let sheetEvent=engineCases.first(where:{$0["change"]["kind"].string=="date_system"}) else{throw NSError(domain:"ActualEngineSheetEventMissing",code:1)}
        try await checkSource16Presentation(sheetEvent["change"])
        try await checkNeutralObservationHosting(eligible)
        try await checkOneSidedSheetReads()
        guard let formatCase=golden.first(where:{$0["name"].string=="neutral-number-format-observation"}) else{throw NSError(domain:"NeutralNumberFormatFixtureMissing",code:1)}
        try await checkRawFieldHosting(change:eligible["change"],before:JSON(longOld),after:JSON(longNew),format:formatCase)
        let workbook=WorkbookModel(bridge:model.bridge);await workbook.start();workbook.projectID="workbook";workbook.reportID="workbook_report";workbook.report=JSON(["report_id":"workbook_report","revisions":[["revision_occurrence_id":"w0","index":0,"sheets":[]],["revision_occurrence_id":"w1","index":1,"sheets":[]]]]);workbook.beforeID="w0";workbook.afterID="w1";workbook.changesFromID="w0";workbook.changesToID="w1"
        workbook.diffMode="text";await workbook.selectVersion("w0");try require(workbook.diffMode=="source" && workbook.effectiveDiffMode=="source","WorkbookVersionMenuKeptTextOverlay")
        try require(workbook.beforeID=="w0" && workbook.afterID=="w0" && workbook.changesFromID=="w0" && workbook.changesToID=="w0" && workbook.changes.isEmpty && !workbook.loadingChanges && workbook.changesFailure.isEmpty,"WorkbookFirstVersionDidNotReadSingleSource")
        workbook.beforeID="w0";workbook.afterID="w1";workbook.changesFromID="w0";workbook.changesToID="w1";workbook.diffMode="text"
        await workbook.changeVersions(before:"w0",after:"w0");try require(workbook.diffMode=="source" && workbook.effectiveDiffMode=="source" && workbook.beforeID==workbook.afterID,"WorkbookEndpointPickerKeptTextOverlay")
        workbook.setDiffMode("text");try require(workbook.diffMode=="source","SingleWorkbookReadAllowedTextPicker")
        try require(workbook.changeListProvenance==L("git.reading"),"EqualWorkbookEndpointsClaimedComparedEvents")
        try await checkWorkbookReadingGuidance(workbook)
        print("CHECK source33 workbook CTA and controlled dismissal complete");fflush(stdout)
        try await checkImportMinimumSubmission()
        print("CHECK source33 import submission boundaries complete");fflush(stdout)
        let reportProjection=documentReportDetails(JSON(["coverage_gap_count":750,"coverage_gaps":(0..<500).map{["reason":"gap_\($0)"]},"quality_counts":["ocr_inferred_pages":3,"ocr_failed_pages":1,"pptx_without_render":4,"unknown_future_key":999]]))
        try require(reportProjection.totalCoverageGaps==750 && reportProjection.gaps.count==50 && reportProjection.coverageTruncated && reportProjection.gaps.first?["reason"].string=="gap_0" && reportProjection.gaps.last?["reason"].string=="gap_49","ReportLimitProjectionLostCountOrBound")
        try require(reportProjection.quality.contains(DocumentReportQualityCount(key:"ocr_inferred_pages",count:3)) && reportProjection.quality.count==3,"ReportQualityProjectionLostKnownCounts")
        print("PASS native Git diff workspace: bounded exact Unicode diff, neutral appearance/unavailable/topology, Source First defaults, old custom layouts retained, query/event/manual navigation separation, previous/next, unknown evidence guard, document/workbook v1 reading")
    }
    @MainActor static func checkOneBasedPager()async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        let model=AppModel();model.initializing=false;model.from=0;model.to=0;model.leftPageID="pager-page"
        func report(_ occurrence:String,pages:[[String:Any]])->JSON {JSON(["report_id":"pager-fixed-report","revisions":[["revision_occurrence_id":occurrence,"label":"Pager source","assets":[],"pages":pages]]])}
        let pages:[[String:Any]]=[["page_id":"pager-page","page":1],["page_id":"pager-second","page":2]]
        model.report=report("pager-occurrence",pages:[])
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:650),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:PageColumnProbeHarness(model:model));window.orderFront(nil)
        defer{window.close()}
        func settle()async throws {try await Task.sleep(nanoseconds:100_000_000);window.contentView?.layoutSubtreeIfNeeded()}
        func fields(_ view:NSView)->[NSTextField] {(view as? NSTextField).map{[$0]} ?? view.subviews.flatMap{fields($0)}}
        try await settle()
        guard let field=window.contentView.flatMap({fields($0).first(where:{$0.isEditable})}) else{throw NSError(domain:"ActualNativePagerFieldMissing",code:1)}
        try require(field.stringValue.isEmpty,"UnavailablePageInventedZero_"+field.stringValue)
        model.report=report("pager-occurrence",pages:pages);try await settle()
        try require(field.stringValue=="1","LateQualifiedSourceDidNotResyncPager_"+field.stringValue)
        guard let picker=window.contentView.flatMap({pageColumnControlObservations(in:$0).first(where:{$0.identifier?.rawValue=="Reviset.document.pagePicker.pager-occurrence"})}),let action=field.action else{throw NSError(domain:"EvaluatedPickerBindingOrNativeSubmitActionMissing",code:1)}
        try require(picker.selection==model.leftPageID && picker.title.hasPrefix("p.1 · "),"EvaluatedPickerDisagreedWithQualifiedPager")
        for invalid in ["not-a-page","0","99"] {
            field.stringValue=invalid;field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))
            model.zoom=1.5;try await settle()
            try require(field.stringValue==invalid,"UnchangedSourceOverwroteEditDraft")
            field.sendAction(action,to:field.target);try await settle()
            try require(field.stringValue=="1" && model.leftPageID=="pager-page","InvalidSubmitDidNotRestoreQualifiedPage_"+field.stringValue)
        }
        field.stringValue="2";field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field));field.sendAction(action,to:field.target);try await settle()
        try require(model.leftPageID=="pager-second" && field.stringValue=="2" && picker.selection==model.leftPageID && picker.title.hasPrefix("p.2 · "),"ValidNativeSubmitDidNotNavigateSelectedSource")
        model.navigatePage("pager-page",in:"pager-occurrence");try await settle()
        let changedPages:[[String:Any]]=[["page_id":"pager-other","page":1],["page_id":"pager-page","page":2]]
        model.report=report("another-occurrence",pages:changedPages);try await settle()
        try require(field.stringValue=="2","ReusedSourceRevisionKeptOldPager_"+field.stringValue)
        try require(window.contentView.map{fields($0).contains(where:{$0===field})}==true,"PagerQualificationRecreatedNativeControl")
        let preferences=LanguagePreferences.shared,previousLanguage=LanguagePreferences.shared.selection
        defer{preferences.selection=previousLanguage}
        let guidanceModel=AppModel();guidanceModel.initializing=false
        guidanceModel.report=JSON(["report_id":"guidance-fixed","revisions":(0..<3).map{["revision_occurrence_id":"guidance-\($0)","pages":[["page_id":"guidance-page-\($0)","page":1]]]}])
        var messageObservations:[[String:Any]]=[]
        for language in [UILanguage.en,.ko] {
            preferences.selection=language
            for mode in ["compare","history"] {
                guidanceModel.tab=mode;guidanceModel.diffMode="text";guidanceModel.selectVersion(0);try await guidanceModel.updateChanges()
                try require(guidanceModel.revisions.count==3 && guidanceModel.readingSingleVersion && guidanceModel.changes.isEmpty && guidanceModel.emptyChangesMessage==L("git.singleVersionChanges") && guidanceModel.emptyChangesMessage != L("doc.changes.needRevisions"),"VersionMenuReadingGuidanceWrong_"+language.rawValue+"_"+mode)
                messageObservations.append(["language":language.rawValue,"mode":mode,"route":"version_menu_v1","message":guidanceModel.emptyChangesMessage,"revision_count":guidanceModel.revisions.count])
                guidanceModel.from=1;guidanceModel.to=1;guidanceModel.diffMode="text";try await guidanceModel.updateChanges()
                try require(guidanceModel.readingSingleVersion && guidanceModel.changes.isEmpty && guidanceModel.emptyChangesMessage==L("git.singleVersionChanges") && guidanceModel.emptyChangesMessage != L("doc.changes.needRevisions"),"EqualEndpointReadingGuidanceWrong_"+language.rawValue+"_"+mode)
                messageObservations.append(["language":language.rawValue,"mode":mode,"route":"equal_query_endpoints","message":guidanceModel.emptyChangesMessage,"revision_count":guidanceModel.revisions.count])
            }
        }
        for language in [UILanguage.en,.ko] {
            preferences.selection=language
            guidanceModel.report=JSON(["report_id":"one-revision","revisions":[["revision_occurrence_id":"only","pages":[]]]]);guidanceModel.from=0;guidanceModel.to=0
            try await guidanceModel.updateChanges();try require(guidanceModel.emptyChangesMessage==L("doc.changes.needRevisions"),"OneRevisionOfferedImpossibleVersionPick_"+language.rawValue)
        }
        let proof:[String:Any]=["scope":"actual retained native PageColumn edit field and evaluated SwiftUI picker binding; synthetic late page/reused occurrence, native submit actions, actual AppModel routes in English/Korean","initial_unavailable_blank":true,"late_qualified_page":1,"reused_occurrence_page":2,"native_field_identity_preserved":true,"draft_preserved_until_submit":true,"invalid_submits_restore_current_page":true,"valid_submit_updates_source_and_picker":true,"message_observations":messageObservations]
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("pager-proof.json"))}
    }

    @MainActor static func checkGridSourceAndHiddenInput()async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        let compactFacts=try await checkCompactGridWidths()
        let raw="stored only; not recalculated"
        let preview=String(repeating:"p",count:64),literalEllipsis="literal… source"
        let cells=[JSON(["address":"D4","row":4,"column":4,"value":raw,"value_type":"string","formula":"SUM(C1)","formula_interpretation":"explicit","cached_result":"present","text_truncated":true,"source_lengths":["value":raw.utf16.count]]),JSON(["address":"E4","row":4,"column":5,"value":literalEllipsis,"value_type":"string","formula":NSNull(),"text_truncated":false,"source_lengths":["value":literalEllipsis.utf16.count]]),JSON(["address":"F4","row":4,"column":6,"value":preview,"value_type":"string","formula":NSNull(),"cached_result":"not_applicable","text_truncated":true,"source_lengths":["value":200]])]
        var gutterSelections:[[Int]]=[],throwAwayPending=false
        func source(_ enabled:Bool)->WorkbookGrid {WorkbookGrid(keyboardEnabled:enabled,language:"en",pane:"source-probe",revealIntent:"fixed",cells:cells,rowStart:4,columnStart:4,rowCount:10,columnCount:12,selectedRow:4,selectedColumn:4,onSelect:{gutterSelections.append([$0,$1])})}
        let host=NSHostingView(rootView:source(true)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:300),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()}
        func settle()async throws {try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()}
        func tables(_ view:NSView)->[NSTableView] {(view as? NSTableView).map{[$0]} ?? view.subviews.flatMap{tables($0)}}
        try await settle()
        guard let table=tables(host).first,let cell=table.view(atColumn:1,row:0,makeIfNecessary:true) as? NSTableCellView,let text=cell.textField,let scroll=table.enclosingScrollView else{throw NSError(domain:"ActualGridSourceCellMissing",code:1)}
        try require(text.stringValue==raw && cell.toolTip?.contains(raw)==true,"RawStoredValueReplacedOrMissingFromTooltip")
        cell.layoutSubtreeIfNeeded()
        let annotations=cell.subviews.compactMap{$0 as? NSTextField}.filter{$0 !== text}
        try require(annotations.count==1 && annotations[0].stringValue=="ƒ · …" && annotations[0].frame.maxX<=text.frame.minX+0.5,"FormulaAndPartialMarkersWerePrependedToRawValue_\(annotations.map{($0.stringValue,$0.frame)})_raw_\(text.frame)")
        try require(text.maximumNumberOfLines==1 && text.lineBreakMode == .byTruncatingTail && cell.layer?.masksToBounds==true && text.frame.minX>=2 && text.frame.maxX<=cell.bounds.maxX-2,"RawGridCellNotSingleLineClippedPadded_lines_\(text.maximumNumberOfLines)_mode_\(text.lineBreakMode.rawValue)_clip_\(String(describing:cell.layer?.masksToBounds))_text_\(text.frame)_cell_\(cell.bounds)")
        guard let previewCell=table.view(atColumn:3,row:0,makeIfNecessary:true) as? NSTableCellView,let previewText=previewCell.textField,let previewAX=previewText.accessibilityValue() else{throw NSError(domain:"LongGridPreviewCellMissing",code:1)}
        let previewAnnotations=previewCell.subviews.compactMap{$0 as? NSTextField}.filter{$0 !== previewText}
        try require(previewText.stringValue.utf16.elementsEqual(preview.utf16) && previewText.stringValue.utf16.count==64 && previewAX.utf16.elementsEqual(preview.utf16) && previewAnnotations.count==1 && previewAnnotations[0].stringValue=="…","PartialGridPreviewMixedQualifierIntoExactRawFieldOrAXValue")
        let previewNativeUTF16=previewText.stringValue.utf16.count,previewAnnotation=previewAnnotations[0].stringValue
        try require(previewCell.toolTip?.contains(L("git.savedValuePreview"))==true && previewCell.toolTip?.contains(L("git.gridPreviewRoute"))==true && previewCell.toolTip?.contains(preview)==true,"BoundedGridPreviewClaimedCompleteSavedValue")
        guard let literalCell=table.view(atColumn:2,row:0,makeIfNecessary:true) as? NSTableCellView,let literalText=literalCell.textField else{throw NSError(domain:"LiteralEllipsisGridCellMissing",code:1)}
        try require(literalText.stringValue.utf16.elementsEqual(literalEllipsis.utf16) && literalCell.subviews.compactMap{$0 as? NSTextField}.filter{$0 !== literalText}.allSatisfy{$0.stringValue.isEmpty},"AuthoredSourceEllipsisWasTreatedAsPartialQualifier")
        guard let pinned=scroll as? WorkbookTableScrollView else{throw NSError(domain:"PinnedRowGutterScrollMissing",code:1)}
        scroll.contentView.scroll(to:NSPoint(x:330,y:0));scroll.reflectScrolledClipView(scroll.contentView);try await settle()
        guard let rowLabel=pinned.pinnedRowLabel(4) else{throw NSError(domain:"PinnedPhysicalRowLabelMissing",code:1)}
        let rowCenter=table.convert(table.rect(ofRow:0),to:nil).midY,labelCenter=rowLabel.convert(rowLabel.bounds,to:nil).midY
        try require(!rowLabel.isHiddenOrHasHiddenAncestor && !rowLabel.visibleRect.isEmpty && rowLabel.stringValue=="4" && abs(rowCenter-labelCenter)<1 && table.visibleRect.intersection(table.rect(ofColumn:0)).isEmpty,"HorizontalScrollLostPinnedPhysicalRowIdentity")
        let gutter=pinned.pinnedRowGutter,point=NSPoint(x:gutter.frame.midX,y:gutter.frame.midY)
        try require(!gutter.acceptsFirstResponder && !gutter.canBecomeKeyView && gutter.hitTest(point)===gutter,"PinnedGutterAcquiredFocusOrForwardedCoveredCellHit")
        guard let nextRow=pinned.pinnedRowLabel(5),let click=NSEvent.mouseEvent(with:.leftMouseDown,location:nextRow.convert(NSPoint(x:nextRow.bounds.midX,y:nextRow.bounds.midY),to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1) else{throw NSError(domain:"PinnedRowClickFixtureMissing",code:1)}
        pinned.pendingCellDetailsReveal={_ in throwAwayPending=true;return true}
        gutter.mouseDown(with:click)
        try require(gutterSelections==[[5,4]] && pinned.pendingCellDetailsReveal==nil && !throwAwayPending,"PinnedRowClickDidNotUsePhysicalRowCurrentColumnOwnerAction")
        guard let header=table.headerView else{throw NSError(domain:"PinnedGridHeaderMissing",code:1)}
        var headerAlignmentError:CGFloat=0
        for column in table.tableColumns.indices {let body=table.convert(table.rect(ofColumn:column),to:nil),title=header.convert(header.headerRect(ofColumn:column),to:nil);headerAlignmentError=max(headerAlignmentError,abs(body.minX-title.minX),abs(body.maxX-title.maxX))}
        try require(headerAlignmentError<1,"PinnedRowsChangedActualHeaderBodyAlignment")
        let coordinator=table.dataSource as AnyObject?,origin=scroll.contentView.bounds.origin,selected=table.selectedRow
        try require(window.makeFirstResponder(table),"VisibleGridCouldNotTakeFocus")
        host.rootView=source(false);try await settle()
        try require(tables(host).first===table && (table.dataSource as AnyObject?)===coordinator && table.selectedRow==selected && scroll.contentView.bounds.origin==origin,"HiddenInputGateChangedGridHostOrViewport")
        try require(!table.acceptsFirstResponder && !table.canBecomeKeyView && table.isAccessibilityHidden(),"HiddenGridGateAbsent")
        try require(gutter.isAccessibilityHidden() && !gutter.acceptsFirstResponder && !gutter.canBecomeKeyView,"HiddenPinnedGutterEscapedSourceInputGate")
        gutter.mouseDown(with:click);try require(gutterSelections==[[5,4]],"HiddenPinnedRowClickSelectedPhysicalSource")
        _ = window.makeFirstResponder(table)
        if let responder=window.firstResponder as? NSView {try require(responder !== table && !responder.isDescendant(of:table),"HiddenGridAllowedReacquisition")}
        for _ in 0..<12 {window.selectNextKeyView(nil);if let responder=window.firstResponder as? NSView {try require(responder !== table && !responder.isDescendant(of:table),"NativeTraversalEnteredHiddenGrid")}}
        host.rootView=source(true);try await settle();try require(!table.isAccessibilityHidden() && window.makeFirstResponder(table),"SourceGridGateDidNotRestore")
        let proof:[String:Any]=["scope":"controlled native WorkbookGrid; raw fixture literal, clipping and public AppKit responder/traversal/AX properties; no OS Full Keyboard Access or VoiceOver claim","raw_value":raw,"raw_utf16":Array(raw.utf16).map(Int.init),"full_saved_value_in_tooltip":true,"single_line_clipping_padding_verified":true,"partial_preview_returned_utf16":64,"partial_preview_source_total_utf16":200,"partial_native_field_utf16":previewNativeUTF16,"partial_native_ax_value_utf16":previewAX.utf16.count,"partial_raw_field_and_ax_exact":true,"partial_secondary_annotation":previewAnnotation,"literal_source_ellipsis_preserved":true,"pinned_row_label_visible_after_horizontal_scroll":true,"pinned_row_label_physical_row":4,"pinned_row_label_vertical_alignment_error":abs(rowCenter-labelCenter),"header_body_alignment_error_after_horizontal_scroll":headerAlignmentError,"pinned_gutter_blocks_covered_cell_hits_and_focus":true,"pinned_gutter_hidden_source_ax_gate":true,"actual_gutter_mouse_down_selected_physical_row_and_current_column":[5,4],"hidden_gutter_mouse_down_blocked":true,"row_click_cancels_pending_reveal":true,"retained_host_coordinator_viewport_selection":true,"hidden_reacquisition_rejected":true,"native_next_keyview_steps":12,"source_restore_verified":true,"source27_compact_defaults_and_native_resize":compactFacts]
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("grid-source-proof.json"))}
    }

    @MainActor static func checkCompactGridWidths()async throws->[String:Any] {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        let cells=(1...5).flatMap {column in [JSON(["address":WorkbookGrid.address(1,column),"row":1,"column":column,"value":["Category","Details","Price","Qty","Amount"][column-1],"value_type":"string","formula":NSNull()]),JSON(["address":WorkbookGrid.address(2,column),"row":2,"column":column,"value":["Category","Description","125","6","750"][column-1],"value_type":column<3 ? "string":"number","formula":NSNull()])]}
        func source(_ language:String="en",_ identity:String="project|report|occurrence|sheet")->WorkbookGrid {WorkbookGrid(sourceIdentity:identity,language:language,pane:"compact",revealIntent:"fixed",cells:cells,rowStart:1,columnStart:1,rowCount:100,columnCount:5,selectedRow:2,selectedColumn:3,onSelect:{_,_ in})}
        let host=NSHostingView(rootView:source()),window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:300),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()}
        func settle()async throws {try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()}
        try await settle()
        guard let table=views(host).compactMap({$0 as? NSTableView}).first,let owner=table.dataSource as? WorkbookGrid.Coordinator,let scroll=table.enclosingScrollView else{throw NSError(domain:"CompactActualNativeGridMissing",code:1)}
        let widths=table.tableColumns.dropFirst().map(\.width),available=scroll.contentView.bounds.width,last=table.rect(ofColumn:5)
        try require(widths.count==5 && widths[0]>=96 && widths[1]>=96 && widths[2]<widths[0] && widths[2]>=64 && last.maxX<=available+0.5,"CompactDefaultsDidNotShowRepresentativeFiveColumns_widths_\(widths)_last_\(last)_available_\(available)")
        table.tableColumns[1].width=241;try await settle()
        // Match the production 100-row viewport. A 10-row document shorter than
        // this window makes AppKit clamp negative origins as the window grows;
        // that geometry cannot represent a retained manual scroll position.
        let manual=NSPoint(x:40,y:56)
        scroll.contentView.scroll(to:manual);scroll.reflectScrolledClipView(scroll.contentView)
        try require(scroll.contentView.bounds.origin==manual && table.bounds.height>scroll.contentView.bounds.height+manual.y && table.bounds.width>scroll.contentView.bounds.width+manual.x,"CompactManualViewportFixtureOutsideNativeScrollableBounds")
        let columns=table.tableColumns,origin=scroll.contentView.bounds.origin,selected=table.selectedRow
        func geometry()->[String:String] {["clip_bounds":NSStringFromRect(scroll.contentView.bounds),"clip_frame":NSStringFromRect(scroll.contentView.frame),"document_bounds":NSStringFromRect(table.bounds),"document_frame":NSStringFromRect(table.frame)]}
        let manualBeforeGeometry=geometry()
        host.rootView=source("ko");try await settle()
        window.setContentSize(NSSize(width:460,height:320));try await settle()
        let manualAfterGeometry=geometry(),manualAfterOrigin=scroll.contentView.bounds.origin
        try require(table.tableColumns[1].width==241 && zip(columns,table.tableColumns).allSatisfy{$0 === $1} && table.dataSource as? WorkbookGrid.Coordinator === owner && table.selectedRow==selected && scroll.contentView.bounds.origin==origin,"ExplicitNativeColumnResizeLostOnSameSourceRefreshOrPassiveResize_widths_\(table.tableColumns.map(\.width))_columnsRetained_\(zip(columns,table.tableColumns).map{$0 === $1})_coordinatorRetained_\(table.dataSource as? WorkbookGrid.Coordinator === owner)_selection_\(selected)_actual_\(table.selectedRow)_origin_\(origin)_actual_\(scroll.contentView.bounds.origin)_clip_\(scroll.contentView.frame)_table_\(table.frame)")
        host.rootView=source("ko","project|report|other-occurrence|sheet");try await settle()
        try require(table.tableColumns[1].width==widths[0],"UserWidthLeakedIntoDifferentPhysicalSource")
        host.rootView=source();try await settle()
        try require(table.tableColumns[1].width==241,"UserWidthLostWhenReturningToSamePhysicalSource")
        guard let field=(table.view(atColumn:3,row:1,makeIfNecessary:true) as? NSTableCellView)?.textField else{throw NSError(domain:"CompactGridNativeSourceMissing",code:1)}
        try require(field.stringValue.utf16.elementsEqual("125".utf16),"CompactWidthReformattedRawValue")
        let badgeRaw="badge raw content",badge=JSON(["row":2,"column":1,"address":"A2","value":badgeRaw,"value_type":"string","formula":"UNRESOLVED","formula_interpretation":"unresolved","cached_result":"missing","text_truncated":true,"source_lengths":["value":300]])
        host.rootView=WorkbookGrid(sourceIdentity:"badge-source",language:"en",pane:"compact",revealIntent:"badge",cells:[badge],rowStart:1,columnStart:1,rowCount:100,columnCount:1,selectedRow:0,selectedColumn:0,onSelect:{_,_ in});try await settle()
        guard let badgeCell=table.view(atColumn:1,row:1,makeIfNecessary:true) as? NSTableCellView,let badgeField=badgeCell.textField,let annotation=badgeCell.subviews.compactMap({$0 as? NSTextField}).first(where:{$0 !== badgeField}) else{throw NSError(domain:"CompactMultiFlagNativeSourceMissing",code:1)}
        badgeCell.layoutSubtreeIfNeeded()
        let badgeReserved=badgeField.frame.minX-6,badgeExpected=min(180,max(96,ceil((badgeRaw as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width+16+badgeReserved))),badgeActual=table.tableColumns[1].width
        try require(annotation.stringValue=="?ƒ · ∅ · …" && badgeReserved>36 && badgeReserved<=48 && abs(badgeActual-badgeExpected)<0.5 && badgeField.stringValue.utf16.elementsEqual(badgeRaw.utf16),"CompactDefaultWidthDidNotReserveActualNativeBadgeOrChangedRaw_width_\(badgeActual)_expected_\(badgeExpected)_reserved_\(badgeReserved)")
        return ["scope":"controlled production native WorkbookGrid at 580pt, five observed source columns; public AppKit resize notification, retained table and coordinator; no whole-corpus auto-fit claim","default_widths":widths.map(Double.init),"available_content_width":Double(available),"last_column_max_x":Double(last.maxX),"all_five_representative_columns_visible":true,"explicit_resized_width":241,"row_count_matches_production":100,"retained_manual_origin":[Double(origin.x),Double(origin.y)],"actual_after_passive_origin":[Double(manualAfterOrigin.x),Double(manualAfterOrigin.y)],"native_geometry_before_passive":manualBeforeGeometry,"native_geometry_after_passive":manualAfterGeometry,"document_height":Double(table.bounds.height),"resized_viewport_height":Double(scroll.contentView.bounds.height),"same_source_locale_refresh_and_passive_window_resize_preserve_width_and_origin":true,"different_source_default_and_returned_source_preference_verified":true,"raw_source_utf16_exact":true,"source30_badge_reserved_width":Double(badgeReserved),"source30_badge_column_width":Double(badgeActual),"source30_badge_expected_width":Double(badgeExpected),"source30_badge_raw_utf16_exact":true]
    }

    @MainActor static func checkWorkbookReadingGuidance(_ model:WorkbookModel)async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        let languages=LanguagePreferences.shared,previous=LanguagePreferences.shared.selection
        defer{languages.selection=previous;model.importPresented=false}
        let revisions:[[String:Any]]=[["revision_occurrence_id":"w0","index":0,"sheets":[]],["revision_occurrence_id":"w1","index":1,"sheets":[]]]
        let host=NSHostingView(rootView:SoleWorkbookImportProbeHarness(model:model)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:220),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()}
        func settle()async throws {try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()}
        func guidance(_ view:NSView)->WorkbookEmptyGuidanceView? {(view as? WorkbookEmptyGuidanceView) ?? view.subviews.lazy.compactMap{guidance($0)}.first}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        func importContent()async throws->NSView {for _ in 0..<50 {if let content=window.sheets.first?.contentView,views(content).compactMap({$0 as? NSTextField}).contains(where:{$0.isEditable && $0.placeholderString==L("workbook.import.projectName")}){return content};try await Task.sleep(nanoseconds:10_000_000)};throw NSError(domain:"WorkbookComparisonImportSheetMissing",code:1)}
        var observations:[[String:Any]]=[]
        for language in [UILanguage.en,.ko] {
            languages.selection=language
            model.report=JSON(["report_id":"workbook_report","revisions":revisions]);model.beforeID="w0";model.afterID="w1";model.changesFromID="w0";model.changesToID="w1"
            model.diffMode="text";await model.selectVersion("w0");try await settle()
            guard let view=guidance(host) else{throw NSError(domain:"ActualWorkbookEmptyGuidanceMissing",code:1)}
            func observe(_ route:String,_ expected:String,_ count:Int)throws {
                try require(view.message.stringValue==expected && view.message.stringValue != L("workbook.changes.empty") && !view.message.isHiddenOrHasHiddenAncestor && !view.message.visibleRect.isEmpty,"WorkbookSingleReadVisibleMessageWrong_"+language.rawValue+"_"+route)
                try require(model.effectiveDiffMode=="source" && model.changes.isEmpty,"WorkbookReadingGuideNotOriginalSingleSource")
                observations.append(["language":language.rawValue,"route":route,"revision_count":count,"native_visible_message":view.message.stringValue,"native_message_field_verified":true,"effective_mode":model.effectiveDiffMode])
            }
            try require(model.emptyChangesKind == .singleRead && view.importButton.isHidden,"ExistingVersionsOfferedNewTimelineInsteadOfDistinctEndpoints")
            try observe("version_menu_v1",L("git.singleVersionChanges"),2)
            model.beforeID="w0";model.afterID="w1";model.changesFromID="w0";model.changesToID="w1";model.diffMode="text";await model.changeVersions(before:"w0",after:"w0");try await settle()
            try observe("equal_query_endpoints",L("git.singleVersionChanges"),2)
            model.report=JSON(["report_id":"workbook_report","revisions":[revisions[0]]]);model.diffMode="text";await model.changeVersions(before:"w0",after:"w0");try await settle()
            try require(model.emptyChangesKind == .additionalVersion && !view.importButton.isHidden && view.importButton.isEnabled,"OneWorkbookVersionLackedReachableNewComparison")
            try observe("one_imported_version",L("git.workbookNeedVersions"),1)
            let report=try model.report.data(),before=try model.beforeCell.data(),after=try model.afterCell.data()
            view.importButton.performClick(nil);try require(model.importPresented,"NativeNewComparisonDidNotReachExistingImportRoute")
            let comparisonSheet=try await importContent()
            try require(model.importIntent == .newComparison && model.importIntent.minimumVersionEntries==2 && views(comparisonSheet).compactMap({$0 as? NSTextField}).contains(where:{$0.isEditable}),"ActualWorkbookComparisonSheetLostCapturedMinimum")
            try require(try model.report.data()==report && model.beforeCell.data()==before && model.afterCell.data()==after,"OpeningNewComparisonMutatedReadingReportOrRawCells")
            model.importPresented=false
            for _ in 0..<50 {if window.sheets.isEmpty{break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(!model.importPresented && model.importIntent == .ordinary && window.sheets.isEmpty,"WorkbookCancelKeptComparisonMinimum")
            model.importPresented=true;let ordinarySheet=try await importContent()
            try require(model.importIntent == .ordinary && model.importIntent.minimumVersionEntries==1 && !views(ordinarySheet).compactMap({$0 as? NSTextField}).filter({$0.isEditable}).isEmpty,"OrdinaryWorkbookReopenInheritedComparisonGuidance")
            model.importPresented=false
            for _ in 0..<50 {if window.sheets.isEmpty{break};try await Task.sleep(nanoseconds:10_000_000)}
            // The query owns the list: a manually equal source pair must not
            // replace a distinct query's truthful empty comparison message.
            model.report=JSON(["report_id":"workbook_report","revisions":revisions]);model.changesFromID="w0";model.changesToID="w1";try await settle()
            try require(model.beforeID==model.afterID && model.emptyChangesKind == .noChanges && view.message.stringValue==L("workbook.changes.empty") && view.importButton.isHidden,"WorkbookEmptyCopyFollowedSourcesInsteadOfQuery")
        }
        let proof:[String:Any]=["scope":"production workbook reading model routes and actual visible native guidance fields/button in synthetic NSHostingView; existing import route reached without submitting a new timeline; no OS gestures","observations":observations,"native_new_comparison_action_reached":true,"report_and_raw_cells_unchanged_by_action":true]
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("workbook-reading-proof.json"))}
    }

    @MainActor static func checkImportMinimumSubmission()async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        guard let originalRoot=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] else{throw NSError(domain:"ImportMinimumIsolatedRootMissing",code:1)}
        let root=URL(fileURLWithPath:originalRoot).appendingPathComponent("import-minimum"),library=root.appendingPathComponent("library")
        try FileManager.default.createDirectory(at:library,withIntermediateDirectories:true)
        try JSON(["mode":"import-gate"]).data().write(to:library.appendingPathComponent("control.json"))
        let pdf=root.appendingPathComponent("source.pdf"),pptx=root.appendingPathComponent("source.pptx"),csv=root.appendingPathComponent("source.csv")
        for url in [pdf,pptx,csv] {try Data("isolated fixture bytes\n".utf8).write(to:url)}
        let originals=try [pdf,pptx,csv].map{try ImportFileIdentity.capture($0)}
        var bundled=[try ImportRow.selected(pptx),try ImportRow.selected(pdf)]
        try require(ImportRow.group(&bundled,at:1) && bundled.count==1 && bundled[0].members.count==2,"ImportMinimumBundleFixtureNotOneVersion")
        let single=try ImportRow.selected(pdf),second=try ImportRow.selected(pdf),workbookRow=try WorkbookImportRow.selected(csv),secondWorkbookRow=try WorkbookImportRow.selected(csv)
        setenv("DOCVER_TEST_USER_DATA",root.path,1);let document=AppModel();setenv("DOCVER_TEST_USER_DATA",originalRoot,1)
        document.initializing=false;document.projectID="fixed-document";document.report=JSON(["report_id":"fixed-document-report","revisions":[["revision_occurrence_id":"sole","pages":[]]]]);document.leftPageID="retained-page";document.rightPageID="retained-page";document.loadingChanges=true
        let workbook=WorkbookModel(bridge:document.bridge);await workbook.start()
        workbook.projectID="fixed-workbook";workbook.reportID="fixed-workbook-report";workbook.report=JSON(["report_id":"fixed-workbook-report","revisions":[["revision_occurrence_id":"sole","sheets":[]]]]);workbook.beforeID="sole";workbook.afterID="sole";workbook.beforeCell=JSON(["value":"é\r\ne\u{301}"]);workbook.afterCell=JSON(["value":"raw\n"]);workbook.loadingRange=true
        let docReport=try document.report.data(),workbookReport=try workbook.report.data(),rawBefore=try workbook.beforeCell.data(),rawAfter=try workbook.afterCell.data(),events=library.appendingPathComponent("read-events.jsonl"),beforeEvents=try Data(contentsOf:events)
        var rejected=0
        for rows in [[single],bundled,[]] {
            do{_ = try await document.create(title:"rejected",rows:rows,intent:rows.isEmpty ? .ordinary:.newComparison);throw NSError(domain:"DocumentMinimumSubmitted",code:1)}
            catch let error as BridgeError {try require(error.code=="IMPORT_VERSION_MINIMUM","DocumentMinimumWrongFailure");rejected += 1}
        }
        for rows in [[workbookRow],[]] {
            do{try await workbook.create(title:"rejected",rows:rows,intent:rows.isEmpty ? .ordinary:.newComparison);throw NSError(domain:"WorkbookMinimumSubmitted",code:1)}
            catch let error as BridgeError {try require(error.code=="IMPORT_VERSION_MINIMUM","WorkbookMinimumWrongFailure");rejected += 1}
        }
        try require(try Data(contentsOf:events)==beforeEvents && document.report.data()==docReport && workbook.report.data()==workbookReport && workbook.beforeCell.data()==rawBefore && workbook.afterCell.data()==rawAfter && document.leftPageID=="retained-page" && document.rightPageID=="retained-page" && document.loadingChanges && workbook.loadingRange && !workbook.busy,"MinimumRejectionChangedSourceOrCancelledReadsOrReachedBackend")
        print("CHECK source33 five rejected entries kept Bridge untouched");fflush(stdout)
        let preferences=LanguagePreferences.shared,previous=preferences.selection
        defer{preferences.selection=previous}
        var mountedDrafts:[[String:Any]]=[]
        for language in [UILanguage.en,.ko] {
            preferences.selection=language
            // Capture while the comparison route is open, then dismiss before
            // mounting: the dialog's intent must not follow the reset model.
            document.openNewComparisonImport();let capturedDocument=ImportView(intent:document.importIntent,initialRows:bundled).environmentObject(document);document.importSheet=false
            workbook.loadingRange=false;workbook.openNewComparisonImport();let capturedWorkbook=WorkbookImportSheet(model:workbook,intent:workbook.importIntent,initialRows:[workbookRow]);workbook.importPresented=false
            let cases:[(String,AnyView,Int,Int)]=[
                ("document_bundle_one",AnyView(capturedDocument),1,2),
                ("document_comparison_two",AnyView(ImportView(intent:.newComparison,initialRows:[single,second]).environmentObject(document)),2,2),
                ("document_ordinary_one",AnyView(ImportView(intent:document.importIntent,initialRows:[single]).environmentObject(document)),1,1),
                ("workbook_comparison_one",AnyView(capturedWorkbook),1,2),
                ("workbook_comparison_two",AnyView(WorkbookImportSheet(model:workbook,intent:.newComparison,initialRows:[workbookRow,secondWorkbookRow])),2,2),
                ("workbook_ordinary_one",AnyView(WorkbookImportSheet(model:workbook,intent:workbook.importIntent,initialRows:[workbookRow])),1,1)
            ]
            for (name,view,entries,minimum) in cases {
                let host=NSHostingView(rootView:view),window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:650),styleMask:[.titled],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil)
                try await Task.sleep(nanoseconds:60_000_000);host.layoutSubtreeIfNeeded()
                let editable=views(host).compactMap{$0 as? NSTextField}.filter{$0.isEditable}
                try require(editable.count==entries+1 && editable.allSatisfy{!$0.visibleRect.isEmpty},"ImportMinimumMountedVersionEntriesWrong_"+name+"_"+language.rawValue+"_fields_\(editable.map(\.stringValue))")
                mountedDrafts.append(["language":language.rawValue,"route":name,"version_entry_count":entries,"captured_route_minimum":minimum,"native_editable_field_count":editable.count]);window.close()
            }
            print("CHECK source33 mounted import drafts "+language.rawValue);fflush(stdout)
        }
        document.loadingChanges=false
        let comparison=try await document.create(title:"document-two",rows:[single,second],intent:.newComparison)
        try require(comparison["project_id"].string=="fixture-created-create","DocumentTwoEntriesDidNotReachBackend")
        _ = try await document.create(title:"document-one",rows:[single])
        print("CHECK source33 document accepted submissions reached controlled Bridge");fflush(stdout)
        try await workbook.create(title:"workbook-two",rows:[workbookRow,secondWorkbookRow],intent:.newComparison)
        try await workbook.create(title:"workbook-one",rows:[workbookRow])
        print("CHECK source33 workbook accepted submissions reached controlled Bridge");fflush(stdout)
        let records=String(data:try Data(contentsOf:events),encoding:.utf8)!.split(separator:"\n").map{JSON(try! JSONSerialization.jsonObject(with:Data($0.utf8)))}
        let submissions=records.filter{["create","workbookCreate"].contains($0["action"].string)}
        try require(submissions.map{$0["query"]["revisions"].array.count}==[2,1,2,1] && submissions.map{$0["query"]["title"].string}==["document-two","document-one","workbook-two","workbook-one"],"CapturedIntentLostActualSubmittedEntryCounts")
        try require(try [pdf,pptx,csv].map{try ImportFileIdentity.capture($0)}==originals,"ImportMinimumChangedOriginalBytes")
        // Reuse the existing fresh reading proof; this adds source33 facts from
        // this invocation without changing any prior round's evidence.
        let proofURL=URL(fileURLWithPath:originalRoot).appendingPathComponent("workbook-reading-proof.json")
        var proof=try JSONSerialization.jsonObject(with:Data(contentsOf:proofURL)) as! [String:Any]
        proof["source33_import_minimum"]=["scope":"actual production model handlers and mounted production sheet drafts; isolated controlled bridge acceptance, no real document parsing or OS input. SwiftUI submit enabled/press state is not observable in this in-process probe; the production disabled binding is source-audited.","rejected_before_any_bridge_call":rejected,"rejection_keeps_raw_report_and_read_ownership":true,"bundle_member_count":2,"bundle_version_entry_count":1,"mounted_drafts":mountedDrafts,"native_submit_enabled_observation":NSNull(),"native_submit_press_observation":NSNull(),"submitted_version_entry_counts":submissions.map{$0["query"]["revisions"].array.count},"original_bytes_unchanged":true]
        try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:proofURL)
    }

    @MainActor static func checkHiddenSourceHeaders()async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        func settle(_ window:NSWindow)async throws {try await Task.sleep(nanoseconds:100_000_000);window.contentView?.layoutSubtreeIfNeeded()}
        func window<Content:View>(_ content:Content)->NSWindow {let result=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled],backing:.buffered,defer:false);result.isReleasedWhenClosed=false;result.contentView=NSHostingView(rootView:content);result.orderFront(nil);return result}
        let language=LanguagePreferences.shared,previous=LanguagePreferences.shared.selection
        defer{language.selection=previous}
        var facts:[[String:Any]]=[]
        for locale in [UILanguage.en,.ko] {
            language.selection=locale
            let title="편집용 {0} % café 👨‍👩‍👧‍👦"
            let identityHost=NSHostingView(rootView:NativeWorkspaceIdentity(name:"probe.identity",title:title,reportID:"")),identityWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:40),styleMask:[.titled],backing:.buffered,defer:false);identityWindow.isReleasedWhenClosed=false;identityWindow.contentView=identityHost;identityWindow.orderFront(nil);try await settle(identityWindow)
            guard let identityField=views(identityHost).compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="probe.identity"}) else{throw NSError(domain:"EmptyReportNativeIdentityMissing",code:1)}
            try require(identityField.stringValue.utf16.elementsEqual(title.utf16) && identityField.toolTip?.utf16.elementsEqual(title.utf16)==true && (identityField.accessibilityHelp() ?? "").isEmpty,"EmptyReportIdentityInventedReportTooltipOrAXHelp")
            identityHost.rootView=NativeWorkspaceIdentity(name:"probe.identity",title:title,reportID:"identity-report");try await settle(identityWindow)
            try require(views(identityHost).contains{$0===identityField} && identityField.toolTip==title+"\n"+L("git.reportChip",.verbatim("identity-report")) && identityField.accessibilityHelp()==L("git.reportChip",.verbatim("identity-report")),"PopulatedReportIdentityLostSecondaryLiteralReportHelp")
            identityHost.rootView=NativeWorkspaceIdentity(name:"probe.identity",title:title,reportID:"");try await settle(identityWindow)
            try require(views(identityHost).contains{$0===identityField} && identityField.toolTip?.utf16.elementsEqual(title.utf16)==true && (identityField.accessibilityHelp() ?? "").isEmpty,"ClearedReportIdentityKeptStaleAXHelp")
            identityWindow.close()
            let document=AppModel();document.initializing=false;document.projectID="header-project";document.projects=[JSON(["project_id":document.projectID,"title":title])];document.zoom=1.5
            document.report=JSON(["report_id":"header-fixed","revisions":(0..<2).map{i in ["revision_occurrence_id":"header-o\(i)","label":"v\(i+1)","assets":[],"pages":[["page_id":"header-p\(i)","page":1],["page_id":"header-next\(i)","page":2]]]}]);document.from=0;document.to=1;document.leftPageID="header-p0";document.rightPageID="header-p1"
            let exactReason="Observed source é / e\u{301}\nFull reason stays selectable."
            document.changes=[JSON(["change_id":"header-change","kind":"text_modified","from_occurrence":"header-o0","to_occurrence":"header-o1","before":"100","after":"120","lineage":["status":"needs_review","reasons":[exactReason]],"evidence":[["revision_occurrence_id":"header-o0","page_id":"header-p0"],["revision_occurrence_id":"header-o1","page_id":"header-p1"]]])];document.selectedChangeID="header-change"
            let layout=WorkspaceLayoutStore(scope:.document),docWindow=window(VStack(spacing:0){ReportBar();CompareWorkspace()}.environmentObject(document).environmentObject(layout))
            try await settle(docWindow)
            guard let docRoot=docWindow.contentView else{throw NSError(domain:"HeaderDocumentRootMissing",code:1)}
            guard let documentTitle=views(docRoot).compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="Reviset.document.projectTitle"}) else{throw NSError(domain:"DocumentPrimaryProjectIdentityMissing",code:1)}
            try require(documentTitle.stringValue.utf16.elementsEqual(title.utf16) && documentTitle.accessibilityLabel()?.utf16.elementsEqual(title.utf16)==true && documentTitle.toolTip?.contains("header-fixed")==true && !documentTitle.visibleRect.isEmpty,"DocumentProjectIdentityNotLiteralVisibleOrReportHashUnavailable_"+locale.rawValue)
            let fields=views(docRoot).compactMap{$0 as? NSTextField}.filter{$0.isEditable && $0.stringValue=="1"}
            let controls=pageColumnControlObservations(in:docRoot)
            try require(fields.count==2 && controls.filter{$0.identifier?.rawValue.contains("pagePicker")==true}.count==2,"NativePageHeadersMissing")
            guard let field=fields.first else{throw NSError(domain:"NativePageEntryMissing",code:1)}
            try require(fields.allSatisfy{$0.isEnabled} && controls.allSatisfy{$0.contentEnabled} && docWindow.makeFirstResponder(field) && field.currentEditor() === docWindow.firstResponder,"VisiblePageHeaderCouldNotOwnNativeEditor")
            let fixed=try document.report.data(),source=[document.leftPageID,document.rightPageID],query=[document.from,document.to]
            document.diffMode="text";try await settle(docWindow)
            try require(fields.allSatisfy{!$0.isEnabled && !$0.acceptsFirstResponder && !$0.canBecomeKeyView && $0.currentEditor()==nil} && controls.allSatisfy{!$0.contentEnabled},"InvisiblePageHeaderKeptKeyboardAuthority")
            _ = docWindow.makeFirstResponder(field)
            try require(field.currentEditor()==nil,"InvisiblePageHeaderReacquiredNativeEditor")
            for reverse in [false,true] {for _ in 0..<12 {if reverse{docWindow.selectPreviousKeyView(nil)}else{docWindow.selectNextKeyView(nil)};try require(fields.allSatisfy{$0.currentEditor()==nil},"NativeTraversalEnteredInvisiblePageHeader")}}
            // Repeat the original native-editor attack only if an editor could
            // still be acquired. Disabled retained headers must offer none.
            if let editor=field.currentEditor() as? NSTextView {editor.selectAll(nil);editor.insertText("2",replacementRange:editor.selectedRange());editor.insertNewline(nil)}
            try await settle(docWindow)
            let overlay=workspaceLayoutMarkers(in:docRoot).first{$0.identifier?.rawValue=="Reviset.document.unifiedDiff"}
            let diffLines=workspaceLayoutMarkers(in:docRoot).filter{$0.identifier?.rawValue.hasPrefix("Reviset.document.diffLine.")==true}
            try require(overlay?.contentEnabled==true && !diffLines.isEmpty && diffLines.allSatisfy{$0.contentEnabled},"OriginalDisableLeakedIntoTextDiffOverlay")
            let details=window(SelectedChangeContextDetails().environmentObject(document));try await settle(details)
            guard let reader=details.contentView.flatMap({views($0).compactMap{$0 as? NSTextView}.first(where:{$0.string.utf16.elementsEqual(exactReason.utf16)})}) else{throw NSError(domain:"FullReasonReaderMissingInTextMode",code:1)}
            try require(reader.isSelectable && !reader.isEditable && details.makeFirstResponder(reader),"FullReasonReaderDisabledWithOriginalSource");reader.selectAll(nil);try require(reader.selectedRange().length==exactReason.utf16.count,"FullReasonReaderLostExactSelectableText")
            details.close();document.diffMode="source";try await settle(docWindow)
            try require(fields.allSatisfy{$0.isEnabled} && controls.allSatisfy{$0.contentEnabled} && fields.allSatisfy{old in views(docRoot).contains{$0===old}} && document.zoom==1.5 && [document.leftPageID,document.rightPageID]==source && [document.from,document.to]==query && (try document.report.data())==fixed,"HeaderModeGateRebuiltControlsOrChangedSource")
            facts.append(["workspace":"document","language":locale.rawValue,"actual_native_page_entries":fields.count,"native_editor_retired":true,"hidden_reacquisition_rejected":true,"local_next_previous_steps":24,"evaluated_page_picker_and_pager_disabled":true,"text_overlay_enabled":true,"exact_full_reason_reader_selectable":true,"report_query_source_zoom_and_header_identity_retained":true,"literal_primary_project_title_visible":true,"source30_empty_and_cleared_report_help_omitted_in_retained_native_identity":true,"primary_project_title_utf16":Array(documentTitle.stringValue.utf16).map(Int.init),"report_hash_secondary_help":true]);docWindow.close()

            let workbook=WorkbookModel(bridge:document.bridge);workbook.projectID="header-workbook";workbook.reportID="header-workbook-report";workbook.projects=[JSON(["project_id":workbook.projectID,"title":title])]
            workbook.report=JSON(["report_id":workbook.reportID,"revisions":(0..<2).map{i in ["revision_occurrence_id":"book-o\(i)","index":i,"sheets":[["sheet_id":"book-s\(i)","name":"Sheet \(i)","row_count":10,"column_count":3],["sheet_id":"other-s\(i)","name":"Other","row_count":10,"column_count":3]]]}]);workbook.beforeID="book-o0";workbook.afterID="book-o1";workbook.beforeSheetID="book-s0";workbook.afterSheetID="book-s1";workbook.changesFromID=workbook.beforeID;workbook.changesToID=workbook.afterID
            let bookWindow=window(WorkbookWorkspace(model:workbook));try await settle(bookWindow)
            guard let bookRoot=bookWindow.contentView else{throw NSError(domain:"WorkbookHeaderRootMissing",code:1)}
            guard let workbookTitle=views(bookRoot).compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.projectTitle"}) else{throw NSError(domain:"WorkbookPrimaryProjectIdentityMissing",code:1)}
            try require(workbookTitle.stringValue.utf16.elementsEqual(title.utf16) && workbookTitle.accessibilityLabel()?.utf16.elementsEqual(title.utf16)==true && workbookTitle.toolTip?.contains(workbook.reportID)==true && !workbookTitle.visibleRect.isEmpty,"WorkbookProjectIdentityNotLiteralVisibleOrReportHashUnavailable_"+locale.rawValue)
            let sheets=workspaceLayoutMarkers(in:bookRoot).filter{$0.identifier?.rawValue.hasPrefix("Reviset.workbook.sheetPicker.")==true},tables=views(bookRoot).compactMap{$0 as? NSTableView}
            try require(sheets.count==2 && sheets.allSatisfy{$0.contentEnabled} && tables.count==2,"ProductionWorkbookSheetHeadersNotMounted")
            let bookFixed=try workbook.report.data(),bookSource=[workbook.beforeID,workbook.afterID,workbook.beforeSheetID,workbook.afterSheetID],tableState=tables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds.origin,$0.selectedRow)}
            workbook.busy=true;try await settle(bookWindow);try require(sheets.allSatisfy{!$0.contentEnabled},"SheetPickerEnabledWhenWorkbookNotReady");workbook.busy=false
            workbook.loadingRange=true;try await settle(bookWindow);try require(sheets.allSatisfy{!$0.contentEnabled},"SheetPickerEnabledDuringRangeRead");workbook.loadingRange=false;try await settle(bookWindow)
            try require(bookWindow.makeFirstResponder(tables[0]),"VisibleWorkbookSourceCouldNotTakeFocus")
            workbook.diffMode="text";try await settle(bookWindow)
            try require(sheets.allSatisfy{!$0.contentEnabled} && tables.allSatisfy{!$0.acceptsFirstResponder && !$0.canBecomeKeyView},"HiddenWorkbookSheetOrGridStayedEnabled")
            try require(workspaceLayoutMarkers(in:bookRoot).first{$0.identifier?.rawValue=="Reviset.workbook.unifiedDiff"}?.contentEnabled==true,"WorkbookSourceDisableLeakedIntoTextOverlay")
            for reverse in [false,true] {for _ in 0..<12 {if reverse{bookWindow.selectPreviousKeyView(nil)}else{bookWindow.selectNextKeyView(nil)};if let responder=bookWindow.firstResponder as? NSView {try require(!tables.contains{responder === $0 || responder.isDescendant(of:$0)},"NativeTraversalEnteredHiddenWorkbookSource")}}}
            workbook.diffMode="source";try await settle(bookWindow)
            try require(sheets.allSatisfy{$0.contentEnabled} && bookSource==[workbook.beforeID,workbook.afterID,workbook.beforeSheetID,workbook.afterSheetID] && (try workbook.report.data())==bookFixed,"WorkbookHeaderGateChangedFixedSource")
            for (table,coordinator,origin,selected) in tableState {try require(views(bookRoot).contains{$0===table} && (table.dataSource as AnyObject?) === coordinator && table.enclosingScrollView!.contentView.bounds.origin==origin && table.selectedRow==selected,"WorkbookHeaderGateRebuiltGridOrMovedViewport")}
            workbook.inspectorVisible=true;try await settle(bookWindow)
            guard let inspector=views(bookRoot).compactMap({$0 as? NSSplitView}).first(where:{$0.identifier?.rawValue=="Reviset.workspace.workbook.inspector"}) else{throw NSError(domain:"WorkbookInspectorSplitMissing",code:1)}
            let inspectorFrames=inspector.arrangedSubviews.map(\.frame),gridOrigins=tables.map{$0.enclosingScrollView!.contentView.bounds.origin}
            workbook.tab="ai";try await settle(bookWindow)
            try require(inspector.arrangedSubviews.map(\.frame)==inspectorFrames && tables.map{$0.enclosingScrollView!.contentView.bounds.origin}==gridOrigins,"AIReportSheetCollapsedUnderlyingInspectorOrMovedSource")
            workbook.tab="compare";for _ in 0..<30 {if bookWindow.sheets.isEmpty{break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(bookWindow.sheets.isEmpty,"AIReportSheetDidNotDismissInProbe")
            facts.append(["workspace":"workbook","language":locale.rawValue,"evaluated_sheet_picker_environments":sheets.count,"hidden_sheet_pickers_disabled":true,"busy_and_range_loading_disable_sheet_pickers":true,"ai_sheet_preserves_inspector_frames_and_source_viewports":true,"text_overlay_enabled":true,"actual_native_grid_hosts":tables.count,"native_popup_views_in_closed_tree":views(bookRoot).compactMap{$0 as? NSPopUpButton}.count,"local_next_previous_steps":24,"source_report_grid_coordinator_viewport_selection_retained":true,"literal_primary_project_title_visible":true,"primary_project_title_utf16":Array(workbookTitle.stringValue.utf16).map(Int.init),"report_hash_secondary_help":true,"picker_proof_scope":"evaluated production Picker enabled environment; no native popup/OS AX activation claim"]);bookWindow.close()
        }
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:["scope":"production CompareWorkspace and WorkbookWorkspace in controlled native NSHostingViews; synthetic fixed reports, local AppKit responder/editor/traversal actions; no OS Full Keyboard Access or VoiceOver automation","observations":facts],options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("hidden-header-proof.json"))}
    }

    @MainActor static func checkReviewRefinements()async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        let preferences=LanguagePreferences.shared,previous=preferences.selection
        defer{preferences.selection=previous}
        preferences.selection = .en
        let exact="é / e\u{301}\r\n"+String(repeating:"raw reason\n",count:80),readerHost=NSHostingView(rootView:NativeVerbatimReasonReader(text:exact).environment(\.locale,Locale(identifier:"en_US")))
        let readerWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:200),styleMask:[.titled],backing:.buffered,defer:false);readerWindow.isReleasedWhenClosed=false;readerWindow.contentView=readerHost;readerWindow.orderFront(nil)
        preferences.selection = .en;try await Task.sleep(nanoseconds:100_000_000)
        guard let reader=views(readerHost).compactMap({$0 as? NSTextView}).first,let scroll=reader.enclosingScrollView else{throw NSError(domain:"ReviewReasonReaderMissing",code:1)}
        try require(reader.accessibilityLabel()==L("git.rawReasons"),"InitialReasonReaderLabelNotEnglish")
        reader.setSelectedRange(NSRange(location:7,length:11));scroll.contentView.scroll(to:NSPoint(x:0,y:80));scroll.reflectScrolledClipView(scroll.contentView)
        let selected=reader.selectedRange(),origin=scroll.contentView.bounds.origin
        preferences.selection = .ko;readerHost.rootView=NativeVerbatimReasonReader(text:exact).environment(\.locale,Locale(identifier:"ko_KR"));try await Task.sleep(nanoseconds:100_000_000)
        try require(reader.accessibilityLabel()==L("git.rawReasons") && reader.string.utf16.elementsEqual(exact.utf16) && reader.selectedRange()==selected && scroll.contentView.bounds.origin==origin && views(readerHost).contains{$0===reader},"ReasonAccessibilityLocaleRefreshChangedRawSelectionOrViewport");readerWindow.close()
        guard let originalRoot=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] else{throw NSError(domain:"IsolatedGuidanceLibraryMissing",code:1)}
        setenv("DOCVER_TEST_USER_DATA",originalRoot+"/sole-document-guidance",1);let model=AppModel();setenv("DOCVER_TEST_USER_DATA",originalRoot,1)
        try require(model.libraryAvailable,"IsolatedSoleDocumentLibraryNotAdmitted")
        model.initializing=false;model.projectID="review-guidance";model.report=JSON(["report_id":"review-fixed","revisions":[["revision_occurrence_id":"only","pages":[["page_id":"one-page","page":1]],"assets":[]]]]);model.from=0;model.to=0;model.leftPageID="one-page";model.rightPageID="one-page"
        let layout=WorkspaceLayoutStore(scope:.document),host=NSHostingView(rootView:CompareWorkspace().environmentObject(model).environmentObject(layout)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()}
        let actionHost=NSHostingView(rootView:SoleDocumentImportProbeHarness(model:model,layout:layout)),actionWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:360,height:600),styleMask:[.titled],backing:.buffered,defer:false);actionWindow.isReleasedWhenClosed=false;actionWindow.contentView=actionHost;actionWindow.orderFront(nil);defer{model.importSheet=false;for sheet in actionWindow.sheets{actionWindow.endSheet(sheet);sheet.orderOut(nil)};actionWindow.close()}
        var observations:[[String:Any]]=[]
        for language in [UILanguage.en,.ko] {
            preferences.selection=language;try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()
            guard let button=views(actionHost).compactMap({$0 as? NSButton}).first(where:{$0.identifier?.rawValue=="Reviset.document.newComparison"}) else{throw NSError(domain:"ActualSoleDocumentNewComparisonButtonMissing",code:1)}
            let fields=views(host).compactMap{$0 as? NSTextField}.filter{$0.isEditable}
            try require(button.isEnabled && !button.visibleRect.isEmpty && button.title==L("git.workbookNewComparison") && fields.count==1 && !views(host).contains{String(describing:type(of:$0)).contains("SegmentedControl")},"SoleImportKeptIrrelevantChangeFiltersOrEndpointMode")
            let fixed=try model.report.data(),source=[model.leftPageID,model.rightPageID],configuration=layout.configuration,nativeSources=views(host).filter{$0.identifier?.rawValue=="Docver.pdf.pane"};button.performClick(nil)
            for _ in 0..<50 {if let sheet=actionWindow.sheets.first,views(sheet.contentView!).compactMap({$0 as? NSTextField}).contains(where:{$0.isEditable && $0.placeholderString==L("doc.import.projectName")}){break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(model.importSheet,"SoleDocumentNativeImportActionDidNotOpen_target_\(String(describing:button.target))_action_\(String(describing:button.action))_library_\(model.libraryAvailable)_busy_\(model.busy)_loading_\(model.loading)_initializing_\(model.initializing)")
            try require(actionWindow.sheets.first?.contentView.map{views($0).compactMap{$0 as? NSTextField}.contains{$0.isEditable && $0.placeholderString==L("doc.import.projectName") && $0.stringValue==L("doc.import.defaultTitle")}}==true,"SoleDocumentActionDidNotMountExistingImportSheet")
            guard let comparisonSheet=actionWindow.sheets.first?.contentView else{throw NSError(domain:"ActualDocumentComparisonSheetMissing",code:1)}
            try require(model.importIntent == .newComparison && model.importIntent.minimumVersionEntries==2 && views(comparisonSheet).compactMap({$0 as? NSTextField}).contains(where:{$0.isEditable}),"ActualDocumentComparisonSheetLostCapturedMinimum")
            do {_ = try await model.create(title:"rejected comparison",rows:[ImportRow(label:"one",urls:[URL(fileURLWithPath:"/unsubmitted.pdf")])],intent:model.importIntent);throw NSError(domain:"MountedDocumentComparisonAcceptedOneEntry",code:1)}
            catch let error as BridgeError {try require(error.code=="IMPORT_VERSION_MINIMUM","MountedDocumentComparisonRejectedTooLate")}
            try require((try model.report.data())==fixed && source==[model.leftPageID,model.rightPageID],"SoleDocumentImportActionChangedFixedReportOrSource")
            model.importSheet=false
            for _ in 0..<50 {if actionWindow.sheets.isEmpty{break};try await Task.sleep(nanoseconds:10_000_000)};try require(actionWindow.sheets.isEmpty,"SoleDocumentImportSheetDidNotDismiss")
            try require(!model.importSheet && model.importIntent == .ordinary,"DocumentCancelKeptComparisonMinimum")
            model.importSheet=true
            for _ in 0..<50 {if let content=actionWindow.sheets.first?.contentView,views(content).compactMap({$0 as? NSTextField}).contains(where:{$0.isEditable && $0.placeholderString==L("doc.import.projectName")}){break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(model.importIntent.minimumVersionEntries==1 && actionWindow.sheets.first?.contentView != nil,"OrdinaryDocumentReopenInheritedComparisonMinimum")
            model.importSheet=false
            for _ in 0..<50 {if actionWindow.sheets.isEmpty{break};try await Task.sleep(nanoseconds:10_000_000)}
            try require((try model.report.data())==fixed && source==[model.leftPageID,model.rightPageID] && window.contentView === host && actionWindow.contentView === actionHost && layout.configuration==configuration && nativeSources.allSatisfy{sourceView in views(host).contains{$0===sourceView}},"DocumentRejectCancelOrOrdinaryReopenChangedFixedSourceHosts")
            observations.append(["language":language.rawValue,"native_new_comparison_button_action":true,"comparison_intent_minimum":2,"controlled_dismissal_resets_ordinary_intent":true,"ordinary_reopen_minimum":1,"only_source_page_field_remains":true,"no_segmented_query_mode":true,"fixed_report_and_source_unchanged":true])
        }
        model.report=JSON(["report_id":"review-fixed","revisions":(0..<3).map{["revision_occurrence_id":"review-\($0)","pages":[["page_id":"review-page-\($0)","page":1]],"assets":[]]}]);model.from=0;model.to=0;model.selectEvidence();try await Task.sleep(nanoseconds:100_000_000)
        try require(!views(host).compactMap({$0 as? NSButton}).contains{$0.identifier?.rawValue=="Reviset.document.newComparison"} && views(host).compactMap({$0 as? NSTextField}).filter{$0.isEditable}.count>=2,"MultiVersionEqualEndpointsLostQueryOrFilters")
        try require(model.changeListProvenance==L("git.reading"),"EqualDocumentEndpointsClaimedComparedEvents")
        model.to=1;try require(model.changeListProvenance==L("git.documentStoredAdjacent"),"AdjacentDocumentListClaimedComputedNet");model.to=2;try require(model.changeListProvenance==L("git.documentComputedNet"),"WiderDocumentListClaimedStoredEvents");model.tab="history";try require(model.changeListProvenance==L("git.documentStoredHistory"),"HistoryListProvenanceMissing")
        try require(documentReportTimestamp(JSON(["report_id":"fixed"]),reports:[JSON(["report_id":"other","created_at":"wrong"]),JSON(["report_id":"fixed","created_at":"2026-10-25T00:00:00Z"])])=="2026-10-25T00:00:00Z" && documentReportTimestamp(JSON(["report_id":"missing"]),reports:[]).isEmpty,"ReportDateNotBoundToActualMetadata")
        let gap=JSON(["revision_id":"revision-physical","page_id":"page-scoped","feature":"table boundaries","reason":"verbatim human reason"])
        try require(documentGapScope(gap)=="revision-physical · page-scoped" && documentGapScope(JSON(["page_id":"page-only"]))=="page-only" && selectedCoverageCaption(gap).contains("table boundaries"),"CoverageFeatureOrRevisionIdentityLost")
        let change=JSON(["before":"Revenue 120\nsource", "after":"Revenue 100\nsource"]),raw=try JSON(["before":"Revenue 120\nsource", "after":"Revenue 100\nsource"]).data()
        try require(documentChangeExcerpt(change).contains("Revenue 120") && documentChangeExcerpt(change).contains(" → Revenue 100") && (try change.data())==raw,"NavigationExcerptOmittedBeforeOrChangedCanonicalSource")
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:["scope":"actual native sole-document CTA, reason-reader accessibility label/selection/scroll; typed report/caption/provenance projections; synthetic fixed data, no submitted import or OS gestures","sole_document":observations,"reason_reader_locale_identity_selection_scroll_retained":true,"coverage_revision_feature_and_metadata_timestamp_verified":true,"before_after_navigation_excerpt_without_source_mutation":true],options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("review13-proof.json"))}
    }

    @MainActor static func checkOneSidedSheetReads()async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        guard let data=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"],let resource=ProcessInfo.processInfo.environment["DOCVER_TEST_ONE_SIDED_RESOURCES"] else{throw NSError(domain:"OneSidedFixtureEnvironmentMissing",code:1)}
        let root=URL(fileURLWithPath:data),library=root.appendingPathComponent("one-sided-library");try FileManager.default.createDirectory(at:library,withIntermediateDirectories:true)
        try JSON(["mode":"ok","value":"valid opposite source"]).data().write(to:library.appendingPathComponent("control.json"))
        let model=WorkbookModel(bridge:Bridge(resources:URL(fileURLWithPath:resource),library:library));await model.start();model.projectID="project";model.reportID="report";model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":"old"],["revision_occurrence_id":"new"]]]);model.beforeID="old";model.afterID="new";model.rowStart=2;model.columnStart=1
        let fixed=try model.report.data()
        model.beforeSheetID="";model.afterSheetID="sheet-new";await model.loadRange()
        try require(model.rangeFailure.isEmpty && model.beforeCells.isEmpty && model.afterCells.first?["value"].string=="valid opposite source","MissingBeforeSheetDiscardedAvailableAfterGrid")
        model.beforeSheetID="sheet-old";model.afterSheetID="";await model.loadRange()
        try require(model.rangeFailure.isEmpty && model.afterCells.isEmpty && model.beforeCells.first?["value"].string=="valid opposite source","MissingAfterSheetDiscardedAvailableBeforeGrid")
        model.beforeSheetID="";await model.loadRange();try require(model.rangeFailure.isEmpty && model.beforeCells.isEmpty && model.afterCells.isEmpty,"BothMissingSheetsBecameFailedQueries")
        let log=try String(contentsOf:library.appendingPathComponent("read-events.jsonl"),encoding:.utf8),requests=try log.split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}.filter{$0["action"].string=="workbookGrid"}
        try require(requests.count==2 && requests[0]["query"]["sheet_id"].string=="sheet-new" && requests[1]["query"]["sheet_id"].string=="sheet-old" && requests.allSatisfy{$0["query"]["project_id"].string=="project" && $0["query"]["report_id"].string=="report"} && (try model.report.data())==fixed,"OneSidedSheetQueryLostScopeOrCalledMissingPane")
        try JSONSerialization.data(withJSONObject:["scope":"production WorkbookModel.loadRange through isolated existing bridge fixture; no extraction or user navigation claim","valid_after_preserved":true,"valid_before_preserved":true,"both_missing_neutral":true,"grid_requests":requests.map(\.raw),"fixed_report_unchanged":true],options:[.sortedKeys]).write(to:root.appendingPathComponent("one-sided-proof.json"))
    }

    @MainActor static func checkRawFieldHosting(change:JSON,before:JSON,after:JSON,format:JSON)async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        let owner=AppModel(),model=WorkbookModel(bridge:owner.bridge)
        func install(_ event:JSON,_ old:JSON,_ new:JSON) {
            model.projectID="raw-field-project";model.reportID="raw-field-fixed";model.report=JSON(["report_id":model.reportID,"revisions":[["revision_occurrence_id":event["from_revision_occurrence_id"].string,"index":0,"sheets":[["sheet_id":event["from_sheet_id"].string,"name":"Before"]]],["revision_occurrence_id":event["to_revision_occurrence_id"].string,"index":1,"sheets":[["sheet_id":event["to_sheet_id"].string,"name":"After"]]]]])
            model.beforeID=event["from_revision_occurrence_id"].string;model.afterID=event["to_revision_occurrence_id"].string;model.beforeSheetID=event["from_sheet_id"].string;model.afterSheetID=event["to_sheet_id"].string;model.changesFromID=model.beforeID;model.changesToID=model.afterID;model.changes=[event];model.selectedChangeID=event["change_id"].string;model.beforeAddress=event["before_address"].string;model.afterAddress=event["after_address"].string;model.beforeCell=old;model.afterCell=new;model.diffMode="text"
        }
        install(change,before,after)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:WorkbookWorkspace(model:model));window.orderFront(nil);defer{window.close()};try await Task.sleep(nanoseconds:150_000_000);window.contentView?.layoutSubtreeIfNeeded()
        guard let content=window.contentView else{throw NSError(domain:"RawFieldHostMissing",code:1)}
        let fallback=workspaceLayoutMarkers(in:content).filter{$0.identifier?.rawValue.hasPrefix("Reviset.workbook.rawField.value.")==true}
        try require(fallback.count==2 && fallback.allSatisfy{$0.bounds.height>1000 && $0.bounds.width>0} && model.beforeCell["value"].string.utf16.elementsEqual(before["value"].string.utf16) && model.afterCell["value"].string.utf16.elementsEqual(after["value"].string.utf16),"CompleteOverLineBudgetRawFieldsNotMounted")
        let heights=fallback.map{Double($0.bounds.height)}
        install(format["change"],format["before"],format["after"]);try await Task.sleep(nanoseconds:100_000_000);content.layoutSubtreeIfNeeded()
        let formats=workspaceLayoutMarkers(in:content).filter{$0.identifier?.rawValue.hasPrefix("Reviset.workbook.rawField.number_format.")==true}
        try require(formats.count==2 && formats.allSatisfy{$0.bounds.height>0},"NeutralNumberFormatRawObservationsMissing")
        let diff=unifiedTextDiff(before:"a\r\nx",after:"a\nx",semantic:true)
        let markerWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:220),styleMask:[.titled],backing:.buffered,defer:false);markerWindow.isReleasedWhenClosed=false;markerWindow.contentView=NSHostingView(rootView:VStack(alignment:.leading){ForEach(Array(diff.lines.enumerated()),id:\.offset){_,line in NativeDiffSourceLine(prefix:line.prefix,text:line.text,semantic:true,terminator:line.terminator)}});markerWindow.orderFront(nil);defer{markerWindow.close()};try await Task.sleep(nanoseconds:100_000_000)
        let labels=markerWindow.contentView.map{views($0).compactMap{$0 as? NSTextField}.filter{$0.identifier?.rawValue=="Reviset.diff.terminator"}} ?? []
        try require(labels.count==diff.lines.count && Set(labels.map(\.stringValue)).isSuperset(of:["⟦CRLF⟧","⟦LF⟧","⟦EOF⟧"]) && labels.allSatisfy{!$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty && !$0.isEditable},"ActualSecondaryTerminatorLabelsMissingOrHidden")
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:["scope":"production workbook text overlay raw fallback/number-format geometry with synthetic complete cells, and actual secondary AppKit terminator labels; no extraction or OS input claim","complete_value_utf16":before["value"].string.utf16.count,"raw_source_marker_heights":heights,"number_format_raw_sections":formats.count,"actual_visible_secondary_terminator_labels":labels.map(\.stringValue),"raw_utf16_preserved":true],options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("raw-fallback-proof.json"))}
    }

    @MainActor static func checkNeutralObservationHosting(_ fixture:JSON)async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        func labels(_ view:NSView)->[String] {views(view).compactMap{$0 as? NSTextField}.filter{$0.identifier?.rawValue=="Reviset.diff.terminator" && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty}.map(\.stringValue)}
        func settle(_ window:NSWindow)async throws {try await Task.sleep(nanoseconds:100_000_000);window.contentView?.layoutSubtreeIfNeeded()}
        let owner=AppModel(),model=WorkbookModel(bridge:owner.bridge),event=fixture["change"],scope=fixture["scope"]
        model.reportID="report";model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":scope["before_occurrence"].string,"index":0,"sheets":[["sheet_id":scope["before_sheet"].string,"name":"Before"]]],["revision_occurrence_id":scope["after_occurrence"].string,"index":1,"sheets":[["sheet_id":scope["after_sheet"].string,"name":"After"]]]]])
        model.beforeID=scope["before_occurrence"].string;model.afterID=scope["after_occurrence"].string;model.beforeSheetID=scope["before_sheet"].string;model.afterSheetID=scope["after_sheet"].string;model.changesFromID=model.beforeID;model.changesToID=model.afterID
        var withheld=event.dictionary;withheld["kind"]="cell_observation";model.changes=[JSON(withheld)];model.selectedChangeID=event["change_id"].string;model.beforeAddress=event["before_address"].string;model.afterAddress=event["after_address"].string;model.diffMode="text"
        func source(_ original:JSON,_ text:String?,partialOffset:Int?=nil)->JSON {
            var value=original.dictionary;value["value"]=text ?? NSNull();value["formula"]=NSNull();value["number_format"]=NSNull();value["value_type"]="string";value["cached_result"]="not_applicable";value["formula_interpretation"]="not_formula"
            let partial=partialOffset != nil,offset=partialOffset ?? 0,total=partial ? offset+(text?.utf16.count ?? 0)+3:(text?.utf16.count ?? 0)
            let next:Any=partial ? offset+(text?.utf16.count ?? 0) as Any:NSNull()
            value["text_continuations"]=["value":["state":text==nil ? "missing":partial ? "truncated":text!.isEmpty ? "empty":"complete","offset":offset,"total_length":total,"next_offset":next],"formula":["state":"missing","offset":0,"total_length":0,"next_offset":NSNull()],"number_format":["state":"missing","offset":0,"total_length":0,"next_offset":NSNull()]]
            return JSON(value)
        }
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:WorkbookWorkspace(model:model));window.orderFront(nil);defer{window.close()};try await settle(window)
        model.projectID="neutral-project"
        let isolatedPasteboard=NSPasteboard.withUniqueName();defer{isolatedPasteboard.clearContents()}
        var copyActions=0
        func checkCopies(_ content:NSView,_ expected:[String])throws {
            let buttons=views(content).compactMap{$0 as? NSButton}.filter{$0.identifier?.rawValue=="Reviset.source.copyRaw"}
            try require(buttons.count==expected.count,"NeutralRawCopyActionCount")
            var remaining=expected
            for button in buttons {
                guard let target=button.target as? NativeRawSourceCopyButton.Coordinator,let index=remaining.firstIndex(where:{$0.utf16.elementsEqual(target.text.utf16)}) else{throw NSError(domain:"NeutralRawCopyWrongPhysicalSource",code:1)}
                let source=remaining.remove(at:index)
                try require(!button.isHiddenOrHasHiddenAncestor && !button.visibleRect.isEmpty && button.isEnabled && button.toolTip==L("common.copyRaw") && button.accessibilityLabel()==L("common.copyRaw"),"NeutralRawCopyActionNotDiscoverable")
                target.pasteboard=isolatedPasteboard;isolatedPasteboard.clearContents();button.performClick(nil)
                try require(isolatedPasteboard.string(forType:.string)?.utf16.elementsEqual(source.utf16)==true,"NeutralRawCopyAlteredUTF16OrIncludedAnnotation")
                copyActions+=1
            }
            try require(remaining.isEmpty,"NeutralRawCopyMissedSource")
        }
        var cases:[[String:Any]]=[]
        for (name,before,after,offset,expected) in [("crlf-to-lf","a\r\nx","a\nx",nil as Int?,["⟦CRLF⟧","⟦EOF⟧","⟦LF⟧","⟦EOF⟧"]),("terminated-to-eof","a\n","a",nil,["⟦LF⟧","⟦EOF⟧"]),("literal-marker","⟦LF⟧ 👨‍👩‍👧‍👦e\u{301}\r","⟦LF⟧ 👨‍👩‍👧‍👦e\u{301}",nil,["⟦CR⟧","⟦EOF⟧"]),("partial-fragment","a\r\nx",nil,0,[]),("continued-partial-fragment","a\r",nil,6,[]),("missing-before",nil,"a\n",nil,["⟦LF⟧"]),("empty-observation","",nil,nil,[])] as [(String,String?,String?,Int?,[String])] {
            model.beforeCell=source(fixture["before"],before,partialOffset:offset);model.afterCell=source(fixture["after"],after);model.cellTextOffset=offset ?? 0;try await settle(window)
            let actual=labels(window.contentView!),old=workbookRawField(model.beforeCell,field:"value"),new=workbookRawField(model.afterCell,field:"value")
            try require(actual.sorted()==expected.sorted(),"NeutralWorkbookTerminatorLabels-"+name+"-"+actual.joined(separator:","))
            try require(old.text?.utf16.elementsEqual((before ?? "").utf16)==(before == nil ? nil:true) && new.text?.utf16.elementsEqual((after ?? "").utf16)==(after == nil ? nil:true),"NeutralWorkbookChangedRawUTF16-"+name)
            if offset != nil {try require(old.state == .partial && !old.complete && workspaceLayoutMarkers(in:window.contentView!).contains{$0.identifier?.rawValue=="Reviset.workbook.rawField.value.before"},"PartialRawReaderWasSuppressedOrClaimedComplete")}
            let context=WorkbookSelectedEventScope(beforeOccurrence:model.beforeID,afterOccurrence:model.afterID,beforeSheet:model.beforeSheetID,afterSheet:model.afterSheetID)
            try require(workbookFieldDiffEligibility(change:model.selectedChange,before:model.beforeCell,after:model.afterCell,scope:context) == .neutral,"NeutralObservationClaimedFieldEdit")
            try checkCopies(window.contentView!,[before,after].compactMap{$0}.filter{!$0.isEmpty})
            cases.append(["name":name,"native_secondary_labels":actual,"before_raw_utf16":Array((before ?? "").utf16).map(Int.init),"after_raw_utf16":Array((after ?? "").utf16).map(Int.init),"before_state":old.state.rawValue,"after_state":new.state.rawValue,"neutral":true])
        }
        let document=AppModel();document.report=JSON(["report_id":"fixed","revisions":[["revision_occurrence_id":"a"],["revision_occurrence_id":"b"]]]);document.from=0;document.to=1;document.diffMode="text"
        let docWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:500),styleMask:[.titled],backing:.buffered,defer:false);docWindow.isReleasedWhenClosed=false;docWindow.contentView=NSHostingView(rootView:DocumentUnifiedDiff().environmentObject(document));docWindow.orderFront(nil);defer{docWindow.close()}
        var docCases:[[String:Any]]=[]
        for (before,after,expected) in [("a\r\nx","a\nx",["⟦CRLF⟧","⟦EOF⟧","⟦LF⟧","⟦EOF⟧"]),("a\n","a",["⟦LF⟧","⟦EOF⟧"])] {
            document.changes=[JSON(["change_id":"neutral","kind":"text_struck_through","before":before,"after":after])];document.selectedChangeID="neutral";try await settle(docWindow)
            let actual=labels(docWindow.contentView!),diff=documentTextDiff(document.selected)
            try require(actual.sorted()==expected.sorted() && !diff.semantic && diff.lines.allSatisfy{$0.prefix.isEmpty},"NeutralDocumentTerminatorLabelsMissingOrSemantic")
            try require(document.selected["before"].string.utf16.elementsEqual(before.utf16) && document.selected["after"].string.utf16.elementsEqual(after.utf16),"NeutralDocumentSourceChanged")
            try checkCopies(docWindow.contentView!,[before,after])
            docCases.append(["native_secondary_labels":actual,"before_raw_utf16":Array(before.utf16).map(Int.init),"after_raw_utf16":Array(after.utf16).map(Int.init),"neutral":true])
        }
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:["scope":"mounted production neutral WorkbookUnifiedDiff and DocumentUnifiedDiff secondary native terminator labels; no OS input or extraction claim","workbook_cases":cases,"document_cases":docCases,"partial_and_missing_not_claimed_eof":true,"raw_utf16_preserved":true,"source18_raw_copy":["actual_native_actions":copyActions,"isolated_unique_pasteboard_only":true,"normal_user_clipboard_read_or_written":false,"clipboard_contents_logged":false,"exact_utf16_including_terminators":true,"complete_and_partial_sources_verified":true]],options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("source17-proof.json"))}
    }

    @MainActor static func checkSource16Presentation(_ metadataEvent:JSON)async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        func settle(_ window:NSWindow)async throws {try await Task.sleep(nanoseconds:100_000_000);window.contentView?.layoutSubtreeIfNeeded()}
        guard let data=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"],let resources=ProcessInfo.processInfo.environment["DOCVER_TEST_ONE_SIDED_RESOURCES"] else{throw NSError(domain:"Source16FixtureMissing",code:1)}
        let library=URL(fileURLWithPath:data).appendingPathComponent("source16-library");try FileManager.default.createDirectory(at:library,withIntermediateDirectories:true)
        let raw="stored only; not recalculated"
        try JSON(["mode":"ok","value":raw]).data().write(to:library.appendingPathComponent("control.json"))
        let model=WorkbookModel(bridge:Bridge(resources:URL(fileURLWithPath:resources),library:library));model.reportID="report"
        let event=JSON(["change_id":"selected-event","kind":"stored_value","from_revision_occurrence_id":"old","to_revision_occurrence_id":"new","from_sheet_id":"sheet-old","to_sheet_id":"sheet-new","before_address":"A2","after_address":"A2","association":"exact","alignment_method":"unique_exact_row_content"])
        model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":"old","index":0,"sheets":[["sheet_id":"sheet-old","name":"Old source"]]],["revision_occurrence_id":"new","index":1,"sheets":[["sheet_id":"sheet-new","name":"New source"]]],["revision_occurrence_id":"later","index":2,"sheets":[]]]]);model.beforeID="old";model.afterID="new";model.beforeSheetID="sheet-old";model.afterSheetID="sheet-new";model.changesFromID="old";model.changesToID="later";model.changesMode="history";model.mode="history";model.changes=[event]
        let host=NSHostingView(rootView:WorkbookWorkspace(model:model)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:800),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()};try await settle(window)
        model.projectID="project";await model.chooseChange("selected-event");try await settle(window)
        let preferences=LanguagePreferences.shared,previous=LanguagePreferences.shared.selection;defer{preferences.selection=previous}
        var observations:[[String:Any]]=[]
        for language in [UILanguage.en,.ko] {
            preferences.selection=language;model.inspectorVisible=false;try await settle(window)
            guard let button=views(host).compactMap({$0 as? NSButton}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetailsAction"}) else{throw NSError(domain:"ActualCellDetailsActionMissing",code:1)}
            let fixed=try model.report.data(),rows=try JSON(model.changes.map(\.raw)).data(),query=model.comparisonScope,identity=[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID],before=try model.beforeCell.data(),after=try model.afterCell.data()
            let tables=views(host).compactMap{$0 as? NSTableView}.filter{$0.identifier?.rawValue.hasPrefix("Docver.workbook.grid.")==true}
            try require(tables.count==2,"CellDetailsPhysicalGridPairMissing")
            for table in tables {if let scroll=table.enclosingScrollView {scroll.contentView.scroll(to:NSPoint(x:400,y:scroll.contentView.bounds.origin.y));scroll.reflectScrolledClipView(scroll.contentView)}}
            try await settle(window)
            let states=tables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds.origin,$0.selectedRow)}
            let requestsBefore=try Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))
            try require(button.isEnabled && !button.visibleRect.isEmpty && button.title==L("workbook.action.cellDetails") && !model.inspectorVisible,"FocusedCellLackedVisibleDetailsAction")
            button.performClick(nil);try await settle(window)
            guard let details=workspaceLayoutMarkers(in:host).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetails"}) else{throw NSError(domain:"ExistingCellInspectorNotMounted",code:1)}
            try require(model.inspectorVisible && !details.visibleRect.isEmpty && details.bounds.width>=250 && model.beforeCell["value"].string.utf16.elementsEqual(raw.utf16),"CellDetailsActionDidNotExposeExistingVerbatimReader")
            try require((try model.report.data())==fixed && (try JSON(model.changes.map(\.raw)).data())==rows && model.comparisonScope==query && identity==[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID] && (try model.beforeCell.data())==before && (try model.afterCell.data())==after && (try Data(contentsOf:library.appendingPathComponent("read-events.jsonl")))==requestsBefore,"OpeningCellDetailsChangedFixedScopeRawSourceOrQueriedAgain")
            var horizontalReveal:[[String:Any]]=[]
            for (table,coordinator,origin,row) in states {
                guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,let owner=table.dataSource as? WorkbookGrid.Coordinator,let column=table.tableColumns.firstIndex(where:{$0.identifier.rawValue==String(owner.parent.selectedColumn)}) else{throw NSError(domain:"CellDetailsPinnedSourceScopeMissing",code:1,userInfo:[NSLocalizedDescriptionKey:"table=\(table.identifier?.rawValue ?? "nil"), scroll=\(String(describing:type(of:table.enclosingScrollView))), owner=\(String(describing:type(of:table.dataSource))), columns=\(table.tableColumns.map{$0.identifier.rawValue})"])}
                guard let rowLabel=scroll.pinnedRowLabel(owner.parent.selectedRow) else{throw NSError(domain:"CellDetailsPinnedRowMissing",code:1,userInfo:[NSLocalizedDescriptionKey:"pane=\(owner.parent.pane), selected=\(owner.parent.selectedRow), start=\(owner.parent.rowStart), tableVisible=\(table.visibleRect), clip=\(scroll.contentView.bounds), gutter=\(scroll.pinnedRowGutter.frame), labels=\(scroll.pinnedRowGutter.subviews.compactMap{($0 as? NSTextField)?.stringValue})"])}
                let actual=scroll.contentView.bounds.origin
                try require(views(host).contains{$0===table} && (table.dataSource as AnyObject?) === coordinator && actual.y==origin.y && actual.x<origin.x && table.selectedRow==row && scroll.columnVisibleToRightOfGutter(column) && !rowLabel.visibleRect.isEmpty,"OpeningCellDetailsDidNotScopedRevealBesidePinnedRowsOrMovedVerticalViewport")
                horizontalReveal.append(["pane":owner.parent.pane,"before_x":Double(origin.x),"after_x":Double(actual.x),"vertical_origin":Double(actual.y),"physical_row":owner.parent.selectedRow,"physical_column":owner.parent.selectedColumn])
            }
            let expected=L("workbook.changes.intervalDifference",.verbatim(model.versionLabel("old")),.verbatim(model.versionLabel("later")),.verbatim(model.versionLabel("old")),.verbatim(model.versionLabel("new")))
            guard let scopeLabel=views(host).compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.queryEventScopeCopy"}) else{throw NSError(domain:"MountedQueryEventScopeLabelMissing",code:1)}
            try require(model.sourceScopeDescription==expected && scopeLabel.stringValue.utf16.elementsEqual(expected.utf16) && !scopeLabel.isHiddenOrHasHiddenAncestor && !scopeLabel.visibleRect.isEmpty,"QueryAndSelectedEventScopeCopyWasAmbiguousOrUnmounted")
            model.diffMode="text";try await settle(window)
            try require(model.sourceIdentity(before:true).contains("Old source · A2") && model.sourceIdentity(before:false).contains("New source · A2") && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.textSourceIdentity"},"CrossSheetTextIdentityLostNamesOrPhysicalAddresses")
            let savedSheet=model.beforeSheetID;model.beforeSheetID="missing-physical-sheet";try await settle(window)
            try require(model.sourceIdentity(before:true).contains("missing-physical-sheet") && model.missingSourceSheetCaptions.count==1 && model.afterCells.first?["value"].string==raw,"AbsentSheetTextIdentityHidIDOrDiscardedAvailableOppositeSource");model.beforeSheetID=savedSheet;try await settle(window)
            try require(!views(host).compactMap({$0 as? NSTextField}).contains{$0.isEditable && $0.accessibilityIdentifier()=="Docver.workbook.addressInput"} && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.showOriginal" && !$0.visibleRect.isEmpty},"TextModeOfferedInvisibleGridNavigation")
            model.setDiffMode("source");try await settle(window)
            observations.append(["language":language.rawValue,"native_details_action_visible_and_performed":true,"existing_inspector_visible":true,"query_event_copy":scopeLabel.stringValue,"mounted_native_scope_label_verified":true,"raw_literal":raw,"raw_utf16_preserved":true,"no_new_bridge_requests_or_list_replacement":true,"grid_hosts_selection_and_vertical_viewports_retained":true,"explicit_horizontal_reveal_from_offscreen_column":true,"horizontal_reveal":horizontalReveal,"inspected_column_and_pinned_row_visible":true,"text_navigation_explicit_original_route":true])
        }
        var directionalGeometry:[[String:Any]]=[]
        let savedCellState=(model.selectedRow,model.selectedColumn,model.beforeAddress,model.afterAddress,model.beforeCell,model.afterCell,model.beforeCells,model.afterCells,model.selectedChangeID,model.columnStart,model.rowStart)
        for start in [1,4] {
            model.inspectorVisible=false;model.diffMode="source";model.rowStart=1;model.columnStart=start;model.selectedRow=4;model.selectedColumn=4;model.beforeAddress="D4";model.afterAddress="D4";model.selectedChangeID="";model.revealGeneration += 1
            let cell=JSON(["address":"D4","row":4,"column":4,"value":raw,"formula":NSNull(),"number_format":"General"])
            model.beforeCell=cell;model.afterCell=cell;model.beforeCells=[cell];model.afterCells=[cell];try await settle(window)
            let tables=views(host).compactMap{$0 as? NSTableView}.filter{$0.identifier?.rawValue.hasPrefix("Docver.workbook.grid.")==true}
            try require(tables.count==2,"DirectionalCellDetailsPhysicalPairMissing")
            for table in tables {let scroll=table.enclosingScrollView!;scroll.contentView.scroll(to:NSPoint(x:start==1 ? 0:400,y:scroll.contentView.bounds.origin.y));scroll.reflectScrolledClipView(scroll.contentView)}
            let states=tables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds,$0.selectedRow)}
            let rawBefore=try model.beforeCell.data(),rawAfter=try model.afterCell.data(),fixed=try model.report.data(),query=model.comparisonScope,requests=try Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))
            guard let button=views(host).compactMap({$0 as? NSButton}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetailsAction"}) else{throw NSError(domain:"DirectionalCellDetailsButtonMissing",code:1)}
            button.performClick(nil);try await settle(window)
            for (table,owner,bounds,row) in states {
                guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,let coordinator=table.dataSource as? WorkbookGrid.Coordinator,let index=table.tableColumns.firstIndex(where:{$0.identifier.rawValue=="4"}),let label=scroll.pinnedRowLabel(4) else{throw NSError(domain:"DirectionalCellDetailsNativeScopeMissing",code:1)}
                let actual=scroll.contentView.bounds,direction=start==1 ? actual.minX>bounds.minX:actual.minX<bounds.minX
                let fact:[String:Any]=["column_start":start,"physical_address":"D4","pane":coordinator.parent.pane,"before_clip":NSStringFromRect(bounds),"after_clip":NSStringFromRect(actual),"column_rect":NSStringFromRect(table.rect(ofColumn:index)),"gutter_rect":NSStringFromRect(scroll.pinnedRowGutter.frame),"horizontal_direction":start==1 ? "right":"left","inspected_column_visible":scroll.columnVisibleToRightOfGutter(index),"physical_row_visible":!label.visibleRect.isEmpty,"pending_reveal":scroll.pendingCellDetailsReveal != nil]
                try require(direction && (start != 1 || actual.width<bounds.width) && actual.minY==bounds.minY && table.selectedRow==row && (table.dataSource as AnyObject?) === owner && views(host).contains{$0===table} && scroll.columnVisibleToRightOfGutter(index) && !label.visibleRect.isEmpty && scroll.pendingCellDetailsReveal==nil,"DirectionalCellDetailsAfterFinalShrinkFailed_\(fact)")
                directionalGeometry.append(fact)
                // Closing the inspector is passive geometry, so the consumed
                // action cannot acquire ownership of subsequent viewport moves.
            }
            try require(try model.beforeCell.data()==rawBefore && model.afterCell.data()==rawAfter && model.report.data()==fixed && model.comparisonScope==query && Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))==requests,"DirectionalDetailsQueriedOrChangedRawScope")
            let origins=tables.map{$0.enclosingScrollView!.contentView.bounds.origin}
            model.inspectorVisible=false;try await settle(window)
            for (table,origin) in zip(tables,origins) {try require(table.enclosingScrollView!.contentView.bounds.origin==origin,"ClosingDetailsRearmedConsumedReveal")}
        }
        // A real native user-sized column can exceed the entire source pane.
        // Opening details must finish its single reveal even when full fit is impossible.
        model.inspectorVisible=false;model.columnStart=1;model.revealGeneration += 1;try await settle(window)
        let oversizedTables=views(host).compactMap{$0 as? NSTableView}.filter{$0.identifier?.rawValue.hasPrefix("Docver.workbook.grid.")==true}
        let originalWindowSize=host.bounds.size
        var oversizedColumns:[(NSTableColumn,CGFloat,CGFloat)]=[],oversizedGeometry:[[String:Any]]=[]
        for table in oversizedTables {
            guard let column=table.tableColumns.first(where:{$0.identifier.rawValue=="4"}) else{throw NSError(domain:"OversizedD4ColumnMissing",code:1)}
            oversizedColumns.append((column,column.width,column.maxWidth));column.maxWidth=2000;column.width=1600;table.tile()
            let scroll=table.enclosingScrollView!;scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.contentView.bounds.origin.y));scroll.reflectScrolledClipView(scroll.contentView)
        }
        let oversizedStates=oversizedTables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds.origin,$0.selectedRow)}
        let oversizedBefore=try model.beforeCell.data(),oversizedAfter=try model.afterCell.data(),oversizedFixed=try model.report.data(),oversizedQuery=model.comparisonScope,oversizedRequests=try Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))
        guard let oversizedButton=views(host).compactMap({$0 as? NSButton}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetailsAction"}) else{throw NSError(domain:"OversizedDetailsButtonMissing",code:1)}
        oversizedButton.performClick(nil);try await settle(window)
        for (table,owner,origin,row) in oversizedStates {
            guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,let index=table.tableColumns.firstIndex(where:{$0.identifier.rawValue=="4"}) else{throw NSError(domain:"OversizedDetailsNativeScopeMissing",code:1)}
            try require(table.rect(ofColumn:index).width>scroll.contentView.bounds.width && !scroll.columnVisibleToRightOfGutter(index) && scroll.pendingCellDetailsReveal==nil && scroll.contentView.bounds.minY==origin.y && table.selectedRow==row && (table.dataSource as AnyObject?) === owner,"OversizedDetailsRetainedRevealAuthorityOrMovedPhysicalSource")
            let fact=try WorkbookNativeSmoke.oversizedLeadingSourceFacts(table,column:index,row:row)
            try require(fact["source_observation_state"] as? String=="nonempty_string" && fact["native_text_leading_fragment_visible"] as? Bool==true && fact["expected_raw_utf16"] as? [Int]==Array(raw.utf16).map(Int.init),"OversizedD4LeadingTextNotVisibleBesidePinnedGutter")
            oversizedGeometry.append(fact)
            scroll.contentView.scroll(to:NSPoint(x:127,y:origin.y));scroll.reflectScrolledClipView(scroll.contentView)
        }
        let manualOrigins=oversizedTables.map{$0.enclosingScrollView!.contentView.bounds.origin}
        window.setContentSize(NSSize(width:originalWindowSize.width+80,height:originalWindowSize.height));try await settle(window)
        guard let pageSplit=views(host).compactMap({$0 as? NSSplitView}).first(where:{$0.identifier?.rawValue=="Reviset.workspace.workbook.pages"}),let pageSizing=pageSplit.delegate as? WorkspacePaneSizing else{throw NSError(domain:"OversizedDetailsNativeDividerMissing",code:1)}
        let savedPageExtent=pageSplit.arrangedSubviews.last!.frame.width
        pageSizing.resizeAuxiliary(to:savedPageExtent+30,commit:true);try await settle(window)
        for ((table,owner,_,row),origin) in zip(oversizedStates,manualOrigins) {let scroll=table.enclosingScrollView as! WorkbookTableScrollView;try require(scroll.pendingCellDetailsReveal==nil && scroll.contentView.bounds.origin==origin && table.selectedRow==row && (table.dataSource as AnyObject?) === owner,"PassiveWindowOrDividerResizeReplayedOversizedReveal")}
        // Fault the actual mounted readiness marker to exercise an unavailable
        // marker, rather than installing a test callback in the production scroll.
        guard let readinessMarker=workspaceLayoutMarkers(in:host).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetails"}) else{throw NSError(domain:"UnavailableReadinessMarkerFixtureMissing",code:1)}
        let readinessID=readinessMarker.identifier;readinessMarker.identifier=NSUserInterfaceItemIdentifier("Test.unavailableCellDetailsReadiness")
        oversizedButton.performClick(nil);try await settle(window)
        readinessMarker.identifier=readinessID
        for (table,origin) in zip(oversizedTables,manualOrigins) {let scroll=table.enclosingScrollView as! WorkbookTableScrollView;try require(scroll.pendingCellDetailsReveal==nil && scroll.contentView.bounds.origin==origin,"UnavailableInspectorMarkerRetainedRevealAuthority")}
        try require(try model.beforeCell.data()==oversizedBefore && model.afterCell.data()==oversizedAfter && model.report.data()==oversizedFixed && model.comparisonScope==oversizedQuery && Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))==oversizedRequests,"OversizedDetailsChangedSourceQueryOrReadAgain")
        var mixedObservationFacts:[[String:Any]]=[]
        let originalBeforeCells=model.beforeCells,originalBeforeCell=model.beforeCell
        let emptyCell=JSON(["address":"D4","row":4,"column":4,"value":"","value_type":"string"]),nullCell=JSON(["address":"D4","row":4,"column":4,"value":NSNull(),"value_type":"blank"])
        for (expectedState,source) in [("missing_observation",[JSON]()),("empty_string",[emptyCell]),("null_value",[nullCell])] {
            model.beforeCells=source;model.beforeCell=source.first ?? JSON();model.revealGeneration += 1;try await settle(window)
            for table in oversizedTables {let scroll=table.enclosingScrollView!;scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.contentView.bounds.minY));scroll.reflectScrolledClipView(scroll.contentView)}
            oversizedButton.performClick(nil);try await settle(window)
            for table in oversizedTables {
                guard let owner=table.dataSource as? WorkbookGrid.Coordinator,let index=table.tableColumns.firstIndex(where:{$0.identifier.rawValue=="4"}) else{throw NSError(domain:"MixedObservationNativeOwnerMissing",code:1)}
                let fact=try WorkbookNativeSmoke.oversizedLeadingSourceFacts(table,column:index,row:table.selectedRow),before=owner.parent.pane=="before"
                try require(fact["source_observation_state"] as? String == (before ? expectedState:"nonempty_string") && fact["raw_utf16_exact"] as? Bool==true && fact["native_cell_present"] as? Bool==true && fact["native_text_field_present"] as? Bool==true && fact["pending_nil_after_attempt"] as? Bool==true,"MixedObservationLostExactNativeSourceOrOwner")
                if before {try require(fact["source_text_visibility_applicable"] as? Bool==false && fact["native_text_leading_fragment_visible"] is NSNull && fact["expected_raw_utf16"] as? [Int]==[] && fact["native_raw_utf16"] as? [Int]==[],"MissingOrEmptySourceFalselyClaimedVisibleText")}
                else {try require(fact["native_text_leading_fragment_visible"] as? Bool==true && fact["native_raw_utf16"] as? [Int]==Array(raw.utf16).map(Int.init),"ObservedOppositeSourceLostActualLeadingText")}
                var recorded=fact;recorded["controlled_before_observation_state"]=expectedState;mixedObservationFacts.append(recorded)
                if before && expectedState=="missing_observation",let cell=table.view(atColumn:index,row:table.selectedRow,makeIfNecessary:true) as? NSTableCellView,let field=cell.textField {
                    var missingFieldCode="",wrongRawCode=""
                    cell.textField=nil
                    do {_ = try WorkbookNativeSmoke.oversizedLeadingSourceFacts(table,column:index,row:table.selectedRow)} catch let error as BridgeError {missingFieldCode=error.code}
                    cell.textField=field;field.stringValue="invented text"
                    do {_ = try WorkbookNativeSmoke.oversizedLeadingSourceFacts(table,column:index,row:table.selectedRow)} catch let error as BridgeError {wrongRawCode=error.code}
                    field.stringValue=""
                    try require(missingFieldCode=="WORKBOOK_CELL_DETAILS_OVERSIZED_FIELD" && wrongRawCode=="WORKBOOK_CELL_DETAILS_OVERSIZED_RAW","MissingNativeFieldOrInventedRawWasTreatedAsAbsentObservation")
                }
            }
        }
        model.beforeCells=originalBeforeCells;model.beforeCell=originalBeforeCell;model.revealGeneration += 1;try await settle(window)
        try require(try model.beforeCell.data()==oversizedBefore && model.afterCell.data()==oversizedAfter && model.report.data()==oversizedFixed && model.comparisonScope==oversizedQuery && Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))==oversizedRequests,"MixedObservationQualificationChangedFixedQueryOrQueriedAgain")
        for (column,width,maxWidth) in oversizedColumns {column.width=width;column.maxWidth=maxWidth}
        pageSizing.resizeAuxiliary(to:savedPageExtent,commit:true);window.setContentSize(originalWindowSize);model.inspectorVisible=false;try await settle(window)
        model.selectedRow=savedCellState.0;model.selectedColumn=savedCellState.1;model.beforeAddress=savedCellState.2;model.afterAddress=savedCellState.3;model.beforeCell=savedCellState.4;model.afterCell=savedCellState.5;model.beforeCells=savedCellState.6;model.afterCells=savedCellState.7;model.selectedChangeID=savedCellState.8;model.columnStart=savedCellState.9;model.rowStart=savedCellState.10;model.revealGeneration += 1;try await settle(window)
        let originalReport=model.report
        var longReport=model.report.dictionary,longRevisions=model.revisions.map(\.dictionary)
        for index in longRevisions.indices {longRevisions[index]["label"]="\(index+1) · "+String(repeating:"긴 버전 이름 👨‍👩‍👧‍👦 e\u{301} العربية עברית · ",count:2)}
        longReport["revisions"]=longRevisions;model.report=JSON(longReport)
        var captionGeometry:[[String:Any]]=[]
        for proposed in [nil,CGFloat.infinity,CGFloat.nan,-CGFloat.infinity,0,184] as [CGFloat?] {let width=WorkbookSourceScopeCaption.finiteWidth(proposed);try require(width.isFinite && width>0 && (proposed?.isFinite==true || width==280),"ScopeCaptionAcceptedNonFiniteWidth")}
        for language in [UILanguage.en,.ko] {
            preferences.selection=language
            let expected=model.sourceScopeDescription
            try require(expected.utf16.count>300,"LongUnicodeVersionScopeFixtureMissing")
            for width in [CGFloat(184),239,317] {
                let captionWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:700),styleMask:[.titled],backing:.buffered,defer:false);captionWindow.isReleasedWhenClosed=false
                let captionHost=NSHostingView(rootView:WorkbookSourceScopeCaption(text:expected).frame(width:width));captionWindow.contentView=captionHost;captionWindow.orderFront(nil);try await settle(captionWindow)
                guard let field=views(captionHost).compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.queryEventScopeCopy"}),let cell=field.cell else{throw NSError(domain:"LongUnicodeMountedScopeCaptionMissing",code:1)}
                let required=cell.cellSize(forBounds:NSRect(x:0,y:0,width:field.bounds.width,height:CGFloat.greatestFiniteMagnitude)).height
                let alignmentRect=field.alignmentRect(forFrame:field.bounds),visible=field.visibleRect.intersection(field.bounds)
                guard field.bounds.width.isFinite && field.bounds.height.isFinite && abs(alignmentRect.width-width)<1 && field.bounds.height>=ceil(required) && required>30 && visible.height>=field.bounds.height-1 && field.stringValue.utf16.elementsEqual(expected.utf16) else {throw NSError(domain:"LongUnicodeScopeCaptionWrappedTailClipped",code:1,userInfo:[NSLocalizedDescriptionKey:"language=\(language.rawValue), proposed=\(width), native=\(field.bounds), alignment=\(alignmentRect), required=\(required), visible=\(visible), utf16=\(expected.utf16.count), exact=\(field.stringValue.utf16.elementsEqual(expected.utf16))"])}
                captionGeometry.append(["language":language.rawValue,"proposed_width":Double(width),"native_width":Double(field.bounds.width),"native_alignment_width":Double(alignmentRect.width),"allocated_height":Double(field.bounds.height),"required_native_cell_height":Double(required),"visible_height":Double(visible.height),"scope_copy_utf16_count":expected.utf16.count,"exact_scope_copy":true,"wrapped_tail_has_native_height":true]);captionWindow.close()
            }
        }
        model.report=originalReport;try await settle(window)
        model.beforeID="old";model.afterID="old";model.afterSheetID="sheet-old";model.beforeAddress="A2";model.afterAddress="A2";model.beforeCell=JSON(["address":"A2","cached_result":"missing","value":NSNull()]);model.afterCell=model.beforeCell
        try require(model.selectedSourceWarnings.count==1 && model.selectedSourceWarnings[0].hasPrefix(L("doc.common.source")) && model.navigationDetail==L("workbook.nav.singleSourceDetail"),"SingleSourceRetainedPairedWarningsOrFooter")
        // A real diffWorkbooks metadata event has no cell payload or cell warning.
        model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":metadataEvent["from_revision_occurrence_id"].string,"index":0],["revision_occurrence_id":metadataEvent["to_revision_occurrence_id"].string,"index":1]]]);model.changes=[metadataEvent];model.changesFromID=metadataEvent["from_revision_occurrence_id"].string;model.changesToID=metadataEvent["to_revision_occurrence_id"].string;await model.chooseChange(metadataEvent["change_id"].string);model.diffMode="text";try await settle(window)
        try require(model.showingSheetMetadata && model.selectedSourceWarnings.isEmpty && model.beforeCell.isNull && model.afterCell.isNull && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.sheetMetadataDiff"} && !workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue.hasPrefix("Reviset.workbook.rawField.")==true},"ActualMetadataEventMislabelledUnmaterializedCell")
        var cellEvent=metadataEvent.dictionary;cellEvent["kind"]="cell_observation";model.changes=[JSON(cellEvent)];try require(!model.showingSheetMetadata && model.selectedSourceWarnings.count==2,"NullCellEventLostUnmaterializedObservationWarnings")
        // Normal manual cell selection retires event authority and keeps only a
        // Return anchor. Also guard a stale metadata ID paired with real focus.
        let sheetEvent=JSON(["change_id":"sheet-metadata","kind":"sheet_name","from_revision_occurrence_id":"old","to_revision_occurrence_id":"new","from_sheet_id":"sheet-old","to_sheet_id":"sheet-new","before_address":"","after_address":""])
        model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":"old","index":0,"sheets":[["sheet_id":"sheet-old","name":"Old source"]]],["revision_occurrence_id":"new","index":1,"sheets":[["sheet_id":"sheet-new","name":"New source"]]],["revision_occurrence_id":"later","index":2,"sheets":[]]]]);model.changes=[sheetEvent];model.changesFromID="old";model.changesToID="later";await model.chooseChange("sheet-metadata");model.setDiffMode("source");try await settle(window)
        let metadataRows=try JSON(model.changes.map(\.raw)).data(),metadataQuery=model.comparisonScope
        try require(model.showingSheetMetadata && model.selectedRow==0 && model.beforeAddress.isEmpty && model.afterAddress.isEmpty,"MetadataInitialFocusNotNeutral")
        await model.selectCell(2,1);try await settle(window)
        try require(model.selectedChange.isNull && model.canReturnToChange && !model.showingSheetMetadata && model.beforeCell["value"].string==raw,"MetadataCellSelectionKeptEventAuthorityOrHidRawCell")
        model.selectedChangeID="sheet-metadata";try require(!model.showingSheetMetadata,"StaleMetadataEventHidCurrentPhysicalFocus");model.selectedChangeID=""
        model.inspectorVisible=false;try await settle(window)
        guard let cellButton=views(host).compactMap({$0 as? NSButton}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetailsAction"}),cellButton.isEnabled else{throw NSError(domain:"MetadataManualCellDetailsUnavailable",code:1)}
        cellButton.performClick(nil);try await settle(window)
        try require(workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.inspector.raw.value" && !$0.visibleRect.isEmpty} && model.beforeCell["value"].string.utf16.elementsEqual(raw.utf16),"MetadataManualCellDetailsHidFocusedRawSource")
        await model.returnToChange();model.setDiffMode("text");try await settle(window)
        try require(model.showingSheetMetadata && model.selectedRow==0 && model.beforeAddress.isEmpty && model.afterAddress.isEmpty && model.comparisonScope==metadataQuery && (try JSON(model.changes.map(\.raw)).data())==metadataRows && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.sheetMetadataDiff"},"MetadataReturnLostQueryRowsOrMetadataPresentation")
        let document=AppModel();document.report=JSON(["report_id":"fixed","revisions":[["revision_occurrence_id":"a"],["revision_occurrence_id":"b"]]]);document.from=0;document.to=1;document.diffMode="text"
        let docWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:500),styleMask:[.titled],backing:.buffered,defer:false);docWindow.isReleasedWhenClosed=false;docWindow.contentView=NSHostingView(rootView:DocumentUnifiedDiff().environmentObject(document));docWindow.orderFront(nil);defer{docWindow.close()};try await settle(docWindow)
        try require(!workspaceLayoutMarkers(in:docWindow.contentView!).contains{$0.identifier?.rawValue=="Reviset.document.selectedEventHeader"},"UnselectedDocumentDiffClaimedSelectedEvent")
        document.changes=[JSON(["change_id":"selected","kind":"text_modified","before":"100","after":"120"])];document.selectedChangeID="selected";try await settle(docWindow)
        try require(workspaceLayoutMarkers(in:docWindow.contentView!).contains{$0.identifier?.rawValue=="Reviset.document.selectedEventHeader"},"SelectedDocumentEventHeaderMissing")
        try JSONSerialization.data(withJSONObject:["scope":"controlled production WorkbookWorkspace/AppKit button and DocumentUnifiedDiff; synthetic cell fixture plus real diffWorkbooks date_system event; no submitted import or OS input","observations":observations,"single_source_warning_and_footer":true,"real_engine_metadata_event":metadataEvent.raw,"metadata_caption_has_no_cell_warning_or_field_rows":true,"null_cell_event_keeps_unmaterialized_warning":true,"metadata_manual_cell_details_and_return_preserves_query_rows":true,"stale_metadata_id_cannot_hide_physical_focus":true,"selected_null_document_header_hidden":true,"source26_shared_shipped_oversized_assertion_used":true,"source26_mixed_observation_leading_source":mixedObservationFacts,"source26_missing_native_field_and_invented_raw_hard_fail":true,"source24_oversized_cell_details":oversizedGeometry,"source24_passive_window_and_divider_resize_keeps_manual_origin":true,"source24_missing_native_marker_readiness_expires":true,"source23_cell_details_both_directions_after_final_inspector_geometry":directionalGeometry,"source18_scope_caption_geometry":captionGeometry,"source18_nonfinite_width_resolved":true],options:[.sortedKeys]).write(to:URL(fileURLWithPath:data).appendingPathComponent("source16-proof.json"))
    }

}
