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
    var body:some View {ChangeListView().environmentObject(model).environmentObject(layout).sheet(isPresented:$model.importSheet){ImportView().environmentObject(model)}}
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
        }
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
        guard let sheetEvent=engineCases.first(where:{$0["change"]["kind"].string=="date_system"}) else{throw NSError(domain:"ActualEngineSheetEventMissing",code:1)}
        try await checkSource16Presentation(sheetEvent["change"])
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
        let raw="stored only; not recalculated"
        let preview=String(repeating:"p",count:64)
        let cells=[JSON(["address":"D4","row":4,"column":4,"value":raw,"value_type":"string","formula":"SUM(C1)","formula_interpretation":"explicit","cached_result":"present","text_truncated":true,"source_lengths":["value":raw.utf16.count]]),JSON(["address":"E4","row":4,"column":5,"value":"50","value_type":"number","formula":NSNull()]),JSON(["address":"F4","row":4,"column":6,"value":preview,"value_type":"string","formula":NSNull(),"cached_result":"not_applicable","text_truncated":true,"source_lengths":["value":200]])]
        func source(_ enabled:Bool)->WorkbookGrid {WorkbookGrid(keyboardEnabled:enabled,language:"en",pane:"source-probe",revealIntent:"fixed",cells:cells,rowStart:4,columnStart:4,rowCount:10,columnCount:12,selectedRow:4,selectedColumn:4,onSelect:{_,_ in})}
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
        guard let previewCell=table.view(atColumn:3,row:0,makeIfNecessary:true) as? NSTableCellView else{throw NSError(domain:"LongGridPreviewCellMissing",code:1)}
        try require(previewCell.toolTip?.contains(L("git.savedValuePreview"))==true && previewCell.toolTip?.contains(L("git.gridPreviewRoute"))==true && previewCell.toolTip?.contains(preview)==true,"BoundedGridPreviewClaimedCompleteSavedValue")
        let coordinator=table.dataSource as AnyObject?,origin=scroll.contentView.bounds.origin,selected=table.selectedRow
        try require(window.makeFirstResponder(table),"VisibleGridCouldNotTakeFocus")
        host.rootView=source(false);try await settle()
        try require(tables(host).first===table && (table.dataSource as AnyObject?)===coordinator && table.selectedRow==selected && scroll.contentView.bounds.origin==origin,"HiddenInputGateChangedGridHostOrViewport")
        try require(!table.acceptsFirstResponder && !table.canBecomeKeyView && table.isAccessibilityHidden(),"HiddenGridGateAbsent")
        _ = window.makeFirstResponder(table)
        if let responder=window.firstResponder as? NSView {try require(responder !== table && !responder.isDescendant(of:table),"HiddenGridAllowedReacquisition")}
        for _ in 0..<12 {window.selectNextKeyView(nil);if let responder=window.firstResponder as? NSView {try require(responder !== table && !responder.isDescendant(of:table),"NativeTraversalEnteredHiddenGrid")}}
        host.rootView=source(true);try await settle();try require(!table.isAccessibilityHidden() && window.makeFirstResponder(table),"SourceGridGateDidNotRestore")
        let proof:[String:Any]=["scope":"controlled native WorkbookGrid; raw fixture literal, clipping and public AppKit responder/traversal/AX properties; no OS Full Keyboard Access or VoiceOver claim","raw_value":raw,"raw_utf16":Array(raw.utf16).map(Int.init),"full_saved_value_in_tooltip":true,"single_line_clipping_padding_verified":true,"retained_host_coordinator_viewport_selection":true,"hidden_reacquisition_rejected":true,"native_next_keyview_steps":12,"source_restore_verified":true]
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("grid-source-proof.json"))}
    }

    @MainActor static func checkWorkbookReadingGuidance(_ model:WorkbookModel)async throws {
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        let languages=LanguagePreferences.shared,previous=LanguagePreferences.shared.selection
        defer{languages.selection=previous;model.importPresented=false}
        let revisions:[[String:Any]]=[["revision_occurrence_id":"w0","index":0,"sheets":[]],["revision_occurrence_id":"w1","index":1,"sheets":[]]]
        let host=NSHostingView(rootView:WorkbookEmptyChangesState(model:model)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:220),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()}
        func settle()async throws {try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()}
        func guidance(_ view:NSView)->WorkbookEmptyGuidanceView? {(view as? WorkbookEmptyGuidanceView) ?? view.subviews.lazy.compactMap{guidance($0)}.first}
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
            try require(try model.report.data()==report && model.beforeCell.data()==before && model.afterCell.data()==after,"OpeningNewComparisonMutatedReadingReportOrRawCells")
            model.importPresented=false
            // The query owns the list: a manually equal source pair must not
            // replace a distinct query's truthful empty comparison message.
            model.report=JSON(["report_id":"workbook_report","revisions":revisions]);model.changesFromID="w0";model.changesToID="w1";try await settle()
            try require(model.beforeID==model.afterID && model.emptyChangesKind == .noChanges && view.message.stringValue==L("workbook.changes.empty") && view.importButton.isHidden,"WorkbookEmptyCopyFollowedSourcesInsteadOfQuery")
        }
        let proof:[String:Any]=["scope":"production workbook reading model routes and actual visible native guidance fields/button in synthetic NSHostingView; existing import route reached without submitting a new timeline; no OS gestures","observations":observations,"native_new_comparison_action_reached":true,"report_and_raw_cells_unchanged_by_action":true]
        if let root=ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"] {try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("workbook-reading-proof.json"))}
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
            let document=AppModel();document.initializing=false;document.projectID="header-project";document.zoom=1.5
            document.report=JSON(["report_id":"header-fixed","revisions":(0..<2).map{i in ["revision_occurrence_id":"header-o\(i)","label":"v\(i+1)","assets":[],"pages":[["page_id":"header-p\(i)","page":1],["page_id":"header-next\(i)","page":2]]]}]);document.from=0;document.to=1;document.leftPageID="header-p0";document.rightPageID="header-p1"
            let exactReason="Observed source é / e\u{301}\nFull reason stays selectable."
            document.changes=[JSON(["change_id":"header-change","kind":"text_modified","from_occurrence":"header-o0","to_occurrence":"header-o1","before":"100","after":"120","lineage":["status":"needs_review","reasons":[exactReason]],"evidence":[["revision_occurrence_id":"header-o0","page_id":"header-p0"],["revision_occurrence_id":"header-o1","page_id":"header-p1"]]])];document.selectedChangeID="header-change"
            let layout=WorkspaceLayoutStore(scope:.document),docWindow=window(CompareWorkspace().environmentObject(document).environmentObject(layout))
            try await settle(docWindow)
            guard let docRoot=docWindow.contentView else{throw NSError(domain:"HeaderDocumentRootMissing",code:1)}
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
            facts.append(["workspace":"document","language":locale.rawValue,"actual_native_page_entries":fields.count,"native_editor_retired":true,"hidden_reacquisition_rejected":true,"local_next_previous_steps":24,"evaluated_page_picker_and_pager_disabled":true,"text_overlay_enabled":true,"exact_full_reason_reader_selectable":true,"report_query_source_zoom_and_header_identity_retained":true]);docWindow.close()

            let workbook=WorkbookModel(bridge:document.bridge);workbook.projectID="header-workbook";workbook.reportID="header-workbook-report"
            workbook.report=JSON(["report_id":workbook.reportID,"revisions":(0..<2).map{i in ["revision_occurrence_id":"book-o\(i)","index":i,"sheets":[["sheet_id":"book-s\(i)","name":"Sheet \(i)","row_count":10,"column_count":3],["sheet_id":"other-s\(i)","name":"Other","row_count":10,"column_count":3]]]}]);workbook.beforeID="book-o0";workbook.afterID="book-o1";workbook.beforeSheetID="book-s0";workbook.afterSheetID="book-s1";workbook.changesFromID=workbook.beforeID;workbook.changesToID=workbook.afterID
            let bookWindow=window(WorkbookWorkspace(model:workbook));try await settle(bookWindow)
            guard let bookRoot=bookWindow.contentView else{throw NSError(domain:"WorkbookHeaderRootMissing",code:1)}
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
            facts.append(["workspace":"workbook","language":locale.rawValue,"evaluated_sheet_picker_environments":sheets.count,"hidden_sheet_pickers_disabled":true,"busy_and_range_loading_disable_sheet_pickers":true,"ai_sheet_preserves_inspector_frames_and_source_viewports":true,"text_overlay_enabled":true,"actual_native_grid_hosts":tables.count,"native_popup_views_in_closed_tree":views(bookRoot).compactMap{$0 as? NSPopUpButton}.count,"local_next_previous_steps":24,"source_report_grid_coordinator_viewport_selection_retained":true,"picker_proof_scope":"evaluated production Picker enabled environment; no native popup/OS AX activation claim"]);bookWindow.close()
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
            let fixed=try model.report.data(),source=[model.leftPageID,model.rightPageID];button.performClick(nil)
            for _ in 0..<50 {if let sheet=actionWindow.sheets.first,views(sheet.contentView!).compactMap({$0 as? NSTextField}).contains(where:{$0.isEditable && $0.placeholderString==L("doc.import.projectName")}){break};try await Task.sleep(nanoseconds:10_000_000)}
            try require(model.importSheet,"SoleDocumentNativeImportActionDidNotOpen_target_\(String(describing:button.target))_action_\(String(describing:button.action))_library_\(model.libraryAvailable)_busy_\(model.busy)_loading_\(model.loading)_initializing_\(model.initializing)")
            try require(actionWindow.sheets.first?.contentView.map{views($0).compactMap{$0 as? NSTextField}.contains{$0.isEditable && $0.placeholderString==L("doc.import.projectName") && $0.stringValue==L("doc.import.defaultTitle")}}==true,"SoleDocumentActionDidNotMountExistingImportSheet")
            try require((try model.report.data())==fixed && source==[model.leftPageID,model.rightPageID],"SoleDocumentImportActionChangedFixedReportOrSource");model.importSheet=false
            for _ in 0..<50 {if actionWindow.sheets.isEmpty{break};try await Task.sleep(nanoseconds:10_000_000)};try require(actionWindow.sheets.isEmpty,"SoleDocumentImportSheetDidNotDismiss")
            observations.append(["language":language.rawValue,"native_new_comparison_button_action":true,"only_source_page_field_remains":true,"no_segmented_query_mode":true,"fixed_report_and_source_unchanged":true])
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
            let tables=views(host).compactMap{$0 as? NSTableView},states=tables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds.origin,$0.selectedRow)}
            let requestsBefore=try Data(contentsOf:library.appendingPathComponent("read-events.jsonl"))
            try require(button.isEnabled && !button.visibleRect.isEmpty && button.title==L("workbook.action.cellDetails") && !model.inspectorVisible,"FocusedCellLackedVisibleDetailsAction")
            button.performClick(nil);try await settle(window)
            guard let details=workspaceLayoutMarkers(in:host).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetails"}) else{throw NSError(domain:"ExistingCellInspectorNotMounted",code:1)}
            try require(model.inspectorVisible && !details.visibleRect.isEmpty && details.bounds.width>=250 && model.beforeCell["value"].string.utf16.elementsEqual(raw.utf16),"CellDetailsActionDidNotExposeExistingVerbatimReader")
            try require((try model.report.data())==fixed && (try JSON(model.changes.map(\.raw)).data())==rows && model.comparisonScope==query && identity==[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID] && (try model.beforeCell.data())==before && (try model.afterCell.data())==after && (try Data(contentsOf:library.appendingPathComponent("read-events.jsonl")))==requestsBefore,"OpeningCellDetailsChangedFixedScopeRawSourceOrQueriedAgain")
            for (table,coordinator,origin,row) in states {let actual=table.enclosingScrollView!.contentView.bounds.origin;try require(views(host).contains{$0===table} && (table.dataSource as AnyObject?) === coordinator && actual==origin && table.selectedRow==row,"OpeningCellDetailsRecreatedGridOrMovedManualViewport")}
            let expected=L("workbook.changes.intervalDifference",.verbatim(model.versionLabel("old")),.verbatim(model.versionLabel("later")),.verbatim(model.versionLabel("old")),.verbatim(model.versionLabel("new")))
            try require(model.sourceScopeDescription==expected,"QueryAndSelectedEventScopeCopyWasAmbiguous")
            model.diffMode="text";try await settle(window)
            try require(model.sourceIdentity(before:true).contains("Old source · A2") && model.sourceIdentity(before:false).contains("New source · A2") && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.textSourceIdentity"},"CrossSheetTextIdentityLostNamesOrPhysicalAddresses")
            let savedSheet=model.beforeSheetID;model.beforeSheetID="missing-physical-sheet";try await settle(window)
            try require(model.sourceIdentity(before:true).contains("missing-physical-sheet") && model.missingSourceSheetCaptions.count==1 && model.afterCells.first?["value"].string==raw,"AbsentSheetTextIdentityHidIDOrDiscardedAvailableOppositeSource");model.beforeSheetID=savedSheet;try await settle(window)
            try require(!views(host).compactMap({$0 as? NSTextField}).contains{$0.isEditable && $0.accessibilityIdentifier()=="Docver.workbook.addressInput"} && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.showOriginal" && !$0.visibleRect.isEmpty},"TextModeOfferedInvisibleGridNavigation")
            model.setDiffMode("source");try await settle(window)
            observations.append(["language":language.rawValue,"native_details_action_visible_and_performed":true,"existing_inspector_visible":true,"query_event_copy":model.sourceScopeDescription,"raw_literal":raw,"raw_utf16_preserved":true,"no_new_bridge_requests_or_list_replacement":true,"grid_hosts_and_viewports_retained":true,"text_navigation_explicit_original_route":true])
        }
        model.beforeID="old";model.afterID="old";model.afterSheetID="sheet-old";model.beforeAddress="A2";model.afterAddress="A2";model.beforeCell=JSON(["address":"A2","cached_result":"missing","value":NSNull()]);model.afterCell=model.beforeCell
        try require(model.selectedSourceWarnings.count==1 && model.selectedSourceWarnings[0].hasPrefix(L("doc.common.source")) && model.navigationDetail==L("workbook.nav.singleSourceDetail"),"SingleSourceRetainedPairedWarningsOrFooter")
        // A real diffWorkbooks metadata event has no cell payload or cell warning.
        model.report=JSON(["report_id":"report","revisions":[["revision_occurrence_id":metadataEvent["from_revision_occurrence_id"].string,"index":0],["revision_occurrence_id":metadataEvent["to_revision_occurrence_id"].string,"index":1]]]);model.changes=[metadataEvent];model.changesFromID=metadataEvent["from_revision_occurrence_id"].string;model.changesToID=metadataEvent["to_revision_occurrence_id"].string;await model.chooseChange(metadataEvent["change_id"].string);model.diffMode="text";try await settle(window)
        try require(model.showingSheetMetadata && model.selectedSourceWarnings.isEmpty && model.beforeCell.isNull && model.afterCell.isNull && workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue=="Reviset.workbook.sheetMetadataDiff"} && !workspaceLayoutMarkers(in:host).contains{$0.identifier?.rawValue.hasPrefix("Reviset.workbook.rawField.")==true},"ActualMetadataEventMislabelledUnmaterializedCell")
        var cellEvent=metadataEvent.dictionary;cellEvent["kind"]="cell_observation";model.changes=[JSON(cellEvent)];try require(!model.showingSheetMetadata && model.selectedSourceWarnings.count==2,"NullCellEventLostUnmaterializedObservationWarnings")
        let document=AppModel();document.report=JSON(["report_id":"fixed","revisions":[["revision_occurrence_id":"a"],["revision_occurrence_id":"b"]]]);document.from=0;document.to=1;document.diffMode="text"
        let docWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:500),styleMask:[.titled],backing:.buffered,defer:false);docWindow.isReleasedWhenClosed=false;docWindow.contentView=NSHostingView(rootView:DocumentUnifiedDiff().environmentObject(document));docWindow.orderFront(nil);defer{docWindow.close()};try await settle(docWindow)
        try require(!workspaceLayoutMarkers(in:docWindow.contentView!).contains{$0.identifier?.rawValue=="Reviset.document.selectedEventHeader"},"UnselectedDocumentDiffClaimedSelectedEvent")
        document.changes=[JSON(["change_id":"selected","kind":"text_modified","before":"100","after":"120"])];document.selectedChangeID="selected";try await settle(docWindow)
        try require(workspaceLayoutMarkers(in:docWindow.contentView!).contains{$0.identifier?.rawValue=="Reviset.document.selectedEventHeader"},"SelectedDocumentEventHeaderMissing")
        try JSONSerialization.data(withJSONObject:["scope":"controlled production WorkbookWorkspace/AppKit button and DocumentUnifiedDiff; synthetic cell fixture plus real diffWorkbooks date_system event; no submitted import or OS input","observations":observations,"single_source_warning_and_footer":true,"real_engine_metadata_event":metadataEvent.raw,"metadata_caption_has_no_cell_warning_or_field_rows":true,"null_cell_event_keeps_unmaterialized_warning":true,"selected_null_document_header_hidden":true],options:[.sortedKeys]).write(to:URL(fileURLWithPath:data).appendingPathComponent("source16-proof.json"))
    }

}
