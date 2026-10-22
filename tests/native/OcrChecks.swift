import Foundation
import AppKit
import Vision

@main struct OcrChecks {
    static func main() throws {
        let normalization=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
        for item in normalization {let text=item["text"] as! String;precondition(DocverVision.roiCompact(text).utf16.elementsEqual((item["compact"] as! String).utf16),"Shared OCR exact UTF16 whitespace/NFC/case contract");precondition(DocverVision.latinCounterScript(text)==item["latin"] as! Bool,"Shared Latin counter-script contract");if let other=item["other_text"] as? String{precondition(DocverVision.sameRoiKey(text,other)==item["equal"] as! Bool,"Shared ambiguity-key equality contract")}}
        let whitespacePrimary="계익 Contract",whitespaceAlternative="계익\u{0085}Contract"
        let whitespaceAmbiguous=DocverVision.roiCompact(whitespacePrimary) != DocverVision.roiCompact(whitespaceAlternative)
        precondition(whitespaceAmbiguous && !DocverVision.mixedScriptCounterOnly(whitespacePrimary,0.5,whitespaceAmbiguous),"NEL dissent must retain the eight-context ambiguous correction path")
        for text in ["계약 Contract","한 éÆ"] {precondition(DocverVision.mixedScriptCounterOnly(text,0.5,false,[]))}
        for text in ["Contract","éÆ","계약 검토","Δ"] {precondition(!DocverVision.mixedScriptCounterOnly(text,0.5,false,[]))}
        for score in [0.0,0.3,0.499,0.501,1.0] {precondition(!DocverVision.mixedScriptCounterOnly("계약 Contract",score,false),"Weak and high-score profiles retain their existing evidence contract")}
        precondition(!DocverVision.mixedScriptCounterOnly("계약 Contract",0.5,true),"Ambiguous positive-correction eligibility still requires all eight contexts")
        precondition(!DocverVision.mixedScriptCounterOnly("계약 é",0.5,false,[["text":"계약 e\u{0301}","confidence":0.5]]),"NFC-equivalent but raw-distinct alternatives retain8 across Unicode table versions")
        precondition(DocverVision.mixedScriptCounterOnly("계약 é",0.5,false,[["text":"계약 é","confidence":0.5]]))
        precondition(!DocverVision.mixedScriptCounterOnly("계약 Contract",0.5,false),"Unknown alternatives container retains8 contexts")
        for alternative in ["계약  Contract","계약 contract","계약\u{0085}Contract"] {precondition(!DocverVision.mixedScriptCounterOnly("계약 Contract",0.5,false,[["text":alternative,"confidence":0.5]]),"Unproven cross-runtime equality retains all correction contexts")}
        precondition(!DocverVision.mixedScriptCounterOnly("계약 Contract",0.5,false,[["text":"계약 Contract"]]))
        typealias Reading=DocverVision.NumericReading
        let a=Reading(text:"100",rect:CGRect(x:0.1,y:0.1,width:0.2,height:0.05),sources:["whole:0"])
        let b=Reading(text:"100",rect:CGRect(x:0.5,y:0.1,width:0.2,height:0.05),sources:["whole:1"])
        var duplicate=a;duplicate.sources=["tile:1360,0"]
        precondition(!DocverVision.numericAgreement([a,b],[a]),"One reading cannot verify two repeated values")
        precondition(DocverVision.numericAgreement([a,b],[a,b,duplicate]),"Overlapping tile duplicates must collapse")
        var conflict=a;conflict.text="1000"
        precondition(!DocverVision.numericAgreement([a,b],[a,b,conflict]),"Conflicting readings must withhold agreement")
        var wrong=b;wrong.rect.origin.x=0.8
        precondition(!DocverVision.numericAgreement([a,b],[a,wrong]),"Text equality cannot substitute for position")
        let merged=Reading(text:"100",rect:CGRect(x:0.1,y:0.1,width:0.6,height:0.05),sources:["crop"])
        precondition(!DocverVision.numericAgreement([a,b],[merged]),"Merged crop cannot verify individual slots")
        precondition(DocverVision.numericStatus([],[a])=="conflicted","Foo versus tile F00 must remain a contradiction")
        precondition(DocverVision.numericStatus([a],[])=="unverified","Missing evidence is not a contradictory reading")
        precondition(DocverVision.numericStatus([a],[a,b])=="conflicted","An extra unmatched numeric reading is a contradiction")
        precondition(DocverVision.numericStatus([a],[conflict])=="conflicted")
        let tall:[[String:Any]]=[
            ["text":"tall","bbox":[CGFloat(0.1),CGFloat(0.1),CGFloat(0.1),CGFloat(0.1)]],
            ["text":"L1","bbox":[CGFloat(0.31),CGFloat(0.1),CGFloat(0.2),CGFloat(0.02)]],
            ["text":"L2","bbox":[CGFloat(0.30),CGFloat(0.13),CGFloat(0.2),CGFloat(0.02)]]]
        precondition(DocverVision.orderedLines(tall).map{$0["text"] as! String} == ["tall","L1","L2"],"Tall anchors must not absorb stacked neighboring lines")
        let kpi:[[String:Any]]=[
            ["text":"Revenue","bbox":[CGFloat(0.1),CGFloat(0.10),CGFloat(0.2),CGFloat(0.02)]],
            ["text":"₩12,000","bbox":[CGFloat(0.4),CGFloat(0.09),CGFloat(0.15),CGFloat(0.05)]]]
        precondition(DocverVision.orderedLines(kpi).map{$0["text"] as! String} == ["Revenue","₩12,000"],"A larger KPI value shares the label's row when their vertical centers lie inside each other")
        let jitter:[[String:Any]]=[
            ["text":"right","bbox":[CGFloat(0.7),CGFloat(0.100),CGFloat(0.2),CGFloat(0.02)]],
            ["text":"left","bbox":[CGFloat(0.1),CGFloat(0.101),CGFloat(0.2),CGFloat(0.02)]],
            ["text":"below","bbox":[CGFloat(0.1),CGFloat(0.14),CGFloat(0.2),CGFloat(0.02)]]
        ]
        precondition(DocverVision.orderedLines(jitter).map{$0["text"] as! String}==["left","right","below"],"Same-row jitter must not reverse column order")
        precondition(DocverVision.orderedLines(Array(jitter.reversed())).map{$0["text"] as! String}==["left","right","below"])
        let expr=try DocverVision.numericExpression()
        func numbers(_ text:String)->[String]{expr.matches(in:text,range:NSRange(text.startIndex...,in:text)).map{DocverVision.canonicalNumber(String(text[Range($0.range,in:text)!]))}}
        precondition(numbers("1\u{0085}/\u{0085}2 －５００")==["1/2","-500"],"Unicode whitespace/sign canonicalization matches TypeScript")
        precondition(numbers(".5 -.5 −．５")==[".5","-.5","-.5"],"A leading decimal point remains inside its verified token")
        precondition(DocverVision.numericStatus([Reading(text:".5",rect:a.rect,sources:["whole"])],[Reading(text:"5",rect:a.rect,sources:["tile"])])=="conflicted","An independently dropped decimal point is a contradiction")
        precondition(numbers("1, 2, 3")==["1","2","3"],"List commas cannot fuse separate values")
        precondition(numbers("2026-10-19")==["2026","10","19"],"Date separators cannot become negative signs")
        precondition(numbers("−５００원 ＋１０％")==["-500원","+10%"],"Full width digits and signed units")
        precondition(DocverVision.numericFormatSupported("−５００원 100 100"))
        precondition(numbers("⅛ pound ¼ butter ½ olives １／２")==["1/8","1/4","1/2","1/2"],"Each complete fraction is one canonical spatial slot")
        precondition(numbers("1½ 1 1/2 -¼")==["1","1/2","1","1/2","-1/4"],"Mixed integer/fraction slots must not fuse into11/2")
        precondition(DocverVision.numericFormatSupported("⅛ pound ¼ pound 1/2"))
        precondition(!DocverVision.numericFormatSupported("⅟ x² Ⅲ ١"),"Incomplete numerators and unsupported numeric scripts remain unverified")
        let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
        for item in cases {
            let text=item["text"] as! String,supported=item["supported"] as! Bool
            precondition(DocverVision.numericFormatSupported(text)==supported,"Shared notation contract: \(text)")
            if !supported {precondition(DocverVision.numericStatus([a],[a],formatSupported:DocverVision.numericFormatSupported(text))=="unsupported_notation")}
        }
        let half=Reading(text:"1/2",rect:a.rect,sources:["whole"]),halfTile=Reading(text:DocverVision.canonicalNumber("½"),rect:a.rect,sources:["tile"]),third=Reading(text:"1/3",rect:a.rect,sources:["tile"])
        precondition(DocverVision.numericAgreement([half],[halfTile]))
        precondition(DocverVision.numericStatus([half],[third])=="conflicted","Fraction denominator changes must not pass agreement")
        precondition(!DocverVision.numericAgreement([half],[Reading(text:"1",rect:a.rect,sources:["tile"]),Reading(text:"2",rect:b.rect,sources:["tile"])]),"Separate decimal digits do not verify a fraction")
        precondition(!DocverVision.numericFormatSupported("⅛ pound ¼ pound x² Ⅲ"),"Unverified fractions/exponents cannot claim decimal consensus")

        let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:240,pixelsHigh:160,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:0,bitsPerPixel:0)!
        let pixels=image.bitmapData!,stride=image.bytesPerRow
        func clear(){for y in 0..<160{for x in 0..<240{pixels[y*stride+x]=255}}}
        clear();for x in 20...220{pixels[40*stride+x]=0}
        // A stroke alone is a rule, not evidence of struck text. Add separated
        // glyph ink above and below the candidate to exercise the strike path.
        for left in Swift.stride(from:30,through:190,by:40){for y in 32...48{for x in left...(left+12){pixels[y*stride+x]=0}}}
        let line=CGRect(x:20.0/240,y:30.0/160,width:200.0/240,height:20.0/160)
        precondition(DocverVision.supportedPixels(image))
        precondition(DocverVision.strikeCandidate(image,line) != nil,"8-bit grayscale strikes must be evaluated")
        clear();for x in 20...220{pixels[52*stride+x]=0}
        precondition(DocverVision.strikeCandidate(image,line)==nil,"Underline is not a strike")
        precondition(DocverVision.strikeObservation(image,CGRect(x:20.1/240,y:30.0/160,width:20.5/240,height:20.0/160)).status=="too_small","Status must use the exact clamped integer detector bounds")

