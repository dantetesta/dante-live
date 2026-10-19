import Foundation

@MainActor func runYouTubeActivityTests() async throws {
    func likes(_ n:String)->[String:Any]{["items":[["statistics":["likeCount":n]]]]}
    let activity=YouTubeActivity();activity.configure(subscribers:true,likes:true,channelTotal:true)
    activity.ingestChannel(["items":[["statistics":["subscriberCount":"8500","hiddenSubscriberCount":false]]]])
    precondition(activity.totalSubscribers==8500)
    activity.ingestChannel(["items":[["statistics":["subscriberCount":"8500","hiddenSubscriberCount":true]]]])
    precondition(activity.totalSubscribers==nil)
    activity.ingestLikes(likes("10"));precondition(activity.totalLikes==10 && activity.queue.isEmpty)
    activity.ingestLikes(likes("12"));activity.ingestLikes(likes("18"));precondition(activity.queue.count==1 && activity.queue[0].total==18)
    let now=Date();activity.tick(now:now);precondition(activity.current?.total==18)
    activity.tick(now:now.addingTimeInterval(4.9));precondition(activity.current != nil)
    activity.tick(now:now.addingTimeInterval(5));precondition(activity.current==nil)
    activity.ingestLikes(likes("17"));precondition(activity.totalLikes==17 && activity.queue.isEmpty)
    activity.ingestLikes(likes("-1"));precondition(activity.totalLikes==17)
    func subscriber(_ id:String,_ title:String="Marina")->[String:Any]{["subscriberSnippet":["channelId":id,"title":title],"snippet":["publishedAt":ISO8601DateFormatter().string(from:Date().addingTimeInterval(2))]]}
    activity.ingestSubscribers([subscriber("old")]);precondition(activity.queue.isEmpty)
    activity.ingestSubscribers([subscriber("new"),subscriber("old")]);precondition(activity.queue.count==1 && activity.queue[0].name=="Marina" && activity.newPublicSubscribers==1)
    activity.tick(now:now.addingTimeInterval(10));precondition(activity.current?.id=="new")
    activity.ingestSubscribers([]);activity.ingestSubscribers([subscriber("new")]);precondition(activity.queue.isEmpty)
    activity.configure(subscribers:false,likes:false);precondition(activity.current==nil && activity.totalLikes==nil)
    activity.configure(subscribers:true,likes:true);activity.ingestSubscribers([subscriber("new")]);activity.ingestSubscribers([subscriber("new")]);precondition(activity.queue.isEmpty)
    activity.ingestLikes(likes("100"));precondition(activity.queue.isEmpty)
    activity.reset();precondition(activity.seen.isEmpty && activity.current==nil && activity.totalLikes==nil && activity.newPublicSubscribers==0)
    // Authenticated read-only endpoints. First poll is a baseline, never old alerts.
    var endpoints:[String]=[]
    let api=YouTubeAPI { request in
        let url=request.url!;endpoints.append(url.path)
        precondition(request.httpMethod=="GET" && request.value(forHTTPHeaderField:"Authorization")=="Bearer test-activity")
        let data:Data
        if url.path.hasSuffix("videos") {data=try JSONSerialization.data(withJSONObject:likes("25"))}
        else if url.path.hasSuffix("channels") {precondition(url.query!.contains("mine=true"));data=try JSONSerialization.data(withJSONObject:["items":[["statistics":["subscriberCount":"8530","hiddenSubscriberCount":false]]]])}
        else {precondition(url.query!.contains("myRecentSubscribers=true"));data=try JSONSerialization.data(withJSONObject:["items":[subscriber("initial")]])}
        return (data,HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
    activity.configure(subscribers:true,likes:true,channelTotal:true)
    activity.start(broadcast:"test-video",api:api,access:{"test-activity"},isSending:{true})
    try await Task.sleep(for:.milliseconds(100))
    precondition(endpoints.count==3 && activity.totalLikes==25 && activity.totalSubscribers==8530 && activity.queue.isEmpty)
    activity.reset()
    let previewDirectory=URL(fileURLWithPath:"build/activity-qa",isDirectory:true)
    try FileManager.default.createDirectory(at:previewDirectory,withIntermediateDirectories:true)
    for style in YouTubeActivityStyle.all {
        let bitmap=YouTubeActivityRaster.render(event:nil,total:1250,subscriberTotal:8500,newPublicSubscribers:3,
            settings:["style":style.id,"layoutWidth":300,"layoutHeight":160,"font":"Menlo","valueSize":30])!
        precondition(bitmap.pixelsWide==300 && bitmap.pixelsHigh==160 && bitmap.bitmapData![3]==0)
        try bitmap.representation(using:.png,properties:[:])!.write(to:previewDirectory.appendingPathComponent("style-\(style.id).png"))
    }
    let normal=YouTubeActivityRaster.render(event:nil,total:1250,settings:["layoutWidth":820,"layoutHeight":240])!
    let scaled=YouTubeActivityRaster.render(event:nil,total:1250,settings:["layoutWidth":820,"layoutHeight":240,"componentScale":1.5])!
    precondition(normal.pixelsWide==820 && normal.pixelsHigh==240)
    precondition(scaled.pixelsWide==1230 && scaled.pixelsHigh==360)
    try normal.representation(using:.png,properties:[:])!.write(to:previewDirectory.appendingPathComponent("default-820x240.png"))
    try scaled.representation(using:.png,properties:[:])!.write(to:previewDirectory.appendingPathComponent("scaled-150-percent.png"))
    let capped=YouTubeActivityRaster.render(event:nil,total:1250,settings:["layoutWidth":1920,"layoutHeight":1600,"componentScale":2])!
    precondition(capped.pixelsWide==2592 && capped.pixelsHigh==2160)
    print("PASS: likes, rounded channel total, public subscriber count, dedup, six editable raster styles and authenticated read-only requests")
}
