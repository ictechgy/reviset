import Foundation

@main struct HistoryPageIndexRegression {
    @MainActor static func main() throws {
        configureLegacyNativeLocalization()
        let model=AppModel()
        func page(_ id:String,_ asset:String,_ number:Int,_ text:String,hidden:Bool=false)->[String:Any] {
            ["page_id":id,"asset_id":asset,"page":number,"text":text,"hidden":hidden]
        }
        // The same source bytes occur twice, but their occurrence page IDs differ.
        // Source-array order deliberately differs from the displayed page number.
        let revisions=[
            JSON(["revision_occurrence_id":"occ_a","revision_id":"same_file","assets":[["asset_id":"pptx","format":"pptx"],["asset_id":"reference","format":"pdf"]],"pages":[
                page("a_reference","reference",1,"Excluded reference"),
                page("a_2","pptx",2,"Earliest source label\nSecond line",hidden:true),
                page("a_1","pptx",1,"Later source entry")]]),
            JSON(["revision_occurrence_id":"occ_b","revision_id":"same_file","assets":[["asset_id":"pptx","format":"pptx"]],"pages":[
                page("b_2","pptx",2,"Repeated bytes, new occurrence"),
                page("b_1","pptx",1,"Split branch")]]),
            JSON(["revision_occurrence_id":"occ_c","assets":[["asset_id":"pdf","format":"pdf"]],"pages":[
                page("c_2","pdf",2,"PDF first in source array"),
                page("c_1","pdf",1,"Merged PDF branch")]]),
            JSON(["revision_occurrence_id":"occ_empty","assets":[],"pages":[]])
        ]
        var primaryPageScans=0
        let index=PageIndex(revisions:revisions) { revision in
            primaryPageScans += 1
            return model.primaryPages(revision)
        }
        let lineages=[
            ["c_1","b_1","a_1","b_2","a_2","c_2"], // split/merge, reversed IDs
            ["b_1","a_1","b_1","unknown","a_1"], // duplicate membership IDs
            ["b_2"], // identical file, later occurrence only
            ["a_reference","a_2"], // hidden primary page remains, PDF omitted
            ["a_reference"], // secondary-only lineage is not rendered
            ["c_1","c_2"], // PDF-only version keeps source order
            ["unknown"],
            []
        ]
        for ids in lineages {
            let expected=revisions.map { model.primaryPages($0).filter { ids.contains($0["page_id"].string) } }
            let projected=index.lineage(JSON(["page_ids":ids]))
            let first=expected.flatMap { $0 }.first
            guard (projected == nil)==(first == nil) else { throw failure("Lineage visibility changed: \(ids)") }
            guard let projected,let first else { continue }
            guard try projected.first.data()==first.data() else { throw failure("First-page label source changed: \(ids)") }
            for revisionIndex in revisions.indices {
                let actual=projected.pagesByRevision[revisionIndex] ?? []
                guard try actual.map({ try $0.data() }) == expected[revisionIndex].map({ try $0.data() }) else { throw failure("Ordered members changed at revision \(revisionIndex): \(ids)") }
            }
        }
        guard primaryPageScans==revisions.count else { throw failure("Lineages rescanned primary pages") }
        guard let split=index.lineage(JSON(["page_ids":lineages[0]])),split.first["text"].string.components(separatedBy:"\n").first=="Earliest source label",split.pagesByRevision[0]?.first?["hidden"].bool==true else { throw failure("Source label or hidden-page semantics changed") }
        guard index.lineage(JSON(["page_ids":["b_2"]]))?.pagesByRevision[0]==nil else { throw failure("Repeated file occurrences were collapsed") }
        // Even repeated page IDs retain all source entries, matching the old filter.
        let duplicate=PageIndex(revisions:[JSON(),JSON()]) { _ in [JSON(page("shared","pdf",1,"same ID"))] }
        guard let repeated=duplicate.lineage(JSON(["page_ids":["shared","shared"]])),repeated.pagesByRevision[0]?.count==1,repeated.pagesByRevision[1]?.count==1 else { throw failure("Repeated source IDs lost an occurrence") }
        guard PageIndex(revisions:[],primaryPages:{ _ in [] }).lineage(JSON(["page_ids":["unknown"]]))==nil else { throw failure("Empty report produced a row") }
        print("PASS native history page index parity: source labels/order, split/merge, duplicate membership, occurrence IDs, hidden/secondary/PDF-only pages, missing IDs and one primary scan per revision")
    }
    static func failure(_ message:String)->NSError { NSError(domain:"HistoryPageIndex",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
