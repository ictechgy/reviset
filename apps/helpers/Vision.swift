import Foundation
import AppKit
import PDFKit
import Vision
import CryptoKit
import CoreText

// A local, versioned process boundary. No network, model download, or language correction.
#if !DOCVER_TEST
@main
#endif
struct DocverVision {
    static let version = "docver-vision-5-ruled-grid"
    static var raster: CGImage?
    static var cachedPath=""
    static var cachedDocument:PDFDocument?
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format:"%02x", $0) }.joined() }
    static func numericExpression() throws->NSRegularExpression {
        try NSRegularExpression(pattern:"(?:(?<![\\p{L}\\p{N}])[+＋−-]\\s*)?[0-9０-９]+(?:[.,，．][0-9０-９]+)*(?:\\s*(?:[%％]|억|만|원))?")
    }
    static func canonicalNumber(_ text:String)->String{text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of:"−",with:"-").filter{!$0.isWhitespace}}
    static func numericFormatSupported(_ text:String)->Bool {
        // Fractions, superscripts and Roman numerals are preserved as text, but
        // agreement on decimal slots does not verify those other number forms.
        text.range(of:"(?=\\p{N})[^0-9０-９]",options:.regularExpression)==nil
    }
    static func supportedPixels(_ image:NSBitmapImageRep)->Bool {
        !image.isPlanar && image.bitsPerSample==8 && ((image.colorSpace.colorSpaceModel == .rgb && [3,4].contains(image.samplesPerPixel)) || (image.colorSpace.colorSpaceModel == .gray && [1,2].contains(image.samplesPerPixel)))
    }
    struct NumericReading {var text:String;var rect:CGRect;var sources:[String]}
    static func sameNumericRegion(_ a:CGRect,_ b:CGRect)->Bool {
        let i=a.intersection(b)
        return !i.isNull && i.width*i.height>0.55*max(a.width*a.height,b.width*b.height)
    }
    static func uniqueNumbers(_ readings:[NumericReading])->[NumericReading] {
        var result:[NumericReading]=[]
        for reading in readings {
            if let i=result.firstIndex(where:{$0.text==reading.text && sameNumericRegion($0.rect,reading.rect)}){
                result[i].sources=Array(Set(result[i].sources+reading.sources)).sorted()
            }else{result.append(reading)}
        }
        return result
    }
    static func numericAgreement(_ required:[NumericReading],_ readings:[NumericReading])->Bool {
        let observed=uniqueNumbers(readings)
        guard required.count==observed.count else{return false}
        // Both directions must be unique. A single repeated value or a merged
        // crop cannot verify two distinct numeric positions.
        return required.allSatisfy{r in let matches=observed.filter{sameNumericRegion(r.rect,$0.rect)};return matches.count==1 && matches[0].text==r.text}
            && observed.allSatisfy{o in required.filter{sameNumericRegion(o.rect,$0.rect)}.count==1}
    }
    static func request() throws -> VNRecognizeTextRequest {
        let r = VNRecognizeTextRequest(); r.revision = VNRecognizeTextRequestRevision3
        r.recognitionLevel = .accurate; r.usesLanguageCorrection = false
        let supported = try r.supportedRecognitionLanguages()
        guard supported.contains("ko-KR"),supported.contains("en-US") else { throw NSError(domain:"DocverVision",code:5,userInfo:[NSLocalizedDescriptionKey:"Korean/English OCR models unavailable"]) }
        r.recognitionLanguages = ["ko-KR", "en-US"]
        r.automaticallyDetectsLanguage = false; r.minimumTextHeight = 0
        return r
    }
    static func info() throws -> [String:Any] {
        let r = try request()
        let families = (CTFontManagerCopyAvailableFontFamilyNames() as! [String]).sorted()
        let descriptors = CTFontManagerCopyAvailableFontURLs() as! [URL]
        let inventory = descriptors.map { url -> String in
            let a = try? FileManager.default.attributesOfItem(atPath:url.path)
            return url.lastPathComponent + ":" + String(describing:a?[.size]) + ":" + String(describing:a?[.modificationDate])
        }.sorted().joined(separator:"\n")
        return ["version":version, "os":ProcessInfo.processInfo.operatingSystemVersionString,
                "revision":r.revision, "languages":r.recognitionLanguages, "supported_languages":try r.supportedRecognitionLanguages(),
                "language_correction":false,"automatic_language_detection":false,"target_dpi":300,"max_dimension":4096,"tile_size":1600,"tile_overlap":240,"compute_device":"Vision automatic; same OS/build keyed", "renderer":"PDFKit.thumbnail.cropBox", "font_families":families,
                "document_structure":ProcessInfo.processInfo.operatingSystemVersion.majorVersion>=26,
                "ruled_grid_inference":"complete-dark-rectangles-v1; OCR tokens; inferred only",
                "font_inventory_sha256":digest(Data(inventory.utf8))]
    }
    static func process(_ input:[String:Any]) throws -> [String:Any] {
        guard let path = input["path"] as? String, let number = input["page"] as? Int, number > 0 else {throw NSError(domain:"DocverVision",code:1)}
        if cachedPath != path {cachedDocument=PDFDocument(url:URL(fileURLWithPath:path));cachedPath=path}
        guard let doc=cachedDocument, !doc.isLocked,
              number <= doc.pageCount, let page = doc.page(at:number-1) else {
            throw NSError(domain:"DocverVision",code:1,userInfo:[NSLocalizedDescriptionKey:"Invalid PDF/page or encrypted document"])
        }
        let bounds = page.bounds(for:.cropBox)
        guard bounds.width>0,bounds.height>0 else {throw NSError(domain:"DocverVision",code:2)}
        let scale=min(300.0/72.0,4096.0/max(bounds.width,bounds.height))
        let width=Int(ceil(bounds.width*scale)),height=Int(ceil(bounds.height*scale))
        let image = page.thumbnail(of:NSSize(width:width,height:height),for:.cropBox)
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw NSError(domain:"DocverVision",code:3) }
        raster=cg
        let bitmap = NSBitmapImageRep(cgImage:cg)
        guard let png = bitmap.representation(using:.png,properties:[:]) else { throw NSError(domain:"DocverVision",code:4) }
        if let output = input["render_path"] as? String { try png.write(to:URL(fileURLWithPath:output),options:.atomic) }
        let metadata:[String:Any]=["version":version,"revision":3,"languages":["ko-KR","en-US"],"language_correction":false,"renderer":"PDFKit.thumbnail.cropBox","width":cg.width,"height":cg.height,"viewport_width":bounds.width,"viewport_height":bounds.height,"rotation":page.rotation,"render_sha256":digest(png)]
        if input["render_only"] as? Bool == true {return metadata.merging(["ocr_performed":false,"verification":"not_requested","lines":[],"structure_status":"not_requested"]){_,new in new}}
        let numeric=try numericExpression()
        let r = try request();try VNImageRequestHandler(cgImage:cg,orientation:.up,options:[:]).perform([r])
        var tiles:[NumericReading] = []
        for y in stride(from:0,to:cg.height,by:1360){for x in stride(from:0,to:cg.width,by:1360){
            let rect=CGRect(x:x,y:y,width:min(1600,cg.width-x),height:min(1600,cg.height-y))
            guard rect.width>200,rect.height>100,let crop=cg.cropping(to:rect) else {continue}
            let tile=try request();try VNImageRequestHandler(cgImage:crop,orientation:.up,options:[:]).perform([tile])
            for result in tile.results ?? []{if let candidate=result.topCandidates(1).first{
                for match in numeric.matches(in:candidate.string,range:NSRange(candidate.string.startIndex...,in:candidate.string)){
                    guard let range=Range(match.range,in:candidate.string),let token=try? candidate.boundingBox(for:range) else {continue}
                    let b=token.boundingBox
                    // Partial tokens at tile boundaries are not conflicting complete observations.
                    if (x>0 && b.minX*rect.width<8)||(x+Int(rect.width)<cg.width && (1-b.maxX)*rect.width<8)||(y>0 && (1-b.maxY)*rect.height<8)||(y+Int(rect.height)<cg.height && b.minY*rect.height<8){continue}
                    tiles.append(NumericReading(text:canonicalNumber(String(candidate.string[range])),rect:CGRect(x:(rect.minX+b.minX*rect.width)/CGFloat(cg.width),y:(rect.minY+(1-b.maxY)*rect.height)/CGFloat(cg.height),width:b.width*rect.width/CGFloat(cg.width),height:b.height*rect.height/CGFloat(cg.height)),sources:["tile:\(x),\(y)"]))
                }
            }}
        }}
        let lines:[[String:Any]] = try (r.results ?? []).map { observation in
            let candidates = observation.topCandidates(3)
            let b = observation.boundingBox
            let text = candidates.first?.string ?? ""
            let lineRect=CGRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height)
            let strike=strikeCandidate(bitmap,lineRect)
            let strikeStatus = !supportedPixels(bitmap) ? "unsupported_format" : lineRect.width*CGFloat(cg.width)<=20 || lineRect.height*CGFloat(cg.height)<=8 ? "too_small" : strike != nil ? "detected":"not_detected"
            var recognized=tiles.filter{let intersection=$0.rect.intersection(lineRect);return !intersection.isNull && intersection.width*intersection.height>0.55*$0.rect.width*$0.rect.height}
            var required:[NumericReading]=[]
            var missingBounds=false
            if let candidate=candidates.first{
                for (index,match) in numeric.matches(in:text,range:NSRange(text.startIndex...,in:text)).enumerated(){
                    guard let range=Range(match.range,in:text) else {continue}
                    let requiredNumber=canonicalNumber(String(text[range]))
                    guard let token=try? candidate.boundingBox(for:range) else {missingBounds=true;continue}
                    let b=token.boundingBox
                    let tokenRect=CGRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height)
                    required.append(NumericReading(text:requiredNumber,rect:tokenRect,sources:["whole_page:\(index)"]))
                    if recognized.contains(where:{$0.text==requiredNumber && sameNumericRegion($0.rect,tokenRect)}){continue}
                    let cropRect=CGRect(x:b.minX*CGFloat(cg.width)-40,y:(1-b.maxY)*CGFloat(cg.height)-25,width:b.width*CGFloat(cg.width)+80,height:b.height*CGFloat(cg.height)+50).intersection(CGRect(x:0,y:0,width:cg.width,height:cg.height)).integral
                    guard let crop=cg.cropping(to:cropRect) else {continue}
                    let verify=try request();try VNImageRequestHandler(cgImage:crop,orientation:.up,options:[:]).perform([verify])
                    for result in verify.results ?? [] {guard let read=result.topCandidates(1).first else{continue}
                        for match in numeric.matches(in:read.string,range:NSRange(read.string.startIndex...,in:read.string)){
                            guard let range=Range(match.range,in:read.string),let box=try? read.boundingBox(for:range) else{continue}
                            let b=box.boundingBox,absolute=CGRect(x:(cropRect.minX+b.minX*cropRect.width)/CGFloat(cg.width),y:(cropRect.minY+(1-b.maxY)*cropRect.height)/CGFloat(cg.height),width:b.width*cropRect.width/CGFloat(cg.width),height:b.height*cropRect.height/CGFloat(cg.height))
                            if sameNumericRegion(absolute,tokenRect){recognized.append(NumericReading(text:canonicalNumber(String(read.string[range])),rect:absolute,sources:["crop:\(index)"]))}
                        }
                    }
                }
            }
            recognized=uniqueNumbers(recognized)
            let numericFormatOK=numericFormatSupported(text)
            let consensus = numericFormatOK && !missingBounds && numericAgreement(required,recognized)
            let tokens:[[String:Any]] = (try? NSRegularExpression(pattern:"\\S+").matches(in:text,range:NSRange(text.startIndex...,in:text)))?.compactMap { match in
                guard let range=Range(match.range,in:text),let word=try? candidates.first?.boundingBox(for:range) else {return nil}
                let b=word.boundingBox
                return ["text":String(text[range]),"bbox":[b.minX,1-b.maxY,b.width,b.height]]
            } ?? []
            return ["text":text, "confidence":Double(candidates.first?.confidence ?? 0),
                    "bbox":[b.minX,1-b.maxY,b.width,b.height],
                    "strike_candidate":strike != nil,"strike_status":strikeStatus,"strike_bbox":strike ?? [0,0,0,0],"numeric_consensus":consensus,"numeric_readings":recognized.map{$0.text},
                    "numeric_status":!numericFormatOK ? "unsupported_notation" : required.isEmpty ? "not_applicable" : consensus ? "verified":"conflicted",
                    "numeric_observations":recognized.map{["text":$0.text,"bbox":[$0.rect.minX,$0.rect.minY,$0.rect.width,$0.rect.height],"sources":$0.sources]},
                    "tokens":tokens,"alternatives":candidates.map { ["text":$0.string,"confidence":Double($0.confidence)] }]
        }.sorted { a,b in
            let x = a["bbox"] as! [CGFloat], y = b["bbox"] as! [CGFloat]
            return x[1]==y[1] ? x[0]<y[0] : x[1]<y[1]
        }
        return metadata.merging(["ocr_performed":true,"verification":"overlapping-1600px-tiles","lines":lines,
                                 "grid_tables":ruledTables(bitmap,lines),"grid_status":"complete_rectangular_grids_only_not_absence_proof"]){_,new in new}
    }
    // A second, conservative table observer. Vision can miss small ruled tables
    // in a page with columns/figures. These are raster grids, never OOXML cells.
    // Only complete rectangular rulings qualify; partial borders/merges withhold
    // the grid rather than guessing spans or filling missing text.
    static func ruledTables(_ image:NSBitmapImageRep,_ lines:[[String:Any]])->[[String:Any]] {
        guard lines.count>=3,supportedPixels(image),let data=image.bitmapData else{return []}
        let w=image.pixelsWide,h=image.pixelsHigh,s=image.samplesPerPixel,offset=image.bitmapFormat.contains(.alphaFirst) ? 1:0
        let gray=image.colorSpace.colorSpaceModel == .gray
        guard w>100,h>100,w<=4096,h<=4096 else{return []}
        var dark=[UInt8](repeating:0,count:w*h)
        for y in 0..<h {for x in 0..<w {let p=y*image.bytesPerRow+x*s+offset
            dark[y*w+x] = (gray ? Int(data[p])*100 : Int(data[p])*21+Int(data[p+1])*72+Int(data[p+2])*7)<17500 ? 1:0
        }}
        struct Rule {var y:Int;var x0:Int;var x1:Int;var bottom:Int}
        var rules:[Rule]=[]
        let minimum=max(80,w/12)
        for y in 0..<h {
            var start = -1,last = -1
            func finish(_ end:Int){
                guard start>=0,end-start>=minimum else{return}
                if let i=rules.indices.suffix(32).last(where:{rules[$0].bottom==y-1 && abs(rules[$0].x0-start)<=3 && abs(rules[$0].x1-end)<=3}){
                    rules[i].bottom=y
                }else{rules.append(Rule(y:y,x0:start,x1:end,bottom:y))}
            }
            for x in 0..<w {
                if dark[y*w+x]>0 {if start<0{start=x};last=x}
                else if start>=0 && x-last>2 {finish(last);start = -1}
            }
            finish(last)
            if rules.count>2000{return []}
        }
        rules=rules.filter{$0.bottom-$0.y<=max(6,h/300)}
        var groups:[[Rule]]=[]
        for r in rules {if let i=groups.firstIndex(where:{abs($0[0].x0-r.x0)<=4 && abs($0[0].x1-r.x1)<=4}){groups[i].append(r)}else{groups.append([r])}}
        var tables:[[String:Any]]=[]
        for group in groups where group.count>=3 && group.count<=64 {
            let sorted=group.sorted{$0.y<$1.y},gaps=zip(sorted,sorted.dropFirst()).map{$1.y-$0.bottom}.filter{$0>8}
            guard let smallest=gaps.min() else{continue}
            var chunks:[[Rule]]=[[]]
            for r in sorted {if let last=chunks[chunks.count-1].last,r.y-last.bottom>max(160,smallest*4){chunks.append([])};chunks[chunks.count-1].append(r)}
            for chunk in chunks where chunk.count>=3 {
                let x0=chunk.map{$0.x0}.min()!,x1=chunk.map{$0.x1}.max()!,ys=chunk.map{($0.y+$0.bottom)/2},top=ys.first!,bottom=ys.last!,height=bottom-top
                guard height>=24,let minRow=zip(ys,ys.dropFirst()).map({$1-$0}).min(),minRow>=12 else{continue}
                var full:[Int]=[],partial:[Int]=[]
                for x in max(0,x0-2)...min(w-1,x1+2) {
                    var count=0,longest=0,run=0,missing=0,maxMissing=0
                    for y in top...bottom {if dark[y*w+x]>0{count+=1;run+=1;missing=0;longest=max(longest,run)}else{missing+=1;maxMissing=max(maxMissing,missing);if missing>2{run=0}}}
                    if Double(count)/Double(height+1)>=0.96 && maxMissing<=4 {full.append(x)}
                    else if Double(longest)>=Double(minRow)*0.85 {partial.append(x)}
                }
                func centers(_ positions:[Int])->[Int]{var bands:[[Int]]=[];for x in positions{if let last=bands.last?.last,x-last<=1{bands[bands.count-1].append(x)}else{bands.append([x])}};return bands.map{($0.first!+$0.last!)/2}}
                let xs=centers(full)
                guard xs.count>=3,xs.count<=33,abs(xs[0]-x0)<=5,abs(xs.last!-x1)<=5,
                      zip(xs,xs.dropFirst()).allSatisfy({$1-$0>=12}),
                      !partial.contains(where:{x in !xs.contains(where:{abs($0-x)<=4})}),
                      (xs.count-1)*(ys.count-1)<=1000 else{continue}
                var cells:[[String:Any]]=[],occupiedRows=Set<Int>(),occupiedColumns=Set<Int>()
                for row in 0..<(ys.count-1) {for col in 0..<(xs.count-1) {
                    let cell=CGRect(x:CGFloat(xs[col])/CGFloat(w),y:CGFloat(ys[row])/CGFloat(h),width:CGFloat(xs[col+1]-xs[col])/CGFloat(w),height:CGFloat(ys[row+1]-ys[row])/CGFloat(h))
                    var words:[(String,CGRect,Bool)]=[]
                    for line in lines {for token in line["tokens"] as? [[String:Any]] ?? [] {
                        guard let text=token["text"] as? String,let b=token["bbox"] as? [CGFloat],b.count==4 else{continue}
                        let rect=CGRect(x:b[0],y:b[1],width:b[2],height:b[3]),intersection=cell.intersection(rect)
                        if cell.contains(CGPoint(x:rect.midX,y:rect.midY)),!intersection.isNull,intersection.width*intersection.height>=rect.width*rect.height*0.6{words.append((text,rect,(line["confidence"] as? Double ?? 0)>=0.5 && (line["numeric_consensus"] as? Bool ?? false) && !(line["alternatives"] as? [[String:Any]] ?? []).contains(where:{($0["text"] as? String) != (line["text"] as? String) && ($0["confidence"] as? Double ?? 0)>=(line["confidence"] as? Double ?? 0)-0.15})))}
                    }}
                    words.sort{$0.1.midY==$1.1.midY ? $0.1.minX<$1.1.minX : $0.1.midY<$1.1.midY}
                    var textRows:[[(String,CGRect,Bool)]]=[]
                    for word in words {
                        if let last=textRows.last?.first,abs(last.1.midY-word.1.midY)<=min(last.1.height,word.1.height)*0.6{textRows[textRows.count-1].append(word)}
                        else{textRows.append([word])}
                    }
                    let text=textRows.map{$0.sorted{$0.1.minX<$1.1.minX}.map{$0.0}.joined(separator:" ")}.joined(separator:"\n")
                    if !text.isEmpty{occupiedRows.insert(row);occupiedColumns.insert(col)}
                    cells.append(["row":row,"column":col,"row_span":1,"column_span":1,"text":text,"text_confident":!words.isEmpty && words.allSatisfy{$0.2},"bbox":[cell.minX,cell.minY,cell.width,cell.height]])
                }}
                guard cells.filter({!($0["text"] as! String).isEmpty}).count>=3,occupiedRows.count>=2,occupiedColumns.count>=2 else{continue}
                tables.append(["cells":cells]);if tables.count>=50{return tables}
            }
        }
        return tables
    }
    static func strikeCandidate(_ image:NSBitmapImageRep,_ line:CGRect)->[Double]?{
        guard supportedPixels(image),let data=image.bitmapData else {return nil}
        let w=image.pixelsWide,h=image.pixelsHigh,s=image.samplesPerPixel,offset=image.bitmapFormat.contains(.alphaFirst) ? 1:0
        let gray=image.colorSpace.colorSpaceModel == .gray
        let x0=max(0,Int(line.minX*CGFloat(w))),x1=min(w-1,Int(line.maxX*CGFloat(w))),y0=max(0,Int(line.minY*CGFloat(h))),y1=min(h-1,Int(line.maxY*CGFloat(h)))
        guard x1-x0>20,y1-y0>8 else {return nil}
        func color(_ x:Int,_ y:Int)->[Int]{let p=max(0,min(h-1,y))*image.bytesPerRow+max(0,min(w-1,x))*s+offset;return gray ? [Int](repeating:Int(data[p]),count:3) : [Int(data[p]),Int(data[p+1]),Int(data[p+2])]}
        let samples=[x0,(x0+x1)/2,x1].flatMap{x in [color(x,y0-4),color(x,y1+4)]}
        let bg=(0..<3).map{c in samples.map{$0[c]}.sorted()[samples.count/2]}
        var band=0,bestBand=0,bestX=x0,bestY=y0,bestWidth=0
        for y in (y0+(y1-y0)/4)...(y0+3*(y1-y0)/4){
            var run=0,longest=0,start=x0
            for x in x0...x1 {let c=color(x,y);if zip(c,bg).reduce(0,{$0+abs($1.0-$1.1)})>135 {run+=1;if run>longest{longest=run;start=x-run+1}}else{run=0}}
            if Double(longest)>0.72*Double(x1-x0){band+=1;if band>bestBand{bestBand=band;bestX=start;bestY=y-band+1;bestWidth=longest}}else{band=0}
        }
        guard bestBand>0,Double(bestBand)<=0.22*Double(y1-y0) else {return nil}
        return [Double(bestX)/Double(w),Double(bestY)/Double(h),Double(bestWidth)/Double(w),Double(bestBand)/Double(h)]
    }
    @available(macOS 26.0, *)
    static func structure(_ image:CGImage) async throws -> [String:Any] {
        var request=RecognizeDocumentsRequest(.revision1)
        request.textRecognitionOptions.recognitionLanguages=[Locale.Language(identifier:"ko-KR"),Locale.Language(identifier:"en-US")]
        request.textRecognitionOptions.automaticallyDetectLanguage=false
        request.textRecognitionOptions.useLanguageCorrection=false
        request.textRecognitionOptions.maximumCandidateCount=3
        request.barcodeDetectionOptions.enabled=false
        let observations=try await request.perform(on:image,orientation:.up)
        var tables:[[String:Any]]=[]
        for document in observations {for table in document.document.tables{
            var cells:[[String:Any]]=[]
            for row in table.rows {for cell in row{
                let b=cell.content.boundingRegion.boundingBox.cgRect
                cells.append(["row":cell.rowRange.lowerBound,"column":cell.columnRange.lowerBound,"row_span":cell.rowRange.count,"column_span":cell.columnRange.count,"text":cell.content.text.transcript,"bbox":[b.minX,1-b.maxY,b.width,b.height]])
            }}
            tables.append(["cells":cells])
        }}
        return ["structure_status":"available","structure_engine":"Vision.RecognizeDocumentsRequest.revision1","tables":tables]
    }
    static func main() async {
        do {
            func one(_ input:[String:Any]) async throws->[String:Any]{
                defer{raster=nil}
                var result=try autoreleasepool{try process(input)}
                if result["ocr_performed"] as? Bool == true,let image=raster{
                    if #available(macOS 26.0, *) {do{result.merge(try await structure(image)){_,new in new}}catch{result["structure_status"]="failed"}}
                    else{result["structure_status"]="unsupported_os"}
                }
                return result
            }
            var result:[String:Any]
            if CommandLine.arguments.count==2 && CommandLine.arguments[1]=="--info"{result=try info()}
            else{
                guard let input=try JSONSerialization.jsonObject(with:FileHandle.standardInput.readDataToEndOfFile()) as? [String:Any] else {throw NSError(domain:"DocverVision",code:1)}
                if let pages=input["pages"] as? [Int]{
                    guard pages.count<=16 else{throw NSError(domain:"DocverVision",code:6)}
                    let ocr=Set(input["ocr_pages"] as? [Int] ?? []);var rows:[[String:Any]]=[]
                    for page in pages{var args=input;args["page"]=page;args["render_only"] = !ocr.contains(page)
                        do{rows.append(["page":page,"result":try await one(args)])}catch{rows.append(["page":page,"error":String(describing:type(of:error))])}
                    }
                    result=["pages":rows]
                }else{result=try await one(input)}
            }
            let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
            FileHandle.standardOutput.write(data)
        } catch {
            let data = try! JSONSerialization.data(withJSONObject:["error":error.localizedDescription],options:[.sortedKeys])
            FileHandle.standardOutput.write(data); exit(1)
        }
    }
}
