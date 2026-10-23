import SwiftUI

struct MappingSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let projectID: String
    let reportID: String
    let draftHash: String
    let before: JSON
    let after: JSON
    @State var left: Set<String>
    @State var right: Set<String>
    @State var mode = "continuation"
    @State var reason = ""
    @State private var leftSearch = ""
    @State private var rightSearch = ""
    @State private var saving = false
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    var validationMessage: String? {
        if max(left.count,right.count)>32 { return L("doc.tail.max32PagesPerSide") }
        if mode == "split" && !(left.count==1 && right.count>=2) { return L("doc.tail.splitSelectOneEarlierTwoOrMoreLater") }
        if mode == "merge" && !(left.count>=2 && right.count==1) { return L("doc.tail.mergeSelectTwoOrMoreEarlierOneLater") }
        if (mode == "continuation" || mode == "unlink") && !(left.count==1 && right.count==1) { return L("doc.tail.selectOnePageEachSide") }
        if reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return L("doc.tail.enterChangeReason") }
        if reason.utf16.count>2000 { return LC("doc.tail.changeReasonExceedsLimitByUnits", reason.utf16.count-2000) }
        return nil
    }
    var valid: Bool { validationMessage == nil }
    var selectedEdges:[JSON] {model.report["matches"].array.filter{left.contains($0["from_page_id"].string)&&right.contains($0["to_page_id"].string)}}
    var currentSelectionText:String {
        let values=selectedEdges.map{edge in edgeLabel(edge)+" · "+(edge["status"].string=="human_confirmed" ? L("doc.matching.humanConfirmed"):edge["status"].string=="needs_review" ? L("doc.matching.needsReview"):L("doc.matching.inferred"))}
        return L("doc.mapping.savedSelection", .verbatim(values.isEmpty ? L("doc.tail.noDirectLink"):values.joined(separator:" / ")))
    }
    var conflicts: [JSON] {
        model.report["matches"].array.filter { edge in
            let a=edge["from_page_id"].string,b=edge["to_page_id"].string
            return mode == "unlink" ? left.contains(a) && right.contains(b) : (left.contains(a) || right.contains(b)) && !(left.contains(a) && right.contains(b))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(L("doc.tail.editPageMapping")).font(.title2.weight(.semibold)); Spacer(); Button(L("doc.common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving) }
            ScrollView { VStack(alignment:.leading,spacing:10) {
            Picker(L("doc.tail.mappingType"), selection: $mode) { Text(L("doc.tail.linkOneToOne")).tag("continuation"); Text(L("doc.tail.splitOneToMany")).tag("split"); Text(L("doc.tail.mergeManyToOne")).tag("merge"); Text(L("doc.tail.unlinkAndBlock")).tag("unlink") }.pickerStyle(.segmented).disabled(saving)
            Text(L("doc.tail.wordingChangeReviewedSeparatelyNewReport")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                pageList(before, search: $leftSearch, selection: $left, title: L("doc.tail.earlierVersion"))
                Image(systemName: mode == "split" ? "arrow.triangle.branch" : mode == "merge" ? "arrow.triangle.merge" : mode == "unlink" ? "scissors" : "arrow.right").foregroundStyle(.secondary)
                pageList(after, search: $rightSearch, selection: $right, title: L("doc.tail.laterVersion"))
            }.disabled(saving)
            Text(L("doc.mapping.selectionCounts", .verbatim(LC("doc.mapping.earlierPages", left.count)), .verbatim(LC("doc.mapping.laterPages", right.count)))).font(.callout.weight(.medium))
            Text(currentSelectionText).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(currentSelectionText)
            Text(L("doc.tail.otherSimilarCandidatesMayExist")).font(.caption2).foregroundStyle(.secondary)
            if !conflicts.isEmpty {
                Text(LC("doc.tail.existingMappingsRemovedBranchesKept", conflicts.count)).font(.caption).foregroundStyle(.orange)
                ScrollView(.horizontal) { HStack { ForEach(Array(conflicts.enumerated()), id: \.offset) { _,edge in Text(edgeLabel(edge)).font(.caption2).padding(5).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 4)) } } }.frame(maxHeight: 34)
            }
            if mode == "unlink" { Text(conflicts.isEmpty ? L("doc.tail.noCurrentLinkBlocksAutoPair") : L("doc.tail.unlinkOneKeepOtherBranches")).font(.caption).foregroundStyle(.secondary) }
            TextField(L("doc.tail.changeReasonRequired"), text: $reason, axis:.vertical).lineLimit(2...3).textFieldStyle(.roundedBorder).disabled(saving)
            if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.red) }
            }.frame(maxWidth:.infinity,alignment:.leading) }
            HStack { if let message=validationMessage { Text(message).foregroundStyle(message==L("doc.tail.enterChangeReason") ? Color.secondary:Color.orange) };Spacer();Text(L("doc.tail.inputLengthOf2000", .integer(reason.utf16.count))).help(L("doc.tail.someEmojiCountAsMultipleUnits")).foregroundStyle(reason.utf16.count>2000 ? Color.orange : Color.secondary) }.font(.caption)

            HStack { Text(L("doc.tail.cancelBeforeApplyDoesNotSave")).font(.caption).foregroundStyle(.secondary); Spacer(); if saving { ProgressView().controlSize(.small) }; Button(L("doc.tail.applyAndReanalyze")) { Task { await apply() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!valid || saving || model.busy).accessibilityHint(Text(validationMessage ?? L("doc.tail.applySelectedRelationAnalyzeNewReport"))) }
        }.padding(24).frame(width: 900, height: 720).background(Color(nsColor:.windowBackgroundColor))
    }
    func pageList(_ revision: JSON, search: Binding<String>, selection: Binding<Set<String>>, title: String) -> some View {
        let all=model.primaryPages(revision),selected=all.filter { selection.wrappedValue.contains($0["page_id"].string) }
        let pages=all.filter { page in search.wrappedValue.isEmpty || String(page["page"].int).contains(search.wrappedValue) || page["text"].string.localizedCaseInsensitiveContains(search.wrappedValue) }
        let hiddenCount=selected.filter { chosen in !pages.contains { $0["page_id"].string == chosen["page_id"].string } }.count
        return ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                Text(title + " · " + revision["label"].string).font(.headline)
                TextField(L("doc.tail.searchNumberOrSummary"), text: search).textFieldStyle(.roundedBorder)
                List(pages, selection: selection) { page in HStack(alignment: .top) { Text("p.\(page["page"].int)").monospacedDigit().frame(width: 50, alignment: .leading); Text(page["text"].string.isEmpty ? L("doc.tail.noSummaryRead") : page["text"].string).lineLimit(2).font(.caption) }.padding(.vertical, 4).tag(page["page_id"].string).id(page["page_id"].string) }.frame(height:280).scrollIndicators(.visible)
                ScrollView(.horizontal) {
                    HStack(spacing:5) {
                        Text(L("doc.tail.selectedColon")).font(.caption2).foregroundStyle(.secondary)
                        ForEach(selected) { page in
                            HStack(spacing:4) {
                                Button("p.\(page["page"].int)") { search.wrappedValue="";Task { @MainActor in await Task.yield();proxy.scrollTo(page["page_id"].string,anchor:.center) } }.buttonStyle(.plain)
                                Button { selection.wrappedValue.remove(page["page_id"].string) } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel(L("doc.tail.deselectPage", .integer(page["page"].int)))
                            }.font(.caption).padding(5).background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:4))
                        }
                    }
                }.frame(height:30).accessibilityElement(children:.contain).accessibilityLabel(L("doc.mapping.selectionAccessibility", .verbatim(title), .verbatim(LC("doc.mapping.selectedPages",selected.count)), .verbatim(selected.map { String($0["page"].int) }.joined(separator:", "))))
                Text(hiddenCount>0 ? LC("doc.tail.selectedPagesOutsideSearchJump", hiddenCount) : LC("doc.tail.pageListScrollSearchMultiSelect", pages.count)).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).task { if let page=selected.first { await Task.yield();proxy.scrollTo(page["page_id"].string,anchor:.center) } }
        }
    }

    func edgeLabel(_ edge: JSON) -> String {
        let a=model.primaryPages(before).first { $0["page_id"].string == edge["from_page_id"].string },b=model.primaryPages(after).first { $0["page_id"].string == edge["to_page_id"].string }
        return "p.\(a?["page"].int ?? 0) → p.\(b?["page"].int ?? 0)"
    }
    func apply() async {
        guard valid && !saving else { return };saving=true
        do {
            try await model.applyRelation(project: projectID, report: reportID, draftHash: draftHash, before: before["revision_occurrence_id"].string, after: after["revision_occurrence_id"].string, left: Array(left), right: Array(right), kind: mode, reason: reason)
            dismiss(); await model.run(projectID)
        } catch { failureMessage=bridgeErrorMessage(error);saving=false }
    }
}
