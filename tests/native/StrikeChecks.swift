import Foundation
import AppKit

@main struct StrikeChecks {
    static func main() throws {
        let image=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:240,bitsPerSample:8,samplesPerPixel:1,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceWhite,bytesPerRow:0,bitsPerPixel:0)!
        let pixels=image.bitmapData!,stride=image.bytesPerRow
        func clear(){for y in 0..<240{for x in 0..<400{pixels[y*stride+x]=255}}}
        func rect(_ x:Int,_ y:Int,_ width:Int,_ height:Int){for row in y..<(y+height){for col in x..<(x+width){pixels[row*stride+col]=0}}}
        func box(_ x:Double,_ y:Double,_ width:Double,_ height:Double)->CGRect{CGRect(x:x/400,y:y/240,width:width/400,height:height/240)}
        // The lower closed bowl deliberately has a long intrinsic crossbar.
        func six(_ x:Int,_ y:Int){rect(x,y,4,36);rect(x,y,25,4);rect(x,y+16,25,3);rect(x,y+32,25,4);rect(x+21,y+16,4,20)}
        var checks=0
        func expect(_ line:CGRect,_ status:String,_ message:String){let result=DocverVision.strikeObservation(image,line);precondition(result.status==status,"\(message): \(result.status)");precondition((result.bbox != nil)==(status=="detected"),"Only detected strikes publish a bbox");checks+=1}
        clear();six(80,70)
        expect(box(78,68,29,40),"ambiguous_glyph_stroke","A single digit crossbar is not deletion evidence")
        clear();six(80,70);rect(74,86,37,2)
        expect(box(72,68,41,40),"detected","A black strike visibly extending beyond one digit remains eligible")
        expect(box(79,68,27,40),"detected","A tight OCR box must not hide a single digit's connected strike overhang")
        clear();for x in [50,90,130,170]{six(x,70)};rect(48,86,150,2)
        expect(box(46,68,154,40),"detected","A numeric strike crossing inter-glyph gaps remains eligible")
        clear();for x in [50,90,130,170]{six(x,70)};rect(48,112,150,2)
        expect(box(46,68,154,40),"not_detected","An underline must not become a strike")
        clear();rect(50,86,150,1)
        expect(box(48,68,154,40),"ambiguous_glyph_stroke","A bare horizontal rule has no text ink")
        clear();rect(50,86,150,1);rect(50,68,1,40);rect(199,68,1,40)
        expect(box(48,68,154,40),"ambiguous_glyph_stroke","Table rules alone cannot supply glyph evidence")
        // Stacked rectangular loops model the projected ink of rotated digits;
        // their shared left/right extent must not turn a loop edge into a strike.
        clear();for y in [50,74,98,122]{rect(80,y,26,3);rect(80,y+17,26,3);rect(80,y,3,20);rect(103,y,3,20)}
        expect(box(78,48,30,96),"ambiguous_glyph_stroke","Rotated glyph crossbars stay unresolved without an independent stroke")
        clear();six(80,70)
        expect(box(78,68,20,40),"too_small","Existing minimum raster bounds stay conservative")
        // A colored strike is not excluded by a dark-ink-only assumption.
        let rgb=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:240,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let data=rgb.bitmapData!
        clear();for x in [50,90,130,170]{six(x,70)}
        for y in 0..<240{for x in 0..<400{let p=y*rgb.bytesPerRow+x*3;for c in 0..<3{data[p+c]=pixels[y*stride+x]}}}
        for y in 86...87{for x in 48..<198{let p=y*rgb.bytesPerRow+x*3;data[p]=255;data[p+1]=0;data[p+2]=0}}
        precondition(DocverVision.strikeObservation(rgb,box(46,68,154,40)).status=="detected","Colored numeric strikes remain detectable");checks+=1
        print("PASS \(checks) native strike ink separation controls")
    }
}
