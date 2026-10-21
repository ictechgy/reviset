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
    @State private var failure = ""
    var validationMessage: String? {
        if max(left.count,right.count)>32 { return "한쪽에서 최대 32쪽까지 선택할 수 있습니다." }
        if mode == "split" && !(left.count==1 && right.count>=2) { return "분할은 이전 1쪽, 이후 2쪽 이상을 선택하세요." }
        if mode == "merge" && !(left.count>=2 && right.count==1) { return "병합은 이전 2쪽 이상, 이후 1쪽을 선택하세요." }
        if (mode == "continuation" || mode == "unlink") && !(left.count==1 && right.count==1) { return "양쪽 페이지를 하나씩 선택하세요." }
        if reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return "수정 이유를 입력하세요." }
        if reason.utf16.count>2000 { return "수정 이유가 한도를 \(reason.utf16.count-2000)단위 넘었습니다." }
        return nil
    }
    var valid: Bool { validationMessage == nil }
    var selectedEdges:[JSON] {model.report["matches"].array.filter{left.contains($0["from_page_id"].string)&&right.contains($0["to_page_id"].string)}}
    var currentSelectionText:String {
        let values=selectedEdges.map{edge in edgeLabel(edge)+" · "+(edge["status"].string=="human_confirmed" ? "사용자 확정":edge["status"].string=="needs_review" ? "검토 필요 후보":"추정 대응")}
        return "현재 선택의 저장된 대응: "+(values.isEmpty ? "직접 연결 없음":values.joined(separator:" / "))
    }
    var conflicts: [JSON] {
        model.report["matches"].array.filter { edge in
            let a=edge["from_page_id"].string,b=edge["to_page_id"].string
            return mode == "unlink" ? left.contains(a) && right.contains(b) : (left.contains(a) || right.contains(b)) && !(left.contains(a) && right.contains(b))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("페이지 대응 수정").font(.title2.weight(.semibold)); Spacer(); Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving) }
            Picker("대응 유형", selection: $mode) { Text("연결 1:1").tag("continuation"); Text("분할 1:N").tag("split"); Text("병합 N:1").tag("merge"); Text("해제·차단").tag("unlink") }.pickerStyle(.segmented).disabled(saving)
            Text("문구의 삭제·변경 여부는 원문 근거로 별도 검토합니다. 페이지 대응을 적용하면 새 보고서를 분석합니다.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                pageList(before, search: $leftSearch, selection: $left, title: "이전 버전")
                Image(systemName: mode == "split" ? "arrow.triangle.branch" : mode == "merge" ? "arrow.triangle.merge" : mode == "unlink" ? "scissors" : "arrow.right").foregroundStyle(.secondary)
                pageList(after, search: $rightSearch, selection: $right, title: "이후 버전")
            }.disabled(saving)
            Text("이전 \(left.count)쪽 → 이후 \(right.count)쪽 · 한쪽 최대 32쪽 선택").font(.callout.weight(.medium))
            Text(currentSelectionText).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(currentSelectionText)
            Text("표시된 연결 외에 다른 유사 후보가 있을 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
            if !conflicts.isEmpty {
                Text("기존 대응 \(conflicts.count)개가 해제됩니다. 남은 분기들은 유지되며, 한 쌍만 남으면 1:1 연결로 바뀝니다.").font(.caption).foregroundStyle(.orange)
                ScrollView(.horizontal) { HStack { ForEach(Array(conflicts.enumerated()), id: \.offset) { _,edge in Text(edgeLabel(edge)).font(.caption2).padding(5).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 4)) } } }.frame(maxHeight: 34)
            }
            if mode == "unlink" { Text(conflicts.isEmpty ? "현재 연결은 없습니다. 적용하면 이 두 페이지의 자동 연결을 차단합니다. 한 번에 한 쌍을 지정합니다." : "한 번에 한 연결을 해제합니다. 나머지 분기 연결은 유지합니다.").font(.caption).foregroundStyle(.secondary) }
            TextField("수정 이유 (필수)", text: $reason, axis:.vertical).lineLimit(3...5).textFieldStyle(.roundedBorder).disabled(saving)
            HStack { if let message=validationMessage { Text(message).foregroundStyle(.orange) };Spacer();Text("입력 길이 \(reason.utf16.count)/2000").help("일부 이모지는 여러 단위로 계산됩니다.").foregroundStyle(reason.utf16.count>2000 ? Color.orange : Color.secondary) }.font(.caption)

            if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.red) }
            HStack { Text("적용 전 취소하면 저장하지 않습니다.").font(.caption).foregroundStyle(.secondary); Spacer(); if saving { ProgressView().controlSize(.small) }; Button("적용하고 재분석") { Task { await apply() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!valid || saving || model.busy).accessibilityHint(Text(validationMessage ?? "선택한 관계를 적용하고 새 보고서로 분석합니다")) }
        }.padding(24).frame(width: 900, height: 650).background(Color(nsColor:.windowBackgroundColor))
    }
    func pageList(_ revision: JSON, search: Binding<String>, selection: Binding<Set<String>>, title: String) -> some View {
        let all=model.primaryPages(revision),selected=all.filter { selection.wrappedValue.contains($0["page_id"].string) }
        let pages=all.filter { page in search.wrappedValue.isEmpty || String(page["page"].int).contains(search.wrappedValue) || page["text"].string.localizedCaseInsensitiveContains(search.wrappedValue) }
        let hiddenCount=selected.filter { chosen in !pages.contains { $0["page_id"].string == chosen["page_id"].string } }.count
        return ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                Text(title + " · " + revision["label"].string).font(.headline)
                TextField("번호·요약 검색", text: search).textFieldStyle(.roundedBorder)
                List(pages, selection: selection) { page in HStack(alignment: .top) { Text("p.\(page["page"].int)").monospacedDigit().frame(width: 50, alignment: .leading); Text(page["text"].string.isEmpty ? "판독된 요약 없음" : page["text"].string).lineLimit(3).font(.caption) }.padding(.vertical, 4).tag(page["page_id"].string).id(page["page_id"].string) }
                ScrollView(.horizontal) {
                    HStack(spacing:5) {
                        Text("선택:").font(.caption2).foregroundStyle(.secondary)
                        ForEach(selected) { page in
                            HStack(spacing:4) {
                                Button("p.\(page["page"].int)") { search.wrappedValue="";Task { @MainActor in await Task.yield();proxy.scrollTo(page["page_id"].string,anchor:.center) } }.buttonStyle(.plain)
                                Button { selection.wrappedValue.remove(page["page_id"].string) } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("페이지 \(page["page"].int) 선택 해제")
                            }.font(.caption).padding(5).background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:4))
                        }
                    }
                }.frame(height:30).accessibilityElement(children:.contain).accessibilityLabel("\(title) 선택 \(selected.count)쪽: "+selected.map { String($0["page"].int) }.joined(separator:", "))
                Text(hiddenCount>0 ? "검색 결과 밖 선택 \(hiddenCount)쪽 · 위 번호를 누르면 이동합니다" : "⌘ 클릭·⇧ 클릭으로 여러 페이지 선택").font(.caption2).foregroundStyle(.secondary)
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
        } catch { failure=error.localizedDescription;saving=false }
    }
}
