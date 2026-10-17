import Foundation

@MainActor func runYouTubeActivityTests() async throws {
    func likes(_ n:String)->[String:Any]{["items":[["statistics":["likeCount":n]]]]}
    let activity=YouTubeActivity();activity.configure(subscribers:true,likes:true)
    activity.ingestLikes(likes("10"));precondition(activity.totalLikes==10 && activity.queue.isEmpty)
    activity.ingestLikes(likes("12"));activity.ingestLikes(likes("18"));precondition(activity.queue.count==1 && activity.queue[0].total==18)
    let now=Date();activity.tick(now:now);precondition(activity.current?.total==18)
    activity.tick(now:now.addingTimeInterval(4.9));precondition(activity.current != nil)
    activity.tick(now:now.addingTimeInterval(5));precondition(activity.current==nil)
    activity.ingestLikes(likes("17"));precondition(activity.totalLikes==17 && activity.queue.isEmpty)
    activity.ingestLikes(likes("-1"));precondition(activity.totalLikes==17)
    func subscriber(_ id:String,_ title:String="Marina")->[String:Any]{["subscriberSnippet":["channelId":id,"title":title],"snippet":["publishedAt":ISO8601DateFormatter().string(from:Date().addingTimeInterval(2))]]}
    activity.ingestSubscribers([subscriber("old")]);precondition(activity.queue.isEmpty)
    activity.ingestSubscribers([subscriber("new"),subscriber("old")]);precondition(activity.queue.count==1 && activity.queue[0].name=="Marina")
    activity.tick(now:now.addingTimeInterval(10));precondition(activity.current?.id=="new")
    activity.ingestSubscribers([]);activity.ingestSubscribers([subscriber("new")]);precondition(activity.queue.isEmpty)
    activity.configure(subscribers:false,likes:false);precondition(activity.current==nil && activity.totalLikes==nil)
    activity.configure(subscribers:true,likes:true);activity.ingestSubscribers([subscriber("new")]);activity.ingestSubscribers([subscriber("new")]);precondition(activity.queue.isEmpty)
    activity.ingestLikes(likes("100"));precondition(activity.queue.isEmpty)
    activity.reset();precondition(activity.seen.isEmpty && activity.current==nil && activity.totalLikes==nil)
    // Authenticated read-only endpoints. First poll is a baseline, never old alerts.
    var endpoints:[String]=[]
    let api=YouTubeAPI { request in
        let url=request.url!;endpoints.append(url.path)
        precondition(request.httpMethod=="GET" && request.value(forHTTPHeaderField:"Authorization")=="Bearer test-activity")
        let data:Data
        if url.path.hasSuffix("videos") {data=try JSONSerialization.data(withJSONObject:likes("25"))}
        else {precondition(url.query!.contains("myRecentSubscribers=true"));data=try JSONSerialization.data(withJSONObject:["items":[subscriber("initial")]])}
        return (data,HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
    activity.start(broadcast:"test-video",api:api,access:{"test-activity"},isSending:{true})
    try await Task.sleep(for:.milliseconds(100))
    precondition(endpoints.count==2 && activity.totalLikes==25 && activity.queue.isEmpty)
    activity.reset()
    print("PASS: aggregate likes baseline/coalescing/decrease, public-subscriber baseline/dedup/toggle, five-second queue, reset and authenticated read-only requests")
}
