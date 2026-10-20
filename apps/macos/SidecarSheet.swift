import SwiftUI

struct OnlyOfficeSidecarSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: SidecarRequest
    @State private var payload = JSON()
    @State private var failure = ""
    @State private var shownPage = 1
    @State private var pageInput = "1"
    @State private var zoom = 0.0
    @State private var warningsOpen = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(request.label+" · 참고 변환 화면").font(.headline)
                    Text(payload.isNull ? "ONLYOFFICE · 로컬 변환":"\(payload["renderer"].string) \(payload["version"].string) · 페이지 대응 추정").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !payload.isNull {
                    Button { go(shownPage-1) } label: {Image(systemName:"chevron.left")}.disabled(shownPage<=1).accessibilityLabel("이전 참고 페이지")
                    TextField("참고 페이지",text:$pageInput).frame(width:55).onSubmit{go(Int(pageInput) ?? shownPage)}
                    Text("/ \(payload["pages"].int)").font(.caption).foregroundStyle(.secondary)
                    Button { go(shownPage+1) } label: {Image(systemName:"chevron.right")}.disabled(shownPage>=payload["pages"].int).accessibilityLabel("다음 참고 페이지")
                    Picker("확대",selection:$zoom){Text("맞춤").tag(0.0);Text("100%").tag(1.0);Text("150%").tag(1.5);Text("200%").tag(2.0)}.frame(width:110)
                }
                Button("닫기"){dismiss()}.keyboardShortcut(.cancelAction)
            }
            Text("PowerPoint와 다를 수 있는 참고 변환 화면입니다. 저장된 변경 이력과 AI 조회 결과에는 반영하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            Text("숨김 슬라이드나 고유 문구가 없는 페이지가 있으면 페이지 대응을 확인할 수 없어 참고 변환이 제한됩니다.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            if !failure.isEmpty {
                ContentUnavailableView("참고 화면을 열지 못했습니다",systemImage:"exclamationmark.triangle",description:Text(failure)).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if payload.isNull {
                VStack(spacing:12){ProgressView("원문과 페이지 대응을 확인하고 있습니다…");Button("변환 취소"){dismiss()}}
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                OriginalPDFView(path:payload["path"].string,pageNumber:shownPage,zoom:zoom,evidence:JSON(),page:JSON())
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                DisclosureGroup("렌더링 확인 항목",isExpanded:$warningsOpen) {
                    ScrollView {
                        VStack(alignment:.leading,spacing:5) {
                            ForEach(payload["warnings"].array.indices,id:\.self){index in
                                Text(payload["warnings"].array[index].string).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading)
                            }
                            if payload["omitted_font_warnings"].int>0 {Text("추가 글꼴 확인 항목 \(payload["omitted_font_warnings"].int)개").font(.caption).foregroundStyle(.orange)}
                        }
                    }.frame(maxHeight:130)
                }
            }
        }.padding(16).frame(minWidth:850,idealWidth:1200,minHeight:600,idealHeight:820)
        .task {
            do {
                let result=try await model.bridge.call("sidecarCreate",request.scope)
                if !Task.isCancelled,model.sidecarRequest?.id==request.id {payload=result;model.sidecarResult=result;shownPage=result["page"].int;pageInput=String(shownPage)}
            } catch {if !Task.isCancelled,model.sidecarRequest?.id==request.id {failure=error.localizedDescription;model.sidecarFailure=failure}}
        }
        .onDisappear {
            let bridge=model.bridge,scope=request.scope
            Task { _ = try? await bridge.call("sidecarClose",scope) }
        }
    }
    private func go(_ value:Int){guard value>=1&&value<=payload["pages"].int else{pageInput=String(shownPage);return};shownPage=value;pageInput=String(value)}
}
