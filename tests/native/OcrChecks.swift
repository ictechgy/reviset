import Foundation
import AppKit

@main struct OcrChecks {
    static func main() throws {
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
        let expr=try DocverVision.numericExpression()
        func numbers(_ text:String)->[String]{expr.matches(in:text,range:NSRange(text.startIndex...,in:text)).map{DocverVision.canonicalNumber(String(text[Range($0.range,in:text)!]))}}
        precondition(numbers("1, 2, 3")==["1","2","3"],"List commas cannot fuse separate values")
        precondition(numbers("2026-10-19")==["2026","10","19"],"Date separators cannot become negative signs")
        precondition(numbers("−５００원 ＋１０％")==["-500원","+10%"],"Full width digits and signed units")
        precondition(DocverVision.numericFormatSupported("−５００원 100 100"))
        precondition(!DocverVision.numericFormatSupported("⅛ pound ¼ pound x² Ⅲ"),"Unverified fractions/exponents cannot claim decimal consensus")

        let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:240,pixelsHigh:160,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:0,bitsPerPixel:0)!
        let pixels=image.bitmapData!,stride=image.bytesPerRow
        func clear(){for y in 0..<160{for x in 0..<240{pixels[y*stride+x]=255}}}
        clear();for x in 20...220{pixels[40*stride+x]=0}
        let line=CGRect(x:20.0/240,y:30.0/160,width:200.0/240,height:20.0/160)
        precondition(DocverVision.supportedPixels(image))
        precondition(DocverVision.strikeCandidate(image,line) != nil,"8-bit grayscale strikes must be evaluated")
        clear();for x in 20...220{pixels[52*stride+x]=0}
        precondition(DocverVision.strikeCandidate(image,line)==nil,"Underline is not a strike")

        clear();let xs=[20,85,150,220],ys=[40,70,100,130]
        for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for x in xs{for y in 40...130{pixels[y*stride+x]=0}}
        let words=[(0,0,"Name"),(0,1,"Corp"),(0,2,"Remark"),(1,0,"Foo"),(2,0,"Bar"),(2,1,"Microsoft"),(2,2,"Dummy")]
        let lines:[[String:Any]]=words.map{row,col,text in
            let box:[CGFloat]=[CGFloat(xs[col]+4)/240,CGFloat(ys[row]+7)/160,40.0/240,12.0/160]
            return ["text":text,"confidence":1.0,"numeric_consensus":true,"alternatives":[["text":text,"confidence":1.0]],"tokens":[["text":text,"bbox":box]]]
        }
        let tables=DocverVision.ruledTables(image,lines)
        precondition(tables.count==1)
        let cells=tables[0]["cells"] as! [[String:Any]]
        precondition(cells.count==9 && cells.filter{($0["text"] as! String).isEmpty}.count==2,"Empty cells and coordinates must survive")
        precondition((cells[7]["text"] as? String)=="Microsoft")
        precondition((cells[4]["text_confident"] as? Bool)==false,"Missing OCR is not proof of an empty value")
        for y in 41..<70{pixels[y*stride+85]=255}
        precondition(DocverVision.ruledTables(image,lines).isEmpty,"Partial/merged border must not silently become a coarser grid")
        clear();for y in ys{for x in 20...220{pixels[y*stride+x]=0}}
        for y in 40...130{pixels[y*stride+20]=0;pixels[y*stride+220]=0}
        precondition(DocverVision.ruledTables(image,lines).isEmpty,"Parallel rules/axes without internal columns are not a grid")
        print("PASS numeric position/multiplicity/conflict and lexical controls; grayscale strike/underline; ruled grid empty cells/partial-border/negative controls")
    }
}
