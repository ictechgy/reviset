import Foundation
import AppKit
import Vision

extension DocverVision {
    // A bounded second observation. Primary strings/confidences are never edited.
    static func clippedRoiRect(_ raw:CGRect,_ bounds:CGRect)->(rect:CGRect,edge:Bool)? {
        guard [raw.minX,raw.minY,raw.width,raw.height].allSatisfy({$0.isFinite}),raw.width>0,raw.height>0 else{return nil}
        let rect=raw.intersection(bounds)
        guard !rect.isNull,!rect.isEmpty else{return nil}
        return (rect,!bounds.contains(raw))
    }
    static func uniformWhitePixels(_ image:NSBitmapImageRep,_ rect:CGRect)->Bool {
        let bounds=CGRect(x:0,y:0,width:image.pixelsWide,height:image.pixelsHigh)
        guard supportedPixels(image),let data=image.bitmapData,[rect.minX,rect.minY,rect.width,rect.height].allSatisfy({$0.isFinite}),rect.width>0,rect.height>0,bounds.contains(rect),rect.integral.width*rect.integral.height<=262_144 else{return false}
        let pixels=rect.integral,s=image.samplesPerPixel,first=image.bitmapFormat.contains(.alphaFirst),offset=first ? 1:0,channels=image.colorSpace.colorSpaceModel == .gray ? 1:3
        for y in Int(pixels.minY)..<Int(pixels.maxY){for x in Int(pixels.minX)..<Int(pixels.maxX){
            let at=y*image.bytesPerRow+x*s
            if image.hasAlpha && data[at+(first ? 0:s-1)] != 255{return false}
            for c in 0..<channels{if data[at+offset+c] != 255{return false}}
        }}
        return true
    }
    static let hangulScript=try! NSRegularExpression(pattern:"\\p{script=Hangul}")
    static func roiCompact(_ text:String)->String {
        text.precomposedStringWithCanonicalMapping.replacingOccurrences(of:"[\\p{White_Space}\\x{FEFF}]",with:"",options:.regularExpression).lowercased()
    }
    static let reconsiderationPolicy="vision-roi-v2; 4 weak/borderline nonnumeric lines/page; weak first; 8 contexts; 262144 core pixels; 4M pixels/crop; 12s/page best-effort cancellation; no language correction"
    static func reconsideredLines(_ image:CGImage,_ bitmap:NSBitmapImageRep,_ lines:[[String:Any]],_ observations:[VNRecognizedTextObservation]=[])->[[String:Any]] {
        let deadline=DispatchTime.now()+12.0
        let eligible=lines.enumerated().compactMap { (index,line)->(index:Int,priority:Int,rect:CGRect,text:String)? in
            guard let text=line["text"] as? String,!text.isEmpty,text.utf16.count<=128,
                  text.range(of:"\\p{N}",options:.regularExpression)==nil,
                  line["numeric_consensus"] as? Bool == true,
                  line["strike_candidate"] as? Bool == false,
                  line["strike_status"] as? String == "not_detected",
                  let confidence=line["confidence"] as? Double,let b=line["bbox"] as? [CGFloat],b.count==4 else{return nil}
            let alternatives=line["alternatives"] as? [[String:Any]] ?? []
            let ambiguous=alternatives.contains{candidate in
                guard let value=candidate["text"] as? String,let score=candidate["confidence"] as? Double else{return false}
                return roiCompact(value) != roiCompact(text) && score>=confidence-0.15
            }
            guard confidence<=0.5 || ambiguous else{return nil}
            return (index,confidence<0.5 || ambiguous ? 0:1,CGRect(x:b[0],y:b[1],width:b[2],height:b[3]),text)
        }.sorted {a,b in a.priority==b.priority ? a.index<b.index:a.priority<b.priority}
        var output=lines
        for (position,entry) in eligible.enumerated() {
            var result=lines[entry.index]
            if position>=4 {
                result["reconsideration"]=["status":"budget_exceeded","band_bbox":result["bbox"]!,"contexts":[]]
            }else{
                let matches=observations.filter{ob in let r=ob.boundingBox;return CGRect(x:r.minX,y:1-r.maxY,width:r.width,height:r.height)==entry.rect && ob.topCandidates(1).first?.string==entry.text}
                result["reconsideration"]=reconsider(image,bitmap,entry.rect,entry.text,matches.count==1 ? matches[0].topCandidates(1).first:nil,deadline)
            }
            output[entry.index]=result
        }
        return output
    }
    static func reconsider(_ image:CGImage,_ bitmap:NSBitmapImageRep,_ line:CGRect,_ primary:String,_ candidate:VNRecognizedText?=nil,_ deadline:DispatchTime=DispatchTime.now()+12.0)->[String:Any] {
        let bounds=CGRect(x:0,y:0,width:image.width,height:image.height)
        let band=CGRect(x:line.minX*bounds.width,y:line.minY*bounds.height,width:line.width*bounds.width,height:line.height*bounds.height).integral.intersection(bounds)
        func normalized(_ r:CGRect)->[CGFloat]{[r.minX/bounds.width,r.minY/bounds.height,r.width/bounds.width,r.height/bounds.height]}
        var output:[String:Any]=["status":"failed","band_bbox":[line.minX,line.minY,line.width,line.height],"contexts":[]]
        guard DispatchTime.now().uptimeNanoseconds<deadline.uptimeNanoseconds else{output["status"]="budget_exceeded";return output}
        guard supportedPixels(bitmap),let data=bitmap.bitmapData else{output["status"]="unsupported_bitmap";return output}
        guard !band.isEmpty,band.width*band.height<=262_144 else{output["status"]="budget_exceeded";return output}
        let samples=bitmap.samplesPerPixel,first=bitmap.bitmapFormat.contains(.alphaFirst),offset=first ? 1:0,gray=bitmap.colorSpace.colorSpaceModel == .gray
        func luma(_ x:Int,_ y:Int)->Int {let p=y*bitmap.bytesPerRow+x*samples+offset;return gray ? Int(data[p]):(Int(data[p])*21+Int(data[p+1])*72+Int(data[p+2])*7)/100}
        var histogram=[Int](repeating:0,count:256)
        for y in Int(band.minY)..<Int(band.maxY){for x in Int(band.minX)..<Int(band.maxX){
            let alpha=y*bitmap.bytesPerRow+x*samples+(first ? 0:samples-1)
            guard !bitmap.hasAlpha || data[alpha]==255 else{output["status"]="unsupported_background";return output}
            histogram[luma(x,y)]+=1
        }}
        let total=histogram.reduce(0,+),sum=histogram.enumerated().reduce(0){$0+$1.offset*$1.element}
        guard histogram[241...255].reduce(0,+)>total/2 else{output["status"]="unsupported_background";return output}
        var weight=0,sumBackground=0,variance = -1.0,threshold=0
        for t in 0..<255 {weight+=histogram[t];sumBackground+=t*histogram[t];if weight==0{continue};let remaining=total-weight;if remaining==0{break};let difference=Double(sumBackground)/Double(weight)-Double(sum-sumBackground)/Double(remaining),v=Double(weight)*Double(remaining)*difference*difference;if v>variance{variance=v;threshold=t}}
        threshold=min(240,threshold)
        let bandWidth=Int(band.width),bandHeight=Int(band.height),stride=bandWidth+1
        // Prefix counts bound memory to about1MiB and avoid ink x token work.
        var prefix=[UInt32](repeating:0,count:stride*bandHeight),inkCount=0
        for y in 0..<bandHeight{for x in 0..<bandWidth{
            let dark=luma(Int(band.minX)+x,Int(band.minY)+y)<=threshold ? 1:0
            prefix[y*stride+x+1]=prefix[y*stride+x]+UInt32(dark);inkCount+=dark
        }}
        guard inkCount>0,variance>0 else{output["status"]="empty_ink";return output}
        func coverage(_ boxes:[CGRect])->Double {
            var count=0
            for row in 0..<bandHeight {
                let y=band.minY+CGFloat(row)+0.5
                let intervals=boxes.compactMap{box->(Int,Int)? in
                    let b=box.insetBy(dx:-1,dy:-1)
                    guard y>=b.minY,y<b.maxY else{return nil}
                    let left=max(0,Int(ceil(b.minX-band.minX-0.5))),right=min(bandWidth,Int(ceil(b.maxX-band.minX-0.5)))
                    return right>left ? (left,right):nil
                }.sorted{$0.0<$1.0}
                var left=0,right=0
                for interval in intervals {
                    if interval.0>right {count+=Int(prefix[row*stride+right]-prefix[row*stride+left]);left=interval.0;right=interval.1}
                    else{right=max(right,interval.1)}
                }
                count+=Int(prefix[row*stride+right]-prefix[row*stride+left])
            }
            return Double(count)/Double(inkCount)
        }
        output["ink_pixels"]=inkCount;output["threshold"]=threshold
        var emptyCharacters:[[String:Any]]=[]
        var characterBudget=262_144
        if let candidate=candidate,candidate.string==primary {
            for start in primary.indices {
                let end=primary.index(after:start)
                guard let glyph=try? candidate.boundingBox(for:start..<end) else{continue}
                let b=glyph.boundingBox,raw=CGRect(x:b.minX*bounds.width,y:(1-b.maxY)*bounds.height,width:b.width*bounds.width,height:b.height*bounds.height).insetBy(dx:-1,dy:-1)
                guard [raw.minX,raw.minY,raw.width,raw.height].allSatisfy({$0.isFinite}),raw.width>2,raw.height>2,bounds.contains(raw) else{continue}
                let pixel=raw.integral,area=Int(pixel.width*pixel.height)
                guard area<=characterBudget else{continue};characterBudget-=area
                if uniformWhitePixels(bitmap,raw){emptyCharacters.append(["offset":start.utf16Offset(in:primary),"text":String(primary[start..<end]),"bbox":normalized(raw),"ink_pixels":0,"method":"uniform_white_pixels_with_1px_margin"])}
            }
        }
        output["primary_empty_characters"]=emptyCharacters
        let hangul=hangulScript.numberOfMatches(in:primary,range:NSRange(primary.startIndex...,in:primary))
        let latin=primary.unicodeScalars.filter{(65...90).contains($0.value)||(97...122).contains($0.value)}.count
        let mono=hangul>latin ? ["ko-KR"]:["en-US"]
        var contexts:[[String:Any]]=[]
        for padding in [0.25,0.75]{for scale in [1,2]{for languages in [mono,["ko-KR","en-US"]]{
            let pad=max(8,min(64,band.height*padding)),cropRect=band.insetBy(dx:-pad,dy:-pad).intersection(bounds).integral
            var context:[String:Any]=["languages":languages,"padding":padding,"scale":scale,"crop_bbox":normalized(cropRect),"status":"failed","observations":[]]
            defer{contexts.append(context)}
            guard DispatchTime.now().uptimeNanoseconds<deadline.uptimeNanoseconds else{context["status"]="budget_exceeded";continue}
            guard cropRect.width*cropRect.height*CGFloat(scale*scale)<=4_000_000 else{context["status"]="budget_exceeded";continue}
            guard let crop=image.cropping(to:cropRect),let canvas=CGContext(data:nil,width:crop.width*scale,height:crop.height*scale,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{continue}
            canvas.setFillColor(NSColor.white.cgColor);canvas.fill(CGRect(x:0,y:0,width:canvas.width,height:canvas.height));canvas.interpolationQuality = .high;canvas.draw(crop,in:CGRect(x:0,y:0,width:canvas.width,height:canvas.height))
            guard let pixels=canvas.makeImage() else{continue}
            do {
                let request=try request();request.recognitionLanguages=languages
                let cancellation=DispatchWorkItem{[weak request] in request?.cancel()}
                DispatchQueue.global(qos:.utility).asyncAfter(deadline:deadline,execute:cancellation)
                defer{cancellation.cancel()}
                try VNImageRequestHandler(cgImage:pixels,orientation:.up,options:[:]).perform([request])
                guard DispatchTime.now().uptimeNanoseconds<deadline.uptimeNanoseconds else{context["status"]="budget_exceeded";continue}
                let found=request.results ?? []
                guard found.count<=8 else{context["status"]="budget_exceeded";continue}
                if found.isEmpty{context["status"]="not_detected";continue}
                var rows:[[String:Any]]=[],edge=false,overflow=false
                for observation in found {
                    let candidates=observation.topCandidates(3)
                    guard let best=candidates.first,!best.string.isEmpty,best.string.utf16.count<=128,candidates.allSatisfy({$0.string.utf16.count<=128}) else{overflow=true;continue}
                    let b=observation.boundingBox,unclipped=CGRect(x:cropRect.minX+b.minX*cropRect.width,y:cropRect.minY+(1-b.maxY)*cropRect.height,width:b.width*cropRect.width,height:b.height*cropRect.height)
                    guard let mapped=clippedRoiRect(unclipped,bounds) else{edge=true;continue}
                    let absolute=mapped.rect;if mapped.edge{edge=true}
                    let intersection=band.intersection(absolute),area=intersection.isNull ? 0:intersection.width*intersection.height
                    if area/(band.width*band.height+absolute.width*absolute.height-area)<0.5{continue}
                    if (cropRect.minX>0 && absolute.minX-cropRect.minX<8)||(cropRect.maxX<bounds.maxX && cropRect.maxX-absolute.maxX<8)||(cropRect.minY>0 && absolute.minY-cropRect.minY<8)||(cropRect.maxY<bounds.maxY && cropRect.maxY-absolute.maxY<8){edge=true}
                    var boxes:[CGRect]=[]
                    let matches=try NSRegularExpression(pattern:"\\S+").matches(in:best.string,range:NSRange(best.string.startIndex...,in:best.string))
                    if matches.count>32{overflow=true;continue}
                    for match in matches {
                        guard let range=Range(match.range,in:best.string),let token=try? best.boundingBox(for:range) else{edge=true;continue}
                        let t=token.boundingBox,raw=CGRect(x:cropRect.minX+t.minX*cropRect.width,y:cropRect.minY+(1-t.maxY)*cropRect.height,width:t.width*cropRect.width,height:t.height*cropRect.height)
                        guard let mapped=clippedRoiRect(raw,bounds) else{edge=true;continue}
                        if mapped.edge{edge=true};boxes.append(mapped.rect)
                    }
                    rows.append(["text":best.string,"confidence":Double(best.confidence),"bbox":normalized(absolute),"token_bboxes":boxes.map{normalized($0)},"alternatives":candidates.map{["text":$0.string,"confidence":Double($0.confidence)]},"ink_coverage":coverage(boxes)])
                }
                context["observations"]=rows
                context["status"]=overflow ? "budget_exceeded":edge ? "edge_cut":found.count>1 ? "contaminated":rows.count>1 ? "ambiguous":rows.isEmpty ? "not_detected":"available"
            }catch{context["status"]=DispatchTime.now().uptimeNanoseconds>=deadline.uptimeNanoseconds ? "budget_exceeded":"failed"}
        }}}
        output["status"]="available";output["contexts"]=contexts;return output
    }
}
