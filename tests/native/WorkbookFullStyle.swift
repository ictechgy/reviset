import Foundation
import AppKit
import SwiftUI

@MainActor enum Smoke {
    static func captureView(_ window:NSWindow,_ url:URL)throws {throw NSError(domain:"UnexpectedCapture",code:1)}
}
@main struct WorkbookFullStyleProbe {
    @MainActor static func main() async throws {
        configureLegacyNativeLocalization()
        _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"]!)
        let bridge=Bridge(resources:Bundle.main.resourceURL!,library:root)
        let actual=ProcessInfo.processInfo.environment["DOCVER_TEST_STYLE_REAL"]=="1"
        let manifest=actual ? JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("style-source.json")))):JSON()
        let fontKey=actual ? manifest["font_key"].string:"font.name"
        func require(_ value:Bool,_ message:String)throws {if !value {throw NSError(domain:message,code:1)}}
        func control(_ mode:String="ok",delay:Int=0)throws {try JSON(["mode":mode,"delay":delay]).data().write(to:root.appendingPathComponent("control.json"),options:.atomic)}
        func source(_ occurrence:String,_ address:String="A1")->WorkbookStyleSource {WorkbookStyleSource(project:actual ? manifest["project"].string:"project",report:actual ? manifest["report"].string:"report",occurrence:actual ? manifest[occurrence]["occurrence"].string:occurrence,sheet:actual ? manifest[occurrence]["sheet"].string:"sheet-"+occurrence,cell:JSON(["address":address,"row":1,"column":address=="A1" ? 1:2]))!}
        try require(WorkbookStyleSource(project:"project",report:"report",occurrence:"old",sheet:"sheet-old",cell:JSON())==nil,"MissingCellMintedStyleSource")
        let before=WorkbookFullStyleModel(bridge:bridge,source:source("old")),after=WorkbookFullStyleModel(bridge:bridge,source:source("new"))
        try control();await before.load();await after.load()
        var keys:[String]=[]
        for index in 0..<9 {
            try require(before.failure.isEmpty && after.failure.isEmpty,"StylePageFailed")
            keys.append(before.item["key"].string)
            try require(before.read.page==index+1 && before.total==(actual ? manifest["total"].int:10),"PropertyPagingLostCount")
            if index<8 {await before.nextProperty();await after.nextProperty()}
        }
        try require(keys.count==Set(keys).count && keys.last==fontKey && before.item["value"].string=="Calibri" && after.item["value"].string=="Arial","NinthPropertyFontChangeNotReadable")
        // Render the production reader component at the changed font, without
        // opening the user's app or invoking screen-recording / accessibility.
        if let output=ProcessInfo.processInfo.environment["DOCVER_TEST_STYLE_EVIDENCE_OUT"] {
            let destination=URL(fileURLWithPath:output);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            for (name,reader) in [("before",before),("after",after)] {
                let host=NSHostingView(rootView:WorkbookFullStyleView(reader:reader).frame(width:580,height:280).background(Color.white))
                host.frame=NSRect(x:0,y:0,width:580,height:280)
                let window=NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false);window.contentView=host
                try await Task.sleep(nanoseconds:100_000_000)
                for _ in 0..<300 {if !reader.loading {break};try await Task.sleep(nanoseconds:10_000_000)}
                host.layoutSubtreeIfNeeded();host.displayIfNeeded()
                let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(name+"-font-property-9.png"))
                try require(reader.read.page==9 && reader.item["key"].string==fontKey,"ProductionViewResetPropertyOwner")
                window.contentView=nil
            }
            // Removing the production view cancels its own reader; resume the
            // same fixed property before testing the next property.
            await before.retry();await after.retry()
        }
        if actual {
            for (name,reader) in [("old",before),("new",after)] {
                await reader.load();var properties:[String:String]=[:]
                while true {
                    try require(reader.failure.isEmpty && !reader.item.isNull,"ActualStylePageFailed")
                    properties[reader.item["key"].string]=reader.item["value"].string
                    if reader.nextCursor.isEmpty {break}
                    await reader.nextProperty()
                }
                try require((try JSON(properties).data())==(try manifest[name]["style"].data()),"ActualSourceStylePropertiesLost")
            }
            print("PASS actual XLSX full style: real independent XLSX producer, committed fixed report, real bridge style cursors, native font property 9 render and complete property reconstruction")
            return
        }
        await before.nextProperty()
        let expected=String(repeating:"😀한글🧑‍💻",count:1600)
        var observed="",chunks=0
        while true {
            try require(before.failure.isEmpty && before.item["key"].string=="long.value" && before.read.page==10,"TextPageChangedProperty")
            observed += before.item["value"].string;chunks += 1
            guard let next=before.nextOffset else {break}
            try require(next>before.read.offset,"NonAdvancingTextCursor")
            await before.textPage(next)
            try require(chunks<20,"UnboundedTextFixture")
        }
        try require(observed==expected && chunks>1 && before.nextCursor.isEmpty,"LongUnicodeStyleLostTextOrPropertyBoundary")
        await before.textPage(0);try require(before.read.offset==0 && before.nextOffset != nil,"StyleTextRestartFailed")
        try control("fail");let failedOffset=before.nextOffset!;await before.textPage(failedOffset)
        try require(!before.failure.isEmpty && before.item.isNull && !before.loading,"FailedContinuationKeptStaleStyle")
        try control();await before.retry()
        try require(before.failure.isEmpty && before.read.offset==failedOffset && before.item["key"].string=="long.value","StyleRetryChangedKeyOrTextOffset")
        try control("wrong-key");await before.textPage(0)
        try require(!before.failure.isEmpty && before.item.isNull,"ContinuationAcceptedForeignProperty")
        try control();await before.retry();await before.previousProperty()
        try require(before.read.page==9 && before.item["value"].string=="Calibri" && before.read.offset==0,"PreviousPropertyKeptTextOffset")
        for mode in ["wrong-project","wrong-report","wrong-revision","wrong-sheet","wrong-component","bad-offset","bad-next","nonarray","fractional-total","same-cursor","complete-short","complete-next","empty-nonempty","truncated-missing-next","truncated-full-initial","missing-next"] {
            try control(mode);await before.retry()
            try require(!before.failure.isEmpty && before.item.isNull && !before.loading,"UntrustedStyleDisplayed-"+mode)
        }
        try control("empty-value");await before.retry()
        try require(before.failure.isEmpty && !before.item.isNull && before.item["value"].string.isEmpty && before.nextOffset==nil,"ValidEmptyPropertyRejected")
        for mode in ["missing","empty"] {
            try control(mode);await before.load()
            try require(before.failure.isEmpty && before.item.isNull && before.missing==(mode=="missing"),"MissingAndEmptyStyleConfused-"+mode)
        }
        try control("late",delay:500)
        let late=Task {await before.load()}
        var started=false
        for _ in 0..<200 {
            if ((try? String(contentsOf:root.appendingPathComponent("style-events.jsonl"),encoding:.utf8)) ?? "").contains("\"mode\":\"late\"") {started=true;break}
            try await Task.sleep(nanoseconds:5_000_000)
        }
        try require(started,"DelayedStyleDidNotStart")
        before.cancel()
        let replacement=WorkbookFullStyleModel(bridge:bridge,source:source("new","B1"))
        try control();await replacement.load();await late.value
        try require(before.item.isNull && before.failure.isEmpty && !before.loading && replacement.failure.isEmpty && replacement.source.address=="B1","SupersededStyleInstalledOldSelection")
        let events=try String(contentsOf:root.appendingPathComponent("style-events.jsonl"),encoding:.utf8).split(separator:"\n").map{JSON(try JSONSerialization.jsonObject(with:Data($0.utf8)))}
        for event in events {
            let q=event["q"],occurrence=q["revision_occurrence_id"].string
            try require(q["project_id"].string=="project" && q["report_id"].string=="report" && q["sheet_id"].string=="sheet-"+occurrence && q["row"].int==1 && [1,2].contains(q["column"].int) && q["limit"].int==1 && q["text_length"].int==4096 && q["max_output_tokens"].int==8000,"StyleReadLostBoundedPhysicalScope")
        }
        print("PASS native full style: property 9 Calibri/Arial, all keys, Unicode continuation, fixed retry, scoped envelopes, missing vs empty, cancelled selection")
    }
}
