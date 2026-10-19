import Foundation
import AppKit
import Vision

extension DocverVision {
    // A bounded second observation. Primary strings/confidences are never edited.
    static let reconsiderationPolicy="vision-roi-v1; 4 weak nonnumeric lines/page; 8 contexts; 4M pixels/crop; no language correction"
    static func reconsideredLines(_ image:CGImage,_ bitmap:NSBitmapImageRep,_ lines:[[String:Any]])->[[String:Any]] {
        var budget=4
        return lines.map { line in
            guard let text=line["text"] as? String,!text.isEmpty,text.count<=128,
                  text.range(of:"\\p{N}",options:.regularExpression)==nil,
                  line["numeric_consensus"] as? Bool == true,
                  line["strike_candidate"] as? Bool == false,
                  ["not_detected"].contains(line["strike_status"] as? String ?? ""),
                  let confidence=line["confidence"] as? Double,let b=line["bbox"] as? [CGFloat],b.count==4 else{return line}
            let alternatives=line["alternatives"] as? [[String:Any]] ?? []
            let ambiguous=alternatives.contains{candidate in
                guard let value=candidate["text"] as? String,let score=candidate["confidence"] as? Double else{return false}
                return value != text && score>=confidence-0.15
            }
            guard confidence<0.5 || ambiguous else{return line}
            var result=line
            if budget==0 {result["reconsideration"]=["status":"budget_exceeded","band_bbox":b,"contexts":[]];return result}
            budget-=1
            result["reconsideration"]=reconsider(image,bitmap,CGRect(x:b[0],y:b[1],width:b[2],height:b[3]),text)
            return result
        }
    }
    static func reconsider(_ image:CGImage,_ bitmap:NSBitmapImageRep,_ line:CGRect,_ primary:String)->[String:Any] {
        let bounds=CGRect(x:0,y:0,width:image.width,height:image.height)
        let band=CGRect(x:line.minX*bounds.width,y:line.minY*bounds.height,width:line.width*bounds.width,height:line.height*bounds.height).integral.intersection(bounds)
        func normalized(_ r:CGRect)->[CGFloat]{[r.minX/bounds.width,r.minY/bounds.height,r.width/bounds.width,r.height/bounds.height]}
        var output:[String:Any]=["status":"failed","band_bbox":[line.minX,line.minY,line.width,line.height],"contexts":[]]
        guard supportedPixels(bitmap),let data=bitmap.bitmapData else{output["status"]="unsupported_bitmap";return output}
        guard !band.isEmpty,band.width*band.height<=4_000_000 else{output["status"]="budget_exceeded";return output}
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
        var ink:[CGPoint]=[]
        for y in Int(band.minY)..<Int(band.maxY){for x in Int(band.minX)..<Int(band.maxX){if luma(x,y)<=threshold{ink.append(CGPoint(x:Double(x)+0.5,y:Double(y)+0.5))}}}
        guard !ink.isEmpty,variance>0 else{output["status"]="empty_ink";return output}
        output["ink_pixels"]=ink.count;output["threshold"]=threshold
        let hangul=primary.unicodeScalars.filter{(0xAC00...0xD7A3).contains($0.value)||(0x1100...0x11FF).contains($0.value)}.count
        let latin=primary.unicodeScalars.filter{(65...90).contains($0.value)||(97...122).contains($0.value)}.count
        let mono=hangul>latin ? ["ko-KR"]:["en-US"]
        var contexts:[[String:Any]]=[]
        for padding in [0.25,0.75]{for scale in [1,2]{for languages in [mono,["ko-KR","en-US"]]{
            let pad=max(8,min(64,band.height*padding)),cropRect=band.insetBy(dx:-pad,dy:-pad).intersection(bounds).integral
            var context:[String:Any]=["languages":languages,"padding":padding,"scale":scale,"crop_bbox":normalized(cropRect),"status":"failed","observations":[]]
            defer{contexts.append(context)}
            guard cropRect.width*cropRect.height*CGFloat(scale*scale)<=4_000_000 else{context["status"]="budget_exceeded";continue}
            guard let crop=image.cropping(to:cropRect),let canvas=CGContext(data:nil,width:crop.width*scale,height:crop.height*scale,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{continue}
            canvas.setFillColor(NSColor.white.cgColor);canvas.fill(CGRect(x:0,y:0,width:canvas.width,height:canvas.height));canvas.interpolationQuality = .high;canvas.draw(crop,in:CGRect(x:0,y:0,width:canvas.width,height:canvas.height))
            guard let pixels=canvas.makeImage() else{continue}
            do {
                let request=try request();request.recognitionLanguages=languages
                try VNImageRequestHandler(cgImage:pixels,orientation:.up,options:[:]).perform([request])
                let found=request.results ?? []
                guard found.count<=8 else{context["status"]="budget_exceeded";continue}
                if found.isEmpty{context["status"]="not_detected";continue}
                var rows:[[String:Any]]=[],edge=false,overflow=false
                for observation in found {
                    let candidates=observation.topCandidates(3)
                    guard let best=candidates.first,!best.string.isEmpty,best.string.count<=128,candidates.allSatisfy({$0.string.count<=128}) else{overflow=true;continue}
                    let b=observation.boundingBox,absolute=CGRect(x:cropRect.minX+b.minX*cropRect.width,y:cropRect.minY+(1-b.maxY)*cropRect.height,width:b.width*cropRect.width,height:b.height*cropRect.height)
                    let intersection=band.intersection(absolute),area=intersection.isNull ? 0:intersection.width*intersection.height
                    if area/(band.width*band.height+absolute.width*absolute.height-area)<0.5{continue}
                    if (cropRect.minX>0 && absolute.minX-cropRect.minX<8)||(cropRect.maxX<bounds.maxX && cropRect.maxX-absolute.maxX<8)||(cropRect.minY>0 && absolute.minY-cropRect.minY<8)||(cropRect.maxY<bounds.maxY && cropRect.maxY-absolute.maxY<8){edge=true}
                    var boxes:[CGRect]=[]
                    let matches=try NSRegularExpression(pattern:"\\S+").matches(in:best.string,range:NSRange(best.string.startIndex...,in:best.string))
                    if matches.count>32{overflow=true;continue}
                    for match in matches {guard let range=Range(match.range,in:best.string),let token=try? best.boundingBox(for:range) else{continue};let t=token.boundingBox;boxes.append(CGRect(x:cropRect.minX+t.minX*cropRect.width,y:cropRect.minY+(1-t.maxY)*cropRect.height,width:t.width*cropRect.width,height:t.height*cropRect.height))}
                    let covered=ink.filter{point in boxes.contains{$0.insetBy(dx:-1,dy:-1).contains(point)}}.count
                    rows.append(["text":best.string,"confidence":Double(best.confidence),"bbox":normalized(absolute),"token_bboxes":boxes.map{normalized($0)},"alternatives":candidates.map{["text":$0.string,"confidence":Double($0.confidence)]},"ink_coverage":Double(covered)/Double(ink.count)])
                }
                context["observations"]=rows
                context["status"]=overflow ? "budget_exceeded":edge ? "edge_cut":found.count>1 ? "contaminated":rows.count>1 ? "ambiguous":rows.isEmpty ? "not_detected":"available"
            }catch{context["status"]="failed"}
        }}}
        output["status"]="available";output["contexts"]=contexts;return output
    }
}