        clear();let xs=[20,85,150,220],ys=[40,70,100,130]
        for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
        let words=[(0,0,"Name"),(0,1,"Corp"),(0,2,"Remark"),(1,0,"Foo"),(2,0,"Bar"),(2,1,"Microsoft"),(2,2,"Dummy")]
        let lines:[[String:Any]]=words.map{row,col,text in
            let box:[CGFloat]=[CGFloat(xs[col]+4)/240,CGFloat(ys[row]+7)/160,40.0/240,12.0/160]
            return ["text":text,"confidence":1.0,"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":[["text":text,"confidence":1.0]],"tokens":[["text":text,"bbox":box]]]
        }
        let tables=DocverVision.ruledTables(image,lines)
        precondition(tables.count==1)
        let cells=tables[0]["cells"] as! [[String:Any]]
        precondition(cells.count==9 && cells.filter{($0["text"] as! String).isEmpty}.count==2,"Empty cells and coordinates must survive")
        precondition((cells[7]["text"] as? String)=="Microsoft")
        precondition((cells[4]["text_confident"] as? Bool)==false,"Missing OCR is not proof of an empty value")
        var struckLines=lines;struckLines[0]["strike_candidate"]=true;struckLines[0]["strike_status"]="detected"
        let struckCells=DocverVision.ruledTables(image,struckLines)[0]["cells"] as! [[String:Any]]
        precondition((struckCells[0]["text_confident"] as? Bool)==false,"Struck text cannot become a confident grid value")
        for background:UInt8 in [240,230] {
            for y in 0..<160{for x in 0..<240{pixels[y*stride+x]=background}}
            for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
            for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
            let observed=DocverVision.gridObservation(image,lines)
            precondition(observed.status=="available" && observed.tables.count==1 && (observed.tables[0]["cells"] as! [[String:Any]]).count==9,"Flat off-white backgrounds are not dividers")
        }
        clear()
        for row in 0..<3{for col in 0..<3{for y in (ys[row]+1)..<ys[row+1]{for x in (xs[col]+1)..<xs[col+1]{pixels[y*stride+x]=(row+col)%2==0 ? 230:245}}}}
        for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
        precondition(DocverVision.gridObservation(image,lines).status=="available","Broad alternating cell fills are not narrow dividers")
        clear();for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:image)
        for (row,col,text) in words{(text as NSString).draw(at:NSPoint(x:xs[col]+4,y:160-ys[row]-20),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.black])}
        NSGraphicsContext.restoreGraphicsState()
        precondition(DocverVision.gridObservation(image,lines).status=="available","Actual cell glyph ink cannot be an interior divider")
        clear();for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
        for y in 41..<70{pixels[y*stride+85]=255}
        precondition(DocverVision.ruledTables(image,lines).isEmpty,"Partial/merged border must not silently become a coarser grid")
        clear();for y in [40,70,130]{for x in 20...220{pixels[y*stride+x]=0}}
        for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
        for x in 85...220{pixels[100*stride+x]=0}
        precondition(DocverVision.ruledTables(image,lines).isEmpty,"Partial horizontal divider must not collapse two distinct right-column rows")
        for gray in [180,230] {
            for x in 85...220{pixels[100*stride+x]=UInt8(gray)}
            let observed=DocverVision.gridObservation(image,lines)
            precondition(observed.tables.isEmpty && observed.status=="ambiguous_boundaries" && observed.reasons.contains("faint_or_dashed_interior_boundary"),"Faint partial dividers must not establish a coarser grid")
        }
        for x in 85...220{pixels[100*stride+x]=(x-85)%10<5 ? 0:255}
        precondition(DocverVision.gridObservation(image,lines).status=="ambiguous_boundaries","Dashed partial dividers must not merge distinct rows")
        for gray in [180,230] {
            clear();for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
            for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
            for y in 40...130{pixels[y*stride+85]=UInt8(gray)}
            precondition(DocverVision.gridObservation(image,lines).status=="ambiguous_boundaries","Faint vertical dividers must not merge columns")
        }
        for y in 40...130{pixels[y*stride+85]=(y-40)%10<5 ? 0:255}
        precondition(DocverVision.gridObservation(image,lines).status=="ambiguous_boundaries","Dashed vertical dividers must not merge columns")
        clear();for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for y in 40...130{pixels[y*stride+20]=0;pixels[y*stride+220]=0}
        precondition(DocverVision.ruledTables(image,lines).isEmpty,"Parallel rules/axes without internal columns are not a grid")
        clear();precondition(DocverVision.gridObservation(image,lines).status=="not_detected")
        let unsupported=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:240,pixelsHigh:160,bitsPerSample:16,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:480,bitsPerPixel:16)!
        precondition(DocverVision.gridObservation(unsupported,lines).status=="unsupported_format")
        let small=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:80,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:80,bitsPerPixel:8)!
        precondition(DocverVision.gridObservation(small,lines).status=="unsupported_dimensions")
        let busy=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:240,pixelsHigh:4096,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:240,bitsPerPixel:8)!
        busy.bitmapData!.initialize(repeating:255,count:240*4096)
        for y in Swift.stride(from:0,to:4096,by:2){for x in 0..<240{busy.bitmapData![y*240+x]=0}}
        precondition(DocverVision.gridObservation(busy,lines).status=="budget_exceeded")
        func budgetGrid(_ columns:Int,_ rows:Int,_ reason:String){
            let width=max(160,columns*15+41),height=max(160,rows*15+41)
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:width,bitsPerPixel:8)!
            let p=bitmap.bitmapData!;p.initialize(repeating:255,count:width*height)
            for row in 0...rows{for x in 20...(20+columns*15){p[(20+row*15)*width+x]=0}}
            for col in 0...columns{for y in 20...(20+rows*15){p[y*width+20+col*15]=0}}
            let result=DocverVision.gridObservation(bitmap,lines)
            precondition(result.status=="budget_exceeded" && result.reasons.contains(reason),"Grid budgets must be explicit: \(reason), got \(result.status) \(result.reasons)")
        }
        budgetGrid(40,3,"column_rule_limit_33")
        budgetGrid(10,65,"row_rule_limit_64")
        budgetGrid(32,33,"cell_limit_1000")
        let high=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:900,pixelsHigh:4096,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:900,bitsPerPixel:8)!,hp=high.bitmapData!
        let highLines:[[String:Any]]=words.map{row,col,text in ["text":text,"tokens":[["text":text,"bbox":[CGFloat(24+col*280)/900,CGFloat(480+row*400)/4096,100.0/900,60.0/4096]]]]}
        for vertical in [false,true]{for gray:UInt8 in [180,230]{
            hp.initialize(repeating:255,count:900*4096)
            for y in (vertical ? [400,800,1200,1600]:[400,800,1600]){for x in 20...880{hp[y*900+x]=0}}
            for x in (vertical ? [20,580,880]:[20,300,580,880]){for y in 400...1600{hp[y*900+x]=0}}
            //14 rows is the inclusive maximum accepted rule thickness at4096px.
            if vertical{for x in 294...307{for y in 400...800{hp[y*900+x]=gray}}}
            else{for y in 1194...1207{for x in 300...880{hp[y*900+x]=gray}}}
            // Keep the accepted solid rulings continuous at intersections.
            for y in (vertical ? [400,800,1200,1600]:[400,800,1600]){for x in 20...880{hp[y*900+x]=0}}
            for x in (vertical ? [20,580,880]:[20,300,580,880]){for y in 400...1600{hp[y*900+x]=0}}
            let observed=DocverVision.gridObservation(high,highLines)
            precondition(observed.status=="ambiguous_boundaries","Maximum-thickness faint partial dividers must withhold a coarse grid: vertical=\(vertical),gray=\(gray),status=\(observed.status)")
        }}
        // Reconsideration must fail closed on unsupported/empty/dark pixels;
        // skipped numeric/strike lines retain every original primary field.
        let roiBand=CGRect(x:0.1,y:0.1,width:0.5,height:0.3)
        let white=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:240,pixelsHigh:160,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:240,bitsPerPixel:8)!
        white.bitmapData!.initialize(repeating:255,count:240*160)
        precondition(DocverVision.reconsider(white.cgImage!,unsupported,roiBand,"weak")["status"] as? String == "unsupported_bitmap")
        precondition(DocverVision.reconsider(white.cgImage!,white,roiBand,"weak")["status"] as? String == "empty_ink")
        white.bitmapData!.initialize(repeating:0,count:240*160)
        precondition(DocverVision.reconsider(white.cgImage!,white,roiBand,"weak")["status"] as? String == "unsupported_background")
        let ineligible:[[String:Any]]=["F00","A 123","Name"].enumerated().map{i,text in ["text":text,"confidence":0.3,"bbox":[CGFloat(0.1),0.1,0.5,0.3],"numeric_consensus":true,"strike_candidate":i==2,"strike_status":i==2 ? "detected":"not_detected","alternatives":[["text":text,"confidence":0.3]]]}
        let untouched=DocverVision.reconsideredLines(white.cgImage!,white,ineligible)
        precondition(NSDictionary(dictionary:untouched[0]).isEqual(to:ineligible[0]) && NSDictionary(dictionary:untouched[1]).isEqual(to:ineligible[1]) && NSDictionary(dictionary:untouched[2]).isEqual(to:ineligible[2]))
        white.bitmapData!.initialize(repeating:255,count:240*160)
        let prioritized:[[String:Any]]=[0.5,0.3,0.3,0.3,0.3].enumerated().map{i,score in ["text":i==0 ? "borderline":"weak","confidence":score,"bbox":[CGFloat(0.1),0.1,0.5,0.3],"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":[]]}
        let priorityResults=DocverVision.reconsideredLines(white.cgImage!,white,prioritized)
        precondition((priorityResults[0]["reconsideration"] as? [String:Any])?["status"] as? String == "budget_exceeded","Borderline lines cannot consume existing weak-line budget")
        for index in 1..<5 {precondition((priorityResults[index]["reconsideration"] as? [String:Any])?["status"] as? String == "empty_ink");precondition(priorityResults[index]["text"] as? String == "weak" && priorityResults[index]["confidence"] as? Double == 0.3)}
        precondition(DocverVision.uniformWhitePixels(white,CGRect(x:49,y:49,width:3,height:3)))
        white.bitmapData![50*240+50]=254
        precondition(!DocverVision.uniformWhitePixels(white,CGRect(x:49,y:49,width:3,height:3)),"One faint nonwhite pixel must veto empty-character proof")
        precondition(!DocverVision.uniformWhitePixels(unsupported,CGRect(x:49,y:49,width:3,height:3)))
        let expired=DocverVision.reconsider(white.cgImage!,white,CGRect(x:0.1,y:0.1,width:0.5,height:0.3),"weak",nil,DispatchTime.now())
        precondition(expired["status"] as? String == "budget_exceeded")
        let pageBounds=CGRect(x:0,y:0,width:100,height:100)
        let inside=DocverVision.clippedRoiRect(CGRect(x:0.1,y:0.3,width:25.123456789,height:18.123456789),pageBounds)!
        precondition(!inside.edge,"Floating intersection reconstruction cannot mark an interior box as clipped")
        let outside=DocverVision.clippedRoiRect(CGRect(x:-0.5,y:2,width:20,height:10),pageBounds)!
        precondition(outside.edge && outside.rect.minX==0)
        precondition(DocverVision.clippedRoiRect(CGRect(x:101,y:0,width:1,height:1),pageBounds)==nil)
        precondition(DocverVision.clippedRoiRect(CGRect(x:CGFloat.nan,y:0,width:1,height:1),pageBounds)==nil)
        let combining=String(repeating:"e\u{301}",count:70)
        precondition(combining.count==70 && combining.utf16.count==140)
        let overBudget:[[String:Any]]=[["text":combining,"confidence":0.3,"bbox":[CGFloat(0.1),0.1,0.5,0.3],"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":[]]]
        precondition(DocverVision.reconsideredLines(white.cgImage!,white,overBudget)[0]["reconsideration"]==nil)
        precondition(DocverVision.reconsider(high.cgImage!,high,CGRect(x:0,y:0,width:1,height:0.1),"weak")["status"] as? String == "budget_exceeded")
        for text in ["Pineapple한","Pineapple 주스","Pineapple한글"] {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1000,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:4000,bitsPerPixel:32)!
            bitmap.bitmapData!.initialize(repeating:255,count:4000*300)
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            (text as NSString).draw(at:NSPoint(x:80,y:120),withAttributes:[.font:NSFont.systemFont(ofSize:32),.foregroundColor:NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            let image=bitmap.cgImage!,request=try DocverVision.request()
            try VNImageRequestHandler(cgImage:image,orientation:.up,options:[:]).perform([request])
            guard let original=request.results?.first(where:{$0.topCandidates(1).first?.string==text}),let candidate=original.topCandidates(1).first else{preconditionFailure("Genuine Hangul native control not read exactly: \(text), got \(request.results?.compactMap{$0.topCandidates(1).first?.string} ?? [])")}
            let b=original.boundingBox,observed=DocverVision.reconsider(image,bitmap,CGRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height),text,candidate)
            let empty=observed["primary_empty_characters"] as? [[String:Any]] ?? []
            precondition(!empty.contains{entry in (entry["text"] as? String)?.range(of:"\\p{script=Hangul}",options:.regularExpression) != nil},"Actual Hangul ink cannot become an empty-character deletion certificate")
            precondition((observed["contexts"] as? [[String:Any]])?.count==8,"All native contexts were exercised")
            if text=="Pineapple 주스" {
                // Synthetic producer eligibility controls,not measured OCR
                // confidence or accuracy claims. The raster/box are real.
                let variants:[(String,Double,Int)]=[(text,0.5,4),("Pineapple\u{0085}주스",0.5,8),("Pineapple\u{0085}주스",0.35,8),("Pineapple\u{0085}주스",0.349,4),("pineapple  주스",0.5,8)]
                for (alternative,score,count) in variants {
                    let row:[String:Any]=["text":text,"confidence":0.5,"bbox":[CGFloat(b.minX),1-b.maxY,b.width,b.height],"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":[["text":text,"confidence":0.5],["text":alternative,"confidence":score]]]
                    let result=DocverVision.reconsideredLines(image,bitmap,[row])[0]
                    precondition((result["reconsideration"] as? [String:Any])?["contexts"] is [[String:Any]])
                    precondition(((result["reconsideration"] as! [String:Any])["contexts"] as! [[String:Any]]).count==count,"Actual producer preserves ambiguity and the competitive-score cutoff")
                    precondition(result["text"] as? String==text && result["confidence"] as? Double==0.5)
                }
                for (alternative,count) in [("Delivery pending",2),("DELIVERY pending",8),("Delivery e\u{0301}",8)] {
                    let row:[String:Any]=["text":"Delivery pending","confidence":0.8,"bbox":[CGFloat(b.minX),1-b.maxY,b.width,b.height],"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":[["text":alternative,"confidence":0.8]]]
                    let result=DocverVision.reconsideredLines(image,bitmap,[row])[0]
                    precondition(((result["reconsideration"] as! [String:Any])["contexts"] as! [[String:Any]]).count==count,"High-score pruning requires literal raw competitive agreement; uncertain readings retain8 instead of losing eligibility")
                }
                for container:Any in [NSNull(),[NSNull(),["text":"Pineapple\u{0085}주스","confidence":0.5]] as [Any]] {
                    let row:[String:Any]=["text":text,"confidence":0.5,"bbox":[CGFloat(b.minX),1-b.maxY,b.width,b.height],"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":container]
                    let result=DocverVision.reconsideredLines(image,bitmap,[row])[0]
                    precondition(((result["reconsideration"] as! [String:Any])["contexts"] as! [[String:Any]]).count==8,"Malformed alternatives containers cannot prune correction contexts")
                }
                for (primary,alternative) in [("계익 é","계익 e\u{0301}"),("계익 J\u{030C}","계익 ǰ"),("계익 H\u{0331}","계익 ẖ"),("계익 T\u{0308}","계익 ẗ"),("계익 W\u{030A}","계익 ẘ"),("계익 Y\u{030A}","계익 ẙ")] {
                    let row:[String:Any]=["text":primary,"confidence":0.5,"bbox":[CGFloat(b.minX),1-b.maxY,b.width,b.height],"numeric_consensus":true,"strike_candidate":false,"strike_status":"not_detected","alternatives":[["text":primary,"confidence":0.5],["text":alternative,"confidence":0.5]]]
                    let result=DocverVision.reconsideredLines(image,bitmap,[row])[0]
                    precondition(((result["reconsideration"] as! [String:Any])["contexts"] as! [[String:Any]]).count==8,"Canonical-equivalent but code-unit-different keys preserve correction eligibility")
                }
            }
        }
        print("PASS genuine trailing Hangul and Korean word raster ink never certifies empty-character deletion")
        print("PASS numeric position/multiplicity/conflict and lexical controls; grayscale strike/underline; ruled grid empty cells/partial-border/negative controls")
    }
}
