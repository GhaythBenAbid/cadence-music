import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Core Graphics renders reliably without an AppKit window or display context.
let ink: [CGFloat] = [22/255,33/255,29/255,1]
let lime: [CGFloat] = [215/255,245/255,103/255,1]
func color(_ components:[CGFloat])->CGColor { CGColor(colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!,components:components)! }
func mark(_ context:CGContext, size:CGFloat, tint:[CGFloat]) {
    context.saveGState();context.scaleBy(x:size/1024,y:size/1024)
    context.setStrokeColor(color(tint));context.setFillColor(color(tint));context.setLineCap(.round)
    context.setLineWidth(76)
    context.addArc(center:CGPoint(x:512,y:512),radius:290,startAngle:CGFloat.pi*0.23,endAngle:CGFloat.pi*1.77,clockwise:false);context.strokePath()
    for (x,height): (CGFloat,CGFloat) in [(444,144),(526,280),(608,200)] {
        context.addPath(CGPath(roundedRect:CGRect(x:x-20,y:512-height/2,width:40,height:height),cornerWidth:20,cornerHeight:20,transform:nil));context.fillPath()
    }
    context.restoreGState()
}
let assets=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Assets.xcassets")
let brand=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Brand")
try FileManager.default.createDirectory(at:brand,withIntermediateDirectories:true)
func png(_ url:URL,size:Int,background:[CGFloat]?,tint:[CGFloat],inset:CGFloat=0,rounded:Bool=false) throws {
    let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:(background == nil || rounded ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    if let background {
        ctx.setFillColor(color(background))
        if rounded {let edge=CGFloat(size);ctx.addPath(CGPath(roundedRect:CGRect(x:edge*0.08,y:edge*0.08,width:edge*0.84,height:edge*0.84),cornerWidth:edge*0.19,cornerHeight:edge*0.19,transform:nil));ctx.fillPath()}
        else{ctx.fill(CGRect(x:0,y:0,width:size,height:size))}
    }
    ctx.translateBy(x:inset,y:inset);mark(ctx,size:CGFloat(size)-inset*2,tint:tint)
    let out=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(out,ctx.makeImage()!,nil)
    guard CGImageDestinationFinalize(out) else {throw NSError(domain:"CadenceBrand",code:1)}
}
func pdf(_ url:URL,tint:[CGFloat]) throws {
    var box=CGRect(x:0,y:0,width:1024,height:1024)
    let ctx=CGContext(url as CFURL,mediaBox:&box,nil)!
    ctx.beginPDFPage(nil);mark(ctx,size:1024,tint:tint);ctx.endPDFPage();ctx.closePDF()
}
let arc="M 729.5 320.2 A 290 290 0 1 0 729.5 703.8"
func svg(tint:String)->String {"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" fill="none">
  <title>Cadence — C and sound waves</title>
  <path d="\(arc)" stroke="\(tint)" stroke-width="76" stroke-linecap="round"/>
  <g fill="\(tint)"><rect x="424" y="440" width="40" height="144" rx="20"/><rect x="506" y="372" width="40" height="280" rx="20"/><rect x="588" y="412" width="40" height="200" rx="20"/></g>
</svg>
"""}
for (name,tint,hex) in [("Ink",ink,"#16211D"),("Lime",lime,"#D7F567")] {
    let folder=assets.appendingPathComponent("CadenceMark\(name).imageset");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try pdf(folder.appendingPathComponent("mark.pdf"),tint:tint)
    let contents="""
    {"images":[{"filename":"mark.pdf","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"preserves-vector-representation":true}}
    """
    try contents.write(to:folder.appendingPathComponent("Contents.json"),atomically:true,encoding:.utf8)
    try svg(tint:hex).write(to:brand.appendingPathComponent("cadence-mark-\(name.lowercased()).svg"),atomically:true,encoding:.utf8)
    try png(brand.appendingPathComponent("cadence-mark-\(name.lowercased()).png"),size:1024,background:nil,tint:tint)
}
try png(assets.appendingPathComponent("AppIcon.appiconset/icon-1024.png"),size:1024,background:ink,tint:lime,inset:30)
try Data(contentsOf:assets.appendingPathComponent("AppIcon.appiconset/icon-1024.png")).write(to:brand.appendingPathComponent("cadence-app-icon.png"),options:.atomic)
let launch=assets.appendingPathComponent("LaunchLogo.imageset");try FileManager.default.createDirectory(at:launch,withIntermediateDirectories:true)
for scale in 1...3 {try png(launch.appendingPathComponent("logo@\(scale)x.png"),size:144*scale,background:nil,tint:lime)}
try """
{"images":[{"filename":"logo@1x.png","idiom":"universal","scale":"1x"},{"filename":"logo@2x.png","idiom":"universal","scale":"2x"},{"filename":"logo@3x.png","idiom":"universal","scale":"3x"}],"info":{"author":"xcode","version":1}}
""".write(to:launch.appendingPathComponent("Contents.json"),atomically:true,encoding:.utf8)
print("Generated Cadence app icon, vector marks and launch assets")

let mac=assets.appendingPathComponent("MacAppIcon.appiconset");try FileManager.default.createDirectory(at:mac,withIntermediateDirectories:true)
var images:[[String:String]]=[]
for points in [16,32,128,256,512]{for scale in 1...2{
    let name="icon-\(points)@\(scale)x.png"
    try png(mac.appendingPathComponent(name),size:points*scale,background:ink,tint:lime,inset:CGFloat(points*scale)*0.12,rounded:true)
    images.append(["filename":name,"idiom":"mac","size":"\(points)x\(points)","scale":"\(scale)x"])
}}
try JSONSerialization.data(withJSONObject:["images":images,"info":["author":"xcode","version":1]],options:[.prettyPrinted,.sortedKeys]).write(to:mac.appendingPathComponent("Contents.json"))
