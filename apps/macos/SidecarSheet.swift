import SwiftUI

struct OnlyOfficeSidecarSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: SidecarRequest
    @State private var payload = JSON()
    @State private var failureMessage=UIMessage.raw("")
    private var failure:String {get{failureMessage.text} nonmutating set{failureMessage = .raw(newValue)}}
    @State private var shownPage = 1
    @State private var pageInput = "1"
    @State private var zoom = 0.0
    @State private var warningsOpen = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(L("doc.sidecar.title", .verbatim(request.label))).readableFont(.headline)
                    Text(payload.isNull ? L("doc.tail.onlyOfficeLocalConversion"):L("doc.tail.rendererVersionPageMappingEstimate", .verbatim(payload["renderer"].string), .verbatim(payload["version"].string))).readableFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !payload.isNull {
                    Button { go(shownPage-1) } label: {Image(systemName:"chevron.left")}.disabled(shownPage<=1).accessibilityLabel(L("doc.tail.previousReferencePage"))
                    TextField(L("doc.tail.referencePage"),text:$pageInput).frame(width:72).onSubmit{go(Int(pageInput) ?? shownPage)}
                    Text("/ \(payload["pages"].int)").readableFont(.caption).foregroundStyle(.secondary)
                    Button { go(shownPage+1) } label: {Image(systemName:"chevron.right")}.disabled(shownPage>=payload["pages"].int).accessibilityLabel(L("doc.tail.nextReferencePage"))
                    Picker(L("doc.common.zoom"),selection:$zoom){Text(L("doc.tail.fit")).tag(0.0);Text("100%").tag(1.0);Text("150%").tag(1.5);Text("200%").tag(2.0)}.frame(width:110)
                }
                Button(L("doc.common.close")){dismiss()}.keyboardShortcut(.cancelAction)
            }
            Text(L("doc.tail.referenceConversionMayDifferFromPowerPoint"))
                .readableFont(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            Text(L("doc.tail.hiddenOrNonUniquePagesLimitConversion"))
                .readableFont(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            if !failure.isEmpty {
                ContentUnavailableView(L("doc.tail.referenceViewOpenFailed"),systemImage:"exclamationmark.triangle",description:Text(failure)).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if payload.isNull {
                VStack(spacing:12){ProgressView(L("doc.tail.checkingSourceAndPageMapping"));Button(L("doc.tail.cancelConversion")){dismiss()}}
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                OriginalPDFView(path:payload["path"].string,pageNumber:shownPage,zoom:zoom,evidence:JSON(),page:JSON())
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                DisclosureGroup(L("doc.tail.renderingCheckItems"),isExpanded:$warningsOpen) {
                    ScrollView {
                        VStack(alignment:.leading,spacing:5) {
                            ForEach(payload["warnings"].array.indices,id:\.self){index in
                                Text(renderWarningName(payload["warnings"].array[index].string)).readableFont(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading)
                            }
                            if payload["omitted_font_warnings"].int>0 {Text(LC("doc.tail.additionalFontCheckItemCount", payload["omitted_font_warnings"].int)).readableFont(.caption).foregroundStyle(.orange)}
                        }
                    }.frame(maxHeight:130)
                }
            }
        }.padding(16).frame(minWidth:850,idealWidth:1200,minHeight:600,idealHeight:820).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light).readableInterface()
        .task {
            guard !Task.isCancelled,model.sidecarRequest?.id==request.id else{return}
            do {
                let result=try await model.bridge.call("sidecarCreate",request.scope,owner:request.owner)
                if !Task.isCancelled,model.sidecarRequest?.id==request.id {payload=result;model.sidecarResult=result;shownPage=result["page"].int;pageInput=String(shownPage)}
            } catch {if !Task.isCancelled,model.sidecarRequest?.id==request.id {failureMessage=bridgeErrorMessage(error);model.sidecarFailureMessage=failureMessage}}
        }
    }
    private func go(_ value:Int){guard value>=1&&value<=payload["pages"].int else{pageInput=String(shownPage);return};shownPage=value;pageInput=String(value)}
}
