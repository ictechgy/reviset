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
    static let version = "docver-vision-26-all-profile-raw-guard"
    static var raster: CGImage?
    static var cachedPath=""
    static var cachedDocument:PDFDocument?
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format:"%02x", $0) }.joined() }
    static let vulgarFractions="[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞↉]"
    static func numericExpression() throws->NSRegularExpression {
        try NSRegularExpression(pattern:"(?:(?<![\\p{L}\\p{N}])[+＋−－-]\\p{White_Space}*)?(?:(?<![\\p{N}.,，．])[0-9０-９]+\\p{White_Space}*[/⁄／]\\p{White_Space}*[0-9０-９]+(?!\\p{N}|[.,，．][0-9０-９])|\(vulgarFractions)|(?:[0-9０-９]*(?:[.,，．][0-9０-９]+)+|[0-9０-９]+))(?:\\p{White_Space}*(?:[%％]|억|만|원))?")
    }
    static func canonicalNumber(_ text:String)->String{text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of:"−",with:"-").replacingOccurrences(of:"⁄",with:"/").replacingOccurrences(of:"\\p{White_Space}",with:"",options:.regularExpression)}
    static func numericFormatSupported(_ text:String)->Bool {
        func matches(_ pattern:String,_ value:String)->Bool{value.range(of:pattern,options:.regularExpression) != nil}
        if matches("(?=\\p{N})[^0-9０-９]",text.replacingOccurrences(of:vulgarFractions,with:"",options:.regularExpression)){return false}
        if matches("\\p{N}",text) && (matches("\\p{Default_Ignorable_Code_Point}|(?=\\p{Cc})[^\\p{White_Space}]|[∕⧸╱⟋]",text) || matches("[\\p{N}/⁄／]\\p{M}|\\p{M}[/⁄／\\p{N}]",text)){return false}
        // Regex ranges are UTF-16 scalar boundaries in both implementations;
        // Character iteration would hide slashes joined to combining marks.
        let ns=text as NSString,range=NSRange(location:0,length:(text as NSString).length)
        let slashes=try! NSRegularExpression(pattern:"[/⁄／]").matches(in:text,range:range)
        if slashes.isEmpty{return true}
        let slots=(try? numericExpression().matches(in:text,range:range)) ?? []
        let dates=try! NSRegularExpression(pattern:"(?<![0-9０-９.,，．/⁄／])[0-9０-９]{1,4}\\p{White_Space}*[/⁄／]\\p{White_Space}*[0-9０-９]{1,2}\\p{White_Space}*[/⁄／]\\p{White_Space}*[0-9０-９]{1,4}(?![0-9０-９/⁄／]|[.,，．][0-9０-９])").matches(in:text,range:range)
        var next=0,date=0
        for slash in slashes {
            let at=slash.range.location
            while next<slots.count && NSMaxRange(slots[next].range)<=at{next+=1}
            while date<dates.count && NSMaxRange(dates[date].range)<=at{date+=1}
            if next<slots.count && slots[next].range.location<at && at<NSMaxRange(slots[next].range) && canonicalNumber(ns.substring(with:slots[next].range)).contains("/"){continue}
            if date<dates.count && dates[date].range.location<at && at<NSMaxRange(dates[date].range){continue}
            let left:String?=next>0 ? ns.substring(with:NSRange(location:NSMaxRange(slots[next-1].range),length:at-NSMaxRange(slots[next-1].range))) : nil
            let right:String?=next<slots.count ? ns.substring(with:NSRange(location:at+1,length:slots[next].range.location-at-1)) : nil
            if at>0 && at+1<ns.length && matches("\\p{White_Space}",ns.substring(with:NSRange(location:at-1,length:1))) && matches("\\p{White_Space}",ns.substring(with:NSRange(location:at+1,length:1))) && left.map({matches("^[\\p{L}\\p{Sc}%％\\p{White_Space}]*$",$0)}) == true && right.map({matches("^[\\p{White_Space}\\p{Sc}]*$",$0)}) == true{continue}
            if matches("^\\p{L}+(?=$|[^\\p{L}\\p{N}\\p{M}])",ns.substring(from:at+1)){continue}
            // Numeric-line slashes require an explicit supported grammar;
            // partial operands and unknown unit punctuation cannot verify.
            if !slots.isEmpty{return false}
        }
        return true
    }
    static func supportedPixels(_ image:NSBitmapImageRep)->Bool {
        !image.isPlanar && image.bitsPerSample==8 && image.bitsPerPixel==image.samplesPerPixel*8 && !image.bitmapFormat.contains(.sixteenBitLittleEndian) && !image.bitmapFormat.contains(.thirtyTwoBitLittleEndian) && ((image.colorSpace.colorSpaceModel == .rgb && [3,4].contains(image.samplesPerPixel)) || (image.colorSpace.colorSpaceModel == .gray && [1,2].contains(image.samplesPerPixel)))
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
    static func numericStatus(_ required:[NumericReading],_ readings:[NumericReading],missingBounds:Bool=false,formatSupported:Bool=true)->String {
        if !formatSupported{return "unsupported_notation"}
        let observed=uniqueNumbers(readings)
        if !missingBounds && numericAgreement(required,observed){return required.isEmpty ? "not_applicable":"verified"}
        if (!missingBounds && observed.contains(where:{o in !required.contains(where:{sameNumericRegion($0.rect,o.rect)})})) || required.contains(where:{r in observed.contains(where:{sameNumericRegion(r.rect,$0.rect) && r.text != $0.text})}){return "conflicted"}
        return "unverified"
    }
    static func orderedLines(_ lines:[[String:Any]])->[[String:Any]] {
        func rect(_ i:Int)->CGRect{let b=lines[i]["bbox"] as! [CGFloat];return CGRect(x:b[0],y:b[1],width:b[2],height:b[3])}
        let order=lines.indices.sorted{let a=rect($0),b=rect($1);return a.minY != b.minY ? a.minY<b.minY : a.minX != b.minX ? a.minX<b.minX : $0<$1}
        var bands:[[Int]]=[]
        for i in order {
            let b=rect(i)
            if let anchor=bands.last?.first {let a=rect(anchor)
                if a.minY<=b.midY && b.midY<=a.maxY && b.minY<=a.midY && a.midY<=b.maxY {bands[bands.count-1].append(i);continue}
            }
            bands.append([i])
        }
        return bands.flatMap{$0.sorted{let a=rect($0),b=rect($1);return a.minX != b.minX ? a.minX<b.minX : a.minY != b.minY ? a.minY<b.minY : $0<$1}}.map{lines[$0]}
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
                "reconsideration_policy":reconsiderationPolicy,"document_structure":ProcessInfo.processInfo.operatingSystemVersion.majorVersion>=26,
                "ruled_grid_inference":"complete-dark-solid-rectangles-v4; local-contrast interior-boundary rejection; OCR tokens; inferred only",
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
        // The caller publishes the PNG after the isolated job exits. Foundation
        // atomic writes can stage outside that job and are denied by its sandbox.
        if let output = input["render_path"] as? String { try png.write(to:URL(fileURLWithPath:output)) }
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
        let primaryLines:[[String:Any]] = orderedLines(try (r.results ?? []).map { observation in
            let candidates = observation.topCandidates(3)
            let b = observation.boundingBox
            let text = candidates.first?.string ?? ""
            let lineRect=CGRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height)
            let strikeResult=strikeObservation(bitmap,lineRect),strike=strikeResult.bbox
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
            let status=numericStatus(required,recognized,missingBounds:missingBounds,formatSupported:numericFormatSupported(text))
            let consensus=["verified","not_applicable"].contains(status)
            let tokens:[[String:Any]] = (try? NSRegularExpression(pattern:"\\S+").matches(in:text,range:NSRange(text.startIndex...,in:text)))?.compactMap { match in
                guard let range=Range(match.range,in:text),let word=try? candidates.first?.boundingBox(for:range) else {return nil}
                let b=word.boundingBox
                return ["text":String(text[range]),"bbox":[b.minX,1-b.maxY,b.width,b.height]]
            } ?? []
            return ["text":text, "confidence":Double(candidates.first?.confidence ?? 0),
                    "bbox":[b.minX,1-b.maxY,b.width,b.height],
                    "strike_candidate":strike != nil,"strike_status":strikeResult.status,"strike_bbox":strike ?? [0,0,0,0],"numeric_consensus":consensus,"numeric_readings":recognized.map{$0.text},
                    "numeric_status":status,
                    "numeric_observations":recognized.map{["text":$0.text,"bbox":[$0.rect.minX,$0.rect.minY,$0.rect.width,$0.rect.height],"sources":$0.sources]},
                    "tokens":tokens,"alternatives":candidates.map { ["text":$0.string,"confidence":Double($0.confidence)] }]
        })
        let lines=reconsideredLines(cg,bitmap,primaryLines,r.results ?? [])
        let grid=gridObservation(bitmap,lines)
        return metadata.merging(["ocr_performed":true,"verification":"overlapping-1600px-tiles","lines":lines,
                                 "grid_tables":grid.tables,"grid_status":grid.status,"grid_reasons":grid.reasons,
                                 "bitmap_format":bitmap.bitmapFormat.rawValue,"bitmap_bits_per_sample":bitmap.bitsPerSample,"bitmap_bits_per_pixel":bitmap.bitsPerPixel]){_,new in new}
    }
    // A second, conservative table observer. Vision can miss small ruled tables
    // in a page with columns/figures. These are raster grids, never OOXML cells.
    // Only complete rectangular rulings qualify; partial borders/merges withhold
    // the grid rather than guessing spans or filling missing text.
    struct GridObservation {var tables:[[String:Any]];var status:String;var reasons:[String]}
    static func ruledTables(_ image:NSBitmapImageRep,_ lines:[[String:Any]])->[[String:Any]] {gridObservation(image,lines).tables}
    static func gridObservation(_ image:NSBitmapImageRep,_ lines:[[String:Any]])->GridObservation {
        guard supportedPixels(image),let data=image.bitmapData else{return GridObservation(tables:[],status:"unsupported_format",reasons:["unsupported_bitmap_layout"])}
        guard lines.count>=3 else{return GridObservation(tables:[],status:"insufficient_text",reasons:["fewer_than_three_text_observations"])}
        let w=image.pixelsWide,h=image.pixelsHigh,s=image.samplesPerPixel,offset=image.bitmapFormat.contains(.alphaFirst) ? 1:0
        let gray=image.colorSpace.colorSpaceModel == .gray
        guard w>100,h>100,w<=4096,h<=4096 else{return GridObservation(tables:[],status:"unsupported_dimensions",reasons:["grid_dimensions_outside_101_to_4096"])}
        var dark=[UInt8](repeating:0,count:w*h),light=[UInt8](repeating:0,count:w*h)
        for y in 0..<h {for x in 0..<w {let p=y*image.bytesPerRow+x*s+offset
            let luminance=gray ? Int(data[p])*100 : Int(data[p])*21+Int(data[p+1])*72+Int(data[p+2])*7
            dark[y*w+x] = luminance<17500 ? 1:0
            light[y*w+x] = UInt8(luminance/100)
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
            if rules.count>2000{return GridObservation(tables:[],status:"budget_exceeded",reasons:["horizontal_rule_limit_2000"])}
        }
        rules=rules.filter{$0.bottom-$0.y<=max(6,h/300)}
        var groups:[[Rule]]=[]
        for r in rules {if let i=groups.firstIndex(where:{abs($0[0].x0-r.x0)<=4 && abs($0[0].x1-r.x1)<=4}){groups[i].append(r)}else{groups.append([r])}}
        var tables:[[String:Any]]=[],rejected=Set<String>(),budget=Set<String>()
        for group in groups where group.count>=3 {
            guard group.count<=64 else{budget.insert("row_rule_limit_64");continue}
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
                guard xs.count>=3,abs(xs[0]-x0)<=5,abs(xs.last!-x1)<=5,
                      zip(xs,xs.dropFirst()).allSatisfy({$1-$0>=12}) else{continue}
                guard xs.count<=33 else{budget.insert("column_rule_limit_33");continue}
                guard (xs.count-1)*(ys.count-1)<=1000 else{budget.insert("cell_limit_1000");continue}
                if partial.contains(where:{x in !xs.contains(where:{abs($0-x)<=4})}){rejected.insert("partial_vertical_divider");continue}
                // Equal-endpoint grouping excludes partial horizontal dividers.
                // Inspect pixels between the accepted rows as well: otherwise a
                // merged/partial row can silently become a larger regular cell.
                let minColumn=zip(xs,xs.dropFirst()).map{$1-$0}.min()!,borderTolerance=max(4,h/600+2)
                var partialHorizontal=false
                for y in (top+1)..<bottom where !ys.contains(where:{abs($0-y)<=borderTolerance}) {
                    var run=0,missing=0
                    for x in x0...x1 {
                        if dark[y*w+x]>0{run+=1;missing=0}
                        else{missing+=1;if missing>2{run=0}}
                        if Double(run)>=Double(minColumn)*0.85{partialHorizontal=true;break}
                    }
                    if partialHorizontal{break}
                }
                if partialHorizontal{rejected.insert("partial_horizontal_divider");continue}
                // A weaker observer may reject an unsafe coarse grid, but cannot
                // establish a new boundary. It detects light/dashed dividers that
                // strict continuous dark-rule acceptance intentionally excludes.
                func boundary(_ start:Int,_ end:Int,_ sample:(Int)->UInt8)->Bool {
                    let length=end-start+1,maxGap=max(6,length/6);var count=0,first=end+1,last=start-1,gap=0,longestGap=0
                    for n in start...end {if sample(n)>0{count+=1;first=min(first,n);last=n;gap=0}else{gap+=1;longestGap=max(longestGap,gap)}}
                    return Double(count)>=Double(length)*0.45 && first-start<=maxGap && end-last<=maxGap && longestGap<=maxGap
                }
                var ambiguous=false
                // A faint ruling is a narrow local contrast, not merely a gray
                // pixel. Require lighter background on both perpendicular sides
                // so uniform off-white pages and broad cell fills remain valid.
                let flank=borderTolerance+1
                func weakHorizontal(_ x:Int,_ y:Int)->UInt8 {
                    guard y>=flank,y+flank<h else{return 0}
                    let center=Int(light[y*w+x])
                    return center<245 && center+6<=min(Int(light[(y-flank)*w+x]),Int(light[(y+flank)*w+x])) ? 1:0
                }
                func weakVertical(_ x:Int,_ y:Int)->UInt8 {
                    guard x>=flank,x+flank<w else{return 0}
                    let center=Int(light[y*w+x])
                    return center<245 && center+6<=min(Int(light[y*w+x-flank]),Int(light[y*w+x+flank])) ? 1:0
                }
                for y in (top+1)..<bottom where !ys.contains(where:{abs($0-y)<=borderTolerance}) {
                    if zip(xs,xs.dropFirst()).contains(where:{a,b in boundary(a,b,{weakHorizontal($0,y)})}){ambiguous=true;break}
                }
                if !ambiguous {for x in (x0+1)..<x1 where !xs.contains(where:{abs($0-x)<=borderTolerance}) {
                    if zip(ys,ys.dropFirst()).contains(where:{a,b in boundary(a,b,{weakVertical(x,$0)})}){ambiguous=true;break}
                }}
                if ambiguous{rejected.insert("faint_or_dashed_interior_boundary");continue}
                var cells:[[String:Any]]=[],occupiedRows=Set<Int>(),occupiedColumns=Set<Int>()
                for row in 0..<(ys.count-1) {for col in 0..<(xs.count-1) {
                    let cell=CGRect(x:CGFloat(xs[col])/CGFloat(w),y:CGFloat(ys[row])/CGFloat(h),width:CGFloat(xs[col+1]-xs[col])/CGFloat(w),height:CGFloat(ys[row+1]-ys[row])/CGFloat(h))
                    var words:[(String,CGRect,Bool)]=[]
                    for line in lines {for token in line["tokens"] as? [[String:Any]] ?? [] {
                        guard let text=token["text"] as? String,let b=token["bbox"] as? [CGFloat],b.count==4 else{continue}
                        let rect=CGRect(x:b[0],y:b[1],width:b[2],height:b[3]),intersection=cell.intersection(rect)
                        if cell.contains(CGPoint(x:rect.midX,y:rect.midY)),!intersection.isNull,intersection.width*intersection.height>=rect.width*rect.height*0.6{words.append((text,rect,(line["confidence"] as? Double ?? 0)>=0.5 && (line["numeric_consensus"] as? Bool ?? false) && (line["strike_candidate"] as? Bool)==false && (line["strike_status"] as? String)=="not_detected" && !(line["alternatives"] as? [[String:Any]] ?? []).contains(where:{($0["text"] as? String) != (line["text"] as? String) && ($0["confidence"] as? Double ?? 0)>=(line["confidence"] as? Double ?? 0)-0.15})))}
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
                tables.append(["cells":cells]);if tables.count>=50{return GridObservation(tables:tables,status:"partial",reasons:Array(rejected.union(budget).union(["table_limit_50"])).sorted())}
            }
        }
        let reasons=rejected.union(budget)
        return GridObservation(tables:tables,status:!budget.isEmpty ? (tables.isEmpty ? "budget_exceeded":"partial"):rejected.isEmpty ? (tables.isEmpty ? "not_detected":"available"):(tables.isEmpty ? "ambiguous_boundaries":"partial"),reasons:Array(reasons).sorted())
    }
    static func strikeCandidate(_ image:NSBitmapImageRep,_ line:CGRect)->[Double]?{
        strikeObservation(image,line).bbox
    }
    static func strikeObservation(_ image:NSBitmapImageRep,_ line:CGRect)->(bbox:[Double]?,status:String){
        guard supportedPixels(image),let data=image.bitmapData else {return (nil,"unsupported_format")}
        let w=image.pixelsWide,h=image.pixelsHigh,s=image.samplesPerPixel,offset=image.bitmapFormat.contains(.alphaFirst) ? 1:0
        let gray=image.colorSpace.colorSpaceModel == .gray
        let x0=max(0,Int(line.minX*CGFloat(w))),x1=min(w-1,Int(line.maxX*CGFloat(w))),y0=max(0,Int(line.minY*CGFloat(h))),y1=min(h-1,Int(line.maxY*CGFloat(h)))
        guard x1-x0>20,y1-y0>8 else {return (nil,"too_small")}
        func color(_ x:Int,_ y:Int)->[Int]{let p=max(0,min(h-1,y))*image.bytesPerRow+max(0,min(w-1,x))*s+offset;return gray ? [Int](repeating:Int(data[p]),count:3) : [Int(data[p]),Int(data[p+1]),Int(data[p+2])]}
        let samples=[x0,(x0+x1)/2,x1].flatMap{x in [color(x,y0-4),color(x,y1+4)]}
        let bg=(0..<3).map{c in samples.map{$0[c]}.sorted()[samples.count/2]}
        var band=0,bestBand=0,bestX=x0,bestY=y0,bestWidth=0
        for y in (y0+(y1-y0)/4)...(y0+3*(y1-y0)/4){
            var run=0,longest=0,start=x0
            for x in x0...x1 {let c=color(x,y);if zip(c,bg).reduce(0,{$0+abs($1.0-$1.1)})>135 {run+=1;if run>longest{longest=run;start=x-run+1}}else{run=0}}
            if Double(longest)>0.72*Double(x1-x0){band+=1;if band>bestBand{bestBand=band;bestX=start;bestY=y-band+1;bestWidth=longest}}else{band=0}
        }
        guard bestBand>0,Double(bestBand)<=0.22*Double(y1-y0) else {return (nil,"not_detected")}
        return ([Double(bestX)/Double(w),Double(bestY)/Double(h),Double(bestWidth)/Double(w),Double(bestBand)/Double(h)],"detected")
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
