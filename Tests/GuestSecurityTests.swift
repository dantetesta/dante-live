import Foundation

@MainActor func runGuestSecurityTests(model: StudioModel,directory: URL) async throws {
    let guests=model.guests
    try await guests.startServer(resources:directory)
    defer {guests.stop()}
    let first=try guests.makeInvite(),second=try guests.makeInvite()
    precondition(first.token.count==64 && first.token != second.token)
    do {_=try guests.makeInvite();preconditionFailure("third slot accepted")} catch {}
    let base=guests.localURL!,client=UUID().uuidString
    func request(_ path:String,token:String,client:String,origin:String?=nil,extra:[String:Any]=[:]) async throws -> Int {
        var request=URLRequest(url:base.appendingPathComponent(path));request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        request.setValue(origin ?? base.absoluteString,forHTTPHeaderField:"Origin")
        request.httpBody=try JSONSerialization.data(withJSONObject:["client":client,"name":"QA"].merging(extra,uniquingKeysWith:{_,new in new}))
        let (_,response)=try await URLSession.shared.data(for:request);return (response as! HTTPURLResponse).statusCode
    }
    let wrong=try await request("join",token:String(repeating:"a",count:64),client:client);precondition(wrong==403)
    let foreign=try await request("join",token:first.token,client:client,origin:"https://example.invalid");precondition(foreign==403)
    let joined=try await request("join",token:first.token,client:client);precondition(joined==200)
    let hijack=try await request("join",token:first.token,client:UUID().uuidString);precondition(hijack==409)
    let invalid=try await request("offer",token:first.token,client:client,extra:["sdp":"not SDP"]);precondition(invalid==400)
    let staleICE=try await request("ice",token:first.token,client:client,extra:["negotiation":UUID().uuidString,"candidates":[]]);precondition(staleICE==409)
    let foreignICE=try await request("ice",token:first.token,client:client,origin:"https://example.invalid");precondition(foreignICE==403)
    let candidate:[String:Any] = ["candidate":"candidate:1 1 UDP 2122260223 192.0.2.1 12345 typ host","sdpMid":"0","sdpMLineIndex":0]
    precondition(GuestModel.validCandidate(candidate))
    for bad:[String:Any] in [["sdpMLineIndex":true],["sdpMLineIndex":0.5],["sdpMLineIndex":3],["sdpMid":"other"],["candidate":"candidate:a\r\nm=audio"],["candidate":"candidate:"+String(repeating:"a",count:1025)]] {
        precondition(!GuestModel.validCandidate(candidate.merging(bad,uniquingKeysWith:{_,new in new})))
    }
    guests.revoke(first.id)
    let revoked=try await request("status",token:first.token,client:client);precondition(revoked==403)
    let stillValid=try await request("join",token:second.token,client:UUID().uuidString);precondition(stillValid==200)
    guests.turnJSON="[{\"urls\":[\"https://invalid\"],\"username\":\"x\",\"credential\":\"x\"}]"
    do {_=try guests.iceServers();preconditionFailure("invalid TURN accepted")}catch{}
    guests.turnJSON="";let ice=try guests.iceServers();precondition(ice.count==1)
    print("PASS: guest token entropy/uniqueness, two-slot bound, invalid token/origin/client rejection, malformed SDP, revocation isolation, TURN validation; loopback only")
}
