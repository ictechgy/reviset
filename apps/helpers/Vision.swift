import Foundation
import AppKit
import PDFKit
import Vision
import CryptoKit
import CoreText

// A local, versioned process boundary. No network, model download, or language correction.
@main struct DocverVision {
    static let version = "docver-vision-4-batched-raster-strike"
    static var raster: CGImage?
    static var cachedPath=""
    static var cachedDocument:PDFDocument?
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format:"%02x", $0) }.joined() }
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
        let numeric=try NSRegularExpression(pattern:"[+−-]?\\s*[0-9]+(?:\\s*[.,]\\s*[0-9]+)*(?:\\s*(?:%|억|만|원))?")
        func numbers(_ text:String)->[String]{numeric.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap{Range($0.range,in:text).map{String(text[$0]).filter{!$0.isWhitespace}}}}
        let r = try request();try VNImageRequestHandler(cgImage:cg,orientation:.up,options:[:]).perform([r])
        var tiles:[(String,CGRect)] = []
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
                    tiles.append((String(candidate.string[range]).filter{!$0.isWhitespace},CGRect(x:(rect.minX+b.minX*rect.width)/CGFloat(cg.width),y:(rect.minY+(1-b.maxY)*rect.height)/CGFloat(cg.height),width:b.width*rect.width/CGFloat(cg.width),height:b.height*rect.height/CGFloat(cg.height))))
                }
            }}
        }}
        let lines:[[String:Any]] = try (r.results ?? []).map { observation in
            let candidates = observation.topCandidates(3)
            let b = observation.boundingBox
            let text = candidates.first?.string ?? ""
            let lineRect=CGRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height),required=numbers(text)
            let strike=strikeCandidate(bitmap,lineRect)
            let relevant=tiles.filter{let intersection=$0.1.intersection(lineRect);return !intersection.isNull && intersection.height>min($0.1.height,lineRect.height)*0.5 && intersection.width>0}
            var recognized=relevant.flatMap{numbers($0.0)}
            if let candidate=candidates.first{
                for match in numeric.matches(in:text,range:NSRange(text.startIndex...,in:text)){
                    guard let range=Range(match.range,in:text) else {continue}
                    let requiredNumber=String(text[range]).filter{!$0.isWhitespace}
                    if recognized.contains(requiredNumber){continue}
                    guard let token=try? candidate.boundingBox(for:range) else {continue}
                    let b=token.boundingBox
                    let cropRect=CGRect(x:b.minX*CGFloat(cg.width)-40,y:(1-b.maxY)*CGFloat(cg.height)-25,width:b.width*CGFloat(cg.width)+80,height:b.height*CGFloat(cg.height)+50).intersection(CGRect(x:0,y:0,width:cg.width,height:cg.height)).integral
                    guard let crop=cg.cropping(to:cropRect) else {continue}
                    let verify=try request();try VNImageRequestHandler(cgImage:crop,orientation:.up,options:[:]).perform([verify])
                    recognized += (verify.results ?? []).flatMap{$0.topCandidates(1).flatMap{numbers($0.string)}}
                }
            }
            let consensus=required.allSatisfy{recognized.contains($0)} && recognized.allSatisfy{required.contains($0)}
            let tokens:[[String:Any]] = (try? NSRegularExpression(pattern:"\\S+").matches(in:text,range:NSRange(text.startIndex...,in:text)))?.compactMap { match in
                guard let range=Range(match.range,in:text),let word=try? candidates.first?.boundingBox(for:range) else {return nil}
                let b=word.boundingBox
                return ["text":String(text[range]),"bbox":[b.minX,1-b.maxY,b.width,b.height]]
            } ?? []
            return ["text":text, "confidence":Double(candidates.first?.confidence ?? 0),
                    "bbox":[b.minX,1-b.maxY,b.width,b.height],
                    "strike_candidate":strike != nil,"strike_bbox":strike ?? [0,0,0,0],"numeric_consensus":consensus,"numeric_readings":recognized,"tokens":tokens,"alternatives":candidates.map { ["text":$0.string,"confidence":Double($0.confidence)] }]
        }.sorted { a,b in
            let x = a["bbox"] as! [CGFloat], y = b["bbox"] as! [CGFloat]
            return abs(x[1]-y[1]) > 0.015 ? x[1] < y[1] : x[0] < y[0]
        }
        return metadata.merging(["ocr_performed":true,"verification":"overlapping-1600px-tiles","lines":lines]){_,new in new}
    }
    static func strikeCandidate(_ image:NSBitmapImageRep,_ line:CGRect)->[Double]?{
        guard !image.isPlanar,image.bitsPerSample==8,image.samplesPerPixel>=3,let data=image.bitmapData else {return nil}
        let w=image.pixelsWide,h=image.pixelsHigh,s=image.samplesPerPixel,offset=image.bitmapFormat.contains(.alphaFirst) ? 1:0
        let x0=max(0,Int(line.minX*CGFloat(w))),x1=min(w-1,Int(line.maxX*CGFloat(w))),y0=max(0,Int(line.minY*CGFloat(h))),y1=min(h-1,Int(line.maxY*CGFloat(h)))
        guard x1-x0>20,y1-y0>8 else {return nil}
        func color(_ x:Int,_ y:Int)->[Int]{let p=max(0,min(h-1,y))*image.bytesPerRow+max(0,min(w-1,x))*s+offset;return [Int(data[p]),Int(data[p+1]),Int(data[p+2])]}
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
                var result=try autoreleasepool{try process(input)}
                if result["ocr_performed"] as? Bool == true,let image=raster{
                    if #available(macOS 26.0, *) {do{result.merge(try await structure(image)){_,new in new}}catch{result["structure_status"]="failed"}}
                    else{result["structure_status"]="unsupported_os"}
                }
                raster=nil;return result
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
