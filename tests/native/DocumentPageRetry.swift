import Foundation
import AppKit
import SwiftUI
import PDFKit

private struct RetryHarness:View {
    @ObservedObject var model:AppModel
    var body:some View {HStack {
        PageColumn(revision:model.revision(0),side:"Before",pageID:$model.leftPageID)
        PageColumn(revision:model.revision(1),side:"After",pageID:$model.rightPageID)
    }.environmentObject(model)}
}
@main struct DocumentPageRetryProbe {
    @MainActor static func main() {
        let application=NSApplication.shared;application.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {try await check();print("PASS native document page Retry preserves both fixed sources");exit(0)}
            catch {FileHandle.standardError.write(Data("FAIL page Retry: \(error)\n".utf8));exit(1)}
        }
        application.run()
    }
    @MainActor static func check()async throws {
        configureLegacyNativeLocalization()
        let model=AppModel(),folder=model.bridge.library
        let pdf=PDFDocument(),page=PDFPage();page.setBounds(NSRect(x:0,y:0,width:400,height:500),for:.mediaBox);pdf.insert(page,at:0)
        guard pdf.write(to:folder.appendingPathComponent("source.pdf")) else{throw NSError(domain:"FixturePDF",code:1)}
        func revision(_ id:String,_ pageID:String)->[String:Any] {[
            "revision_occurrence_id":id,"label":id,"assets":[["asset_id":"asset","format":"pdf"]],
            "pages":[["page_id":pageID,"asset_id":"asset","page":1,"width":400,"height":500,"text":"source"]]
        ]}
        model.projectID="project";model.report=JSON(["report_id":"fixed-report","revisions":[revision("before","left"),revision("after","right")]])
        model.from=0;model.to=1;model.leftPageID="left";model.rightPageID="right"
        let original=try model.report.data()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:740),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:RetryHarness(model:model));window.orderFront(nil)
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        func settle(_ condition:()->Bool)async throws {
            for _ in 0..<250 {window.contentView?.layoutSubtreeIfNeeded();if condition(){return};try await Task.sleep(nanoseconds:20_000_000)}
            throw NSError(domain:"RetryTimedOut",code:1)
        }
        try await settle {views(window.contentView!).contains{($0 as? NSButton)?.identifier?.rawValue=="Reviset.document.retryPage.before"} && views(window.contentView!).compactMap{$0 as? OriginalPDFHostView}.contains{$0.representedPageID=="right"}}
        let peer=views(window.contentView!).compactMap{$0 as? OriginalPDFHostView}.first{$0.representedPageID=="right"}!
        let peerDocument=peer.document,peerPage=peer.currentPage,peerScale=peer.scaleFactor
        let button=views(window.contentView!).compactMap{$0 as? NSButton}.first{$0.identifier?.rawValue=="Reviset.document.retryPage.before"}!
        guard button.isEnabled,!button.visibleRect.isEmpty else{throw NSError(domain:"RetryNotVisible",code:1)}
        button.performClick(nil)
        try await settle {views(window.contentView!).compactMap{$0 as? OriginalPDFHostView}.contains{$0.representedPageID=="left"}}
        let events=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("attempts.json"))) as! [[String:Any]]
        guard events.filter({$0["page_id"] as? String=="left"}).count==2,events.filter({$0["page_id"] as? String=="right"}).count==1,
              events.allSatisfy({$0["report_id"] as? String=="fixed-report" && $0["project_id"] as? String=="project"}),
              peer.document === peerDocument,peer.currentPage === peerPage,peer.scaleFactor==peerScale,
              model.leftPageID=="left",model.rightPageID=="right",model.from==0,model.to==1,try model.report.data()==original else{throw NSError(domain:"RetryChangedSource",code:1)}
        window.close()
    }
}
