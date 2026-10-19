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
    var valid: Bool {
        let cardinality = mode == "split" ? left.count == 1 && right.count >= 2 : mode == "merge" ? left.count >= 2 && right.count == 1 : left.count == 1 && right.count == 1
        return cardinality && max(left.count, right.count) <= 32 && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.utf16.count <= 2000
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
            Picker("대응 유형", selection: $mode) { Text("연결 1:1").tag("continuation"); Text("분할 1:N").tag("split"); Text("병합 N:1").tag("merge"); Text("연결 해제").tag("unlink") }.pickerStyle(.segmented).disabled(saving)
            Text("문구의 삭제·변경 여부는 원문 근거로 별도 검토합니다. 페이지 대응을 적용하면 새 보고서를 분석합니다.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                pageList(before, search: $leftSearch, selection: $left, title: "이전 버전")
                Image(systemName: mode == "split" ? "arrow.triangle.branch" : mode == "merge" ? "arrow.triangle.merge" : mode == "unlink" ? "link.badge.plus" : "arrow.right").foregroundStyle(.secondary)
                pageList(after, search: $rightSearch, selection: $right, title: "이후 버전")
            }.disabled(saving)
            Text("이전 \(left.count)쪽 → 이후 \(right.count)쪽 · 한 관계에서 최대 32쪽 선택").font(.callout.weight(.medium))
            if !conflicts.isEmpty {
                Text("기존 대응 \(conflicts.count)개가 해제됩니다. 남은 분기들은 유지되며, 한 쌍만 남으면 1:1 연결로 바뀝니다.").font(.caption).foregroundStyle(.orange)
                ScrollView(.horizontal) { HStack { ForEach(Array(conflicts.enumerated()), id: \.offset) { _,edge in Text(edgeLabel(edge)).font(.caption2).padding(5).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 4)) } } }.frame(maxHeight: 34)
            }
            TextField("수정 이유 (필수, 최대 2,000자)", text: $reason).textFieldStyle(.roundedBorder).disabled(saving)
            if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.red) }
            HStack { Text("적용 전 취소하면 저장하지 않습니다.").font(.caption).foregroundStyle(.secondary); Spacer(); if saving { ProgressView().controlSize(.small) }; Button("적용하고 재분석") { Task { await apply() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!valid || saving || model.busy) }
        }.padding(24).frame(width: 900, height: 650)
    }
    func pageList(_ revision: JSON, search: Binding<String>, selection: Binding<Set<String>>, title: String) -> some View {
        let pages=model.primaryPages(revision).filter { page in search.wrappedValue.isEmpty || String(page["page"].int).contains(search.wrappedValue) || page["text"].string.localizedCaseInsensitiveContains(search.wrappedValue) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title + " · " + revision["label"].string).font(.headline)
            TextField("번호·요약 검색", text: search).textFieldStyle(.roundedBorder)
            List(pages, selection: selection) { page in HStack(alignment: .top) { Text("p.\(page["page"].int)").monospacedDigit().frame(width: 50, alignment: .leading); Text(page["text"].string.isEmpty ? "판독된 요약 없음" : page["text"].string).lineLimit(3).font(.caption) }.padding(.vertical, 4).tag(page["page_id"].string) }
            Text("⌘ 클릭·⇧ 클릭으로 여러 페이지 선택").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
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
