import Foundation
import AppKit
import SwiftUI

enum Smoke { @MainActor static func captureView(_ window:NSWindow,_ url:URL)throws {throw NSError(domain:"UnexpectedScreenshotInModelProbe",code:1)} }

private struct PageColumnProbeHarness:View {
    @ObservedObject var model:AppModel
    var body:some View {PageColumn(revision:model.revision(0),side:"Source",pageID:$model.leftPageID).environmentObject(model)}
}

@main struct GitDiffWorkspaceProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        func require(_ value:Bool,_ name:String)throws {if !value {throw NSError(domain:name,code:1)}}
        for (before,after) in [("100","120"),("a\nb\na","a\na\nb"),("", ""),("a\n","\na"),("문서 👨‍👩‍👧‍👦\r\n금액 100", "문서 👨‍👩‍👧‍👦\r\n금액 120"),("a\r\nb", "a\nb"),("a\rb", "a\rc"),("é", "e\u{301}"),("e\u{301}","é"),("각\n내용", "\u{1100}\u{1161}\u{11a8}\n내용")] {
            let diff=unifiedTextDiff(before:before,after:after,semantic:true)
            try require(diff.bounded && diff.semantic,"UnexpectedDiffFallback")
            try require(Array(diff.lines.filter{$0.prefix != "+"}.map(\.text).joined(separator:"\n").utf16)==Array(before.utf16),"BeforeTextChangedByDiff")
            try require(Array(diff.lines.filter{$0.prefix != "−"}.map(\.text).joined(separator:"\n").utf16)==Array(after.utf16),"AfterTextChangedByDiff")
        }
        for long in [String(repeating:"가",count:4097),String(repeating:"😀",count:2049),String(repeating:"x\n",count:128)] {
            let diff=unifiedTextDiff(before:long,after:"short",semantic:true)
            try require(!diff.bounded && diff.lines.isEmpty && !diff.semantic,"ExceededDiffBoundOrPresentedTruncatedText")
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
        let workbook=WorkbookModel(bridge:model.bridge);await workbook.start();workbook.projectID="workbook";workbook.reportID="workbook_report";workbook.report=JSON(["report_id":"workbook_report","revisions":[["revision_occurrence_id":"w0","index":0,"sheets":[]],["revision_occurrence_id":"w1","index":1,"sheets":[]]]]);workbook.beforeID="w0";workbook.afterID="w1";workbook.changesFromID="w0";workbook.changesToID="w1"
        workbook.diffMode="text";await workbook.selectVersion("w0");try require(workbook.diffMode=="source" && workbook.effectiveDiffMode=="source","WorkbookVersionMenuKeptTextOverlay")
        try require(workbook.beforeID=="w0" && workbook.afterID=="w0" && workbook.changesFromID=="w0" && workbook.changesToID=="w0" && workbook.changes.isEmpty && !workbook.loadingChanges && workbook.changesFailure.isEmpty,"WorkbookFirstVersionDidNotReadSingleSource")
        workbook.beforeID="w0";workbook.afterID="w1";workbook.changesFromID="w0";workbook.changesToID="w1";workbook.diffMode="text"
        await workbook.changeVersions(before:"w0",after:"w0");try require(workbook.diffMode=="source" && workbook.effectiveDiffMode=="source" && workbook.beforeID==workbook.afterID,"WorkbookEndpointPickerKeptTextOverlay")
        workbook.setDiffMode("text");try require(workbook.diffMode=="source","SingleWorkbookReadAllowedTextPicker")
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
        let cells=[JSON(["address":"D4","row":4,"column":4,"value":raw,"value_type":"string","formula":NSNull(),"cached_result":"not_applicable","source_lengths":["value":raw.utf16.count]]),JSON(["address":"E4","row":4,"column":5,"value":"50","value_type":"number","formula":NSNull()])]
        func source(_ enabled:Bool)->WorkbookGrid {WorkbookGrid(keyboardEnabled:enabled,language:"en",pane:"source-probe",revealIntent:"fixed",cells:cells,rowStart:4,columnStart:4,rowCount:10,columnCount:12,selectedRow:4,selectedColumn:4,onSelect:{_,_ in})}
        let host=NSHostingView(rootView:source(true)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:300),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host;window.orderFront(nil);defer{window.close()}
        func settle()async throws {try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()}
        func tables(_ view:NSView)->[NSTableView] {(view as? NSTableView).map{[$0]} ?? view.subviews.flatMap{tables($0)}}
        try await settle()
        guard let table=tables(host).first,let cell=table.view(atColumn:1,row:0,makeIfNecessary:true) as? NSTableCellView,let text=cell.textField,let scroll=table.enclosingScrollView else{throw NSError(domain:"ActualGridSourceCellMissing",code:1)}
        try require(text.stringValue==raw && cell.toolTip?.contains(raw)==true,"RawStoredValueReplacedOrMissingFromTooltip")
        try require(text.maximumNumberOfLines==1 && text.lineBreakMode == .byTruncatingTail && cell.layer?.masksToBounds==true && text.frame.minX>=2 && text.frame.maxX<=cell.bounds.maxX-2,"RawGridCellNotSingleLineClippedPadded_lines_\(text.maximumNumberOfLines)_mode_\(text.lineBreakMode.rawValue)_clip_\(String(describing:cell.layer?.masksToBounds))_text_\(text.frame)_cell_\(cell.bounds)")
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

}
