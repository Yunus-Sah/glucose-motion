import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
import CoreTransferable
import UniformTypeIdentifiers
#endif

private let comparisonA = Color(red:0.02,green:0.34,blue:0.78)
private let comparisonB = Color(red:0.58,green:0.22,blue:0.72)
private struct ComparisonPoint: Identifiable {
    var id: Date { reading.time }
    let reading: Reading
    let minute: Double
    let segment: Int
}
struct ComparisonReport: View {
    static let canvasHeight: CGFloat = 780
    let data: ComparisonData
    private func points(_ s: ComparedSession) -> [ComparisonPoint] {
        var segment = 0
        let p = s.chartReadings.filter { data.domain.contains($0.time.timeIntervalSince(s.session.start)/60) }
        return p.enumerated().map { i,r in
            if i > 0 && r.time.timeIntervalSince(p[i-1].time) > 600 { segment += 1 }
            return ComparisonPoint(reading:r,minute:r.time.timeIntervalSince(s.session.start)/60,segment:segment)
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            VStack(alignment:.leading,spacing:4) {
                Text("GLUCOSE MOTION · SESSION COMPARISON").font(.system(size:9,weight:.bold)).tracking(1).foregroundStyle(.secondary)
                Text(data.title).font(.system(size:20,weight:.bold)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                Text(data.subtitle).font(.system(size:11)).foregroundStyle(.secondary)
            }
            HStack(alignment:.top,spacing:16) { identity(data.a,letter:"A",color:comparisonA); identity(data.b,letter:"B",color:comparisonB) }
            Divider()
            HStack(spacing:16) { legend("A · \(data.a.day)",color:comparisonA); legend("B · \(data.b.day)",color:comparisonB); Spacer(); Text("mmol/L").font(.system(size:10)).foregroundStyle(.secondary) }
            Chart {
                RectangleMark(xStart:.value("Both started",0),xEnd:.value("Both active",min(data.a.durationMinutes,data.b.durationMinutes))).foregroundStyle(.teal.opacity(0.10))
                ForEach(points(data.a)) { p in LineMark(x:.value("Minutes",p.minute),y:.value("Glucose",p.reading.value),series:.value("Series","A-\(p.segment)")).foregroundStyle(comparisonA).lineStyle(StrokeStyle(lineWidth:2.4)) }
                ForEach(points(data.b)) { p in LineMark(x:.value("Minutes",p.minute),y:.value("Glucose",p.reading.value),series:.value("Series","B-\(p.segment)")).foregroundStyle(comparisonB).lineStyle(StrokeStyle(lineWidth:2.4)) }
                if let meal = data.a.mealOffset { RuleMark(x:.value("A meal",meal)).foregroundStyle(.orange).lineStyle(StrokeStyle(dash:[3,3])).annotation(position:.top) { Text("A meal").font(.system(size:9,weight:.semibold)).foregroundStyle(.orange) } }
                if let meal = data.b.mealOffset { RuleMark(x:.value("B meal",meal)).foregroundStyle(.orange).lineStyle(StrokeStyle(dash:[3,3])).annotation(position:.top) { Text("B meal").font(.system(size:9,weight:.semibold)).foregroundStyle(.orange) } }
                RuleMark(x:.value("Workout start",0)).foregroundStyle(.teal).lineStyle(StrokeStyle(dash:[4,3])).annotation(position:.top) { Text("Start").font(.system(size:9,weight:.semibold)).foregroundStyle(.teal) }
            }.chartXScale(domain:data.domain).chartYScale(domain:data.yDomain)
                .chartXAxis { AxisMarks(values:.stride(by:30)) { value in AxisGridLine(); AxisValueLabel { if let minute = value.as(Double.self) { Text("\(Int(minute))").font(.system(size:9)) } } } }
                .chartYAxis { AxisMarks(position:.leading,values:.automatic(desiredCount:4)) { AxisGridLine(); AxisValueLabel().font(.system(size:9)) } }
                .frame(height:145).padding(.top,10)
            Text("Minutes relative to workout start (0)").font(.system(size:10)).foregroundStyle(.secondary).frame(maxWidth:.infinity)
            HStack(alignment:.top,spacing:14) { legend(data.a.finishedMeal && data.b.finishedMeal ? "Orange: meal finished" : "Orange: recorded meal time",color:.orange); legend("Teal band: both exercising",color:.teal) }
            Divider()
            Text("DURING EXERCISE · mmol/L").font(.system(size:9,weight:.bold)).tracking(0.6).foregroundStyle(.secondary)
            if let x = data.a.session.stats,let y = data.b.session.stats {
                VStack(spacing:5) {
                    metric("",left:"A · \(data.a.day)",right:"B · \(data.b.day)",bold:true)
                    metric("Start",left:ComparedSession.value(x[0]),right:ComparedSession.value(y[0]))
                    metric("End",left:ComparedSession.value(x[1]),right:ComparedSession.value(y[1]))
                    metric("Change",left:ComparedSession.signed(x[4]),right:ComparedSession.signed(y[4]),bold:true)
                    metric("Min–max",left:"\(ComparedSession.value(x[2]))–\(ComparedSession.value(x[3]))",right:"\(ComparedSession.value(y[2]))–\(ComparedSession.value(y[3]))")
                    metric("Average",left:ComparedSession.value(x[5]),right:ComparedSession.value(y[5]))
                }
                Text("A: \(data.a.session.window.count) readings · B: \(data.b.session.window.count) readings").font(.system(size:9)).foregroundStyle(.secondary)
            }
            Divider()
            Text("ATHLETE FEEDBACK").font(.system(size:10,weight:.bold)).tracking(0.6)
            feedback("During training",data.duringFeedback)
            feedback("After training",data.afterFeedback)
            feedback("What this means",data.interpretationFeedback)
            Spacer(minLength:0)
        }.padding(18).frame(width:390,height:Self.canvasHeight,alignment:.topLeading).background(Color.white).foregroundStyle(Color.black).environment(\.colorScheme,.light).environment(\.locale,Locale(identifier:"en_GB")).dynamicTypeSize(.medium)
    }
    private func feedback(_ title:String,_ body:String) -> some View {
        VStack(alignment:.leading,spacing:2) { Text(title).font(.system(size:11,weight:.semibold)); Text(body).font(.system(size:10.5)).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true) }
    }
    private func identity(_ item: ComparedSession,letter:String,color:Color) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(letter) · \(item.dateLabel)\(item.session.demo ? " · DEMO" : "")").font(.system(size:13,weight:.bold)).foregroundStyle(color)
            Text(item.delayExplanation).font(.system(size:11,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
            Text(item.mealName).font(.system(size:11)).lineLimit(2)
            Text("Meal \(item.mealClock)").font(.system(size:10)).foregroundStyle(.secondary)
            Text("Workout \(item.trainingClock)").font(.system(size:10)).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func legend(_ text:String,color:Color) -> some View { HStack(spacing:5) { Circle().fill(color).frame(width:7,height:7); Text(text).font(.system(size:9)).fixedSize(horizontal:false,vertical:true) } }
    private func metric(_ label:String,left:String,right:String,bold:Bool=false) -> some View {
        HStack { Text(label).foregroundStyle(.secondary).frame(width:75,alignment:.leading); Text(left).foregroundStyle(comparisonA).frame(maxWidth:.infinity,alignment:.trailing); Text(right).foregroundStyle(comparisonB).frame(maxWidth:.infinity,alignment:.trailing) }.font(.system(size:11,weight:bold ? .semibold:.regular)).monospacedDigit()
    }
}
#if os(iOS)
struct ComparisonPNG: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation { DataRepresentation(exportedContentType:.png) { $0.data }.suggestedFileName("GlucoseMotion-comparison.png") }
}
@MainActor func comparisonImage(_ data: ComparisonData) -> UIImage? {
    let r = ImageRenderer(content:ComparisonReport(data:data)); r.scale = 3
    return r.uiImage
}
struct ComparisonPosterView: View {
    let data: ComparisonData
    @Environment(\.dismiss) var dismiss
    @ViewState<UIImage?> private var image = nil
    var body: some View {
        VStack(spacing:8) {
            HStack { Button("Done") { dismiss() }; Spacer(); Text("Poster view").font(.subheadline.bold()); Spacer(); if let image,let png = image.pngData() { ShareLink(item:ComparisonPNG(data:png),preview:SharePreview("Glucose comparison",image:Image(uiImage:image))) { Image(systemName:"square.and.arrow.up") }.accessibilityLabel("Export complete comparison image") } }.padding(.horizontal,20).frame(height:40)
            if let image { Image(uiImage:image).resizable().scaledToFit().padding(.horizontal,8).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
        }.background(Color.white).foregroundStyle(Color.black).preferredColorScheme(.light).task { image = comparisonImage(data) }
    }
}
#endif
