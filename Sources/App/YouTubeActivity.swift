import Foundation
import Combine

struct YouTubeActivityEvent: Equatable {
    enum Kind { case subscriber, likes }
    let id: String
    let kind: Kind
    let name: String
    let total: UInt64?
}

/// Public aggregate statistics and public subscribers only. No inferred identities.
/// Session-only deduplication: toggling alerts never replays a person in this live.
@MainActor final class YouTubeActivity: ObservableObject {
    @Published private(set) var totalLikes: UInt64?
    @Published private(set) var current: YouTubeActivityEvent?
    @Published private(set) var status = "Ative os alertas em uma fonte da cena."
    private(set) var queue: [YouTubeActivityEvent] = []
    private(set) var seen = Set<String>()
    private(set) var subscribersEnabled = false
    private(set) var likesEnabled = false
    private var subscribersReady = false
    private var startedAt = Date()
    private var displayedAt: Date?
    private var generation = UUID()
    private var task: Task<Void,Never>?
    private var pollTurn = 0
    private var stoppedByQuota = false
    private var subscribersUnavailable = false
    private var likesUnavailable = false
    func configure(subscribers: Bool, likes: Bool) {
        guard subscribersEnabled != subscribers || likesEnabled != likes else{return}
        if subscribersEnabled != subscribers { subscribersReady=false }
        if likesEnabled != likes {totalLikes=nil}
        subscribersEnabled=subscribers;likesEnabled=likes
        queue.removeAll { $0.kind == .subscriber ? !subscribers : !likes }
        if let event=current, event.kind == .subscriber ? !subscribers : !likes { current=nil;displayedAt=nil }
    }
    func reset() {
        task?.cancel();task=nil;generation=UUID();current=nil;totalLikes=nil
        queue.removeAll();seen.removeAll();subscribersReady=false;displayedAt=nil;pollTurn=0;stoppedByQuota=false;subscribersUnavailable=false;likesUnavailable=false
        status="Alertas aguardando uma live do YouTube."
    }
    func ingestLikes(_ response:[String:Any]) {
        guard likesEnabled,let raw=response.array("items").first?.object("statistics")["likeCount"] as? String,let total=UInt64(raw) else{return}
        let previous=totalLikes;totalLikes=total
        if let previous,total>previous {
            let event=YouTubeActivityEvent(id:"likes-\(total)",kind:.likes,name:"",total:total)
            if let index=queue.firstIndex(where:{$0.kind == .likes}) {queue[index]=event}
            else if queue.count<200 {queue.append(event)}
        } else if let previous,total<previous {
            queue.removeAll{$0.kind == .likes}
            if current?.kind == .likes {current=nil;displayedAt=nil}
        }
    }
    func ingestSubscribers(_ items:[[String:Any]]) {
        guard subscribersEnabled else{return}
        let baseline = !subscribersReady
        // Reverse newest-first response so alerts play in chronological order.
        for item in items.reversed() {
            let person=item.object("subscriberSnippet"),id=person.string("channelId")
            guard !id.isEmpty,!seen.contains(id) else{continue}
            guard seen.count<10000 else {status="Limite de alertas de inscritos atingido nesta live.";return}
            seen.insert(id)
            guard !baseline,let date=Self.date(item.object("snippet").string("publishedAt")),date>=startedAt else{continue}
            let name=String(person.string("title","Novo inscrito").prefix(100))
            if queue.count<200 {queue.append(.init(id:id,kind:.subscriber,name:name,total:nil))}
            else {status="Fila de alertas cheia. Alguns inscritos não serão exibidos."}
        }
        subscribersReady=true
    }
    static func date(_ text:String) -> Date? {
        let parser=ISO8601DateFormatter();if let date=parser.date(from:text){return date}
        parser.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return parser.date(from:text)
    }
    func tick(now:Date=Date()) {
        guard current != nil || !queue.isEmpty else{return}
        if let displayedAt,now.timeIntervalSince(displayedAt)<5 {return}
        current=queue.isEmpty ? nil:queue.removeFirst();displayedAt=current == nil ? nil:now
    }
    private func handle(_ error:Error,subscribers:Bool) {
        guard let error=error as? YouTubeAPIError else{return}
        if ["quotaExceeded","dailyLimitExceeded","unauthorized","invalid_grant"].contains(error.reason){stoppedByQuota=true}
        else if ["forbidden","insufficientPermissions","subscriptionForbidden"].contains(error.reason){
            if subscribers{subscribersUnavailable=true}else{likesUnavailable=true}
        }
    }
    func start(broadcast:String,api:YouTubeAPI,access:@escaping @MainActor () async throws -> String,isSending:@escaping @MainActor () -> Bool) {
        reset();startedAt=Date();let session=generation
        task=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.generation==session else{return}
                guard isSending() else{self.reset();return}
                if (self.subscribersEnabled || self.likesEnabled) && !self.stoppedByQuota {
                    do {
                        let token=try await access()
                        var failure:Error?
                        if self.likesEnabled && !self.likesUnavailable {
                            do {
                                let response=try await api.call("videos",token:token,query:["part":"statistics","id":broadcast])
                                try Task.checkCancellation();guard self.generation==session else{return};self.ingestLikes(response)
                            } catch {failure=error;self.handle(error,subscribers:false)}
                        }
                        try Task.checkCancellation()
                        if self.subscribersEnabled && !self.subscribersUnavailable && !self.stoppedByQuota && self.pollTurn%2 == 0 {
                            do {
                                var entries:[[String:Any]]=[],cursor=""
                                for _ in 0..<4 {
                                    var query=["part":"snippet,subscriberSnippet","myRecentSubscribers":"true","maxResults":"50"]
                                    if !cursor.isEmpty{query["pageToken"]=cursor}
                                    let response=try await api.call("subscriptions",token:token,query:query)
                                    try Task.checkCancellation();guard self.generation==session else{return}
                                    entries += response.array("items");cursor=response.string("nextPageToken")
                                    if cursor.isEmpty{break}
                                }
                                self.ingestSubscribers(entries)
                            } catch {failure=error;self.handle(error,subscribers:true)}
                        }
                        try Task.checkCancellation()
                        if let failure {self.status="Alertas: \(failure.localizedDescription)"}
                        else if self.subscribersUnavailable {self.status="Inscritos indisponíveis pela API. O contador de likes continua ativo."}
                        else if self.likesUnavailable {self.status="Likes indisponíveis pela API. Alertas de inscritos continuam ativos."}
                        else {self.status="Likes: consulta a cada 15 s • inscritos públicos: 30 s"}
                    } catch is CancellationError {return}
                    catch {
                        guard self.generation==session,!Task.isCancelled else{return}
                        self.status="Alertas: \(error.localizedDescription)"
                        if let error=error as? YouTubeAPIError,["quotaExceeded","dailyLimitExceeded","forbidden","insufficientPermissions","unauthorized","invalid_grant"].contains(error.reason){self.stoppedByQuota=true}
                    }
                    self.pollTurn += 1
                }
                do {try await Task.sleep(for:.seconds(15))}catch{return}
            }
        }
    }
}
