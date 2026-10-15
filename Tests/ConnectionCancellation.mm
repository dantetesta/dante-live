#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <atomic>
#include <thread>
#include <chrono>
#include <stdio.h>
static void pump(double duration){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:duration];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static bool streaming(dante_engine_t *engine){NSData *data=[[NSString stringWithUTF8String:dante_engine_state(engine)] dataUsingEncoding:NSUTF8StringEncoding];return [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil][@"streaming"] boolValue];}
int main(int argc,char **argv){@autoreleasepool{
 if(argc!=3)return 2;[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 NSString *config=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"DanteCancel-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 auto *engine=dante_engine_create_with_config(argv[1],320,180,10,config.UTF8String);if(!engine)return 3;
 int listener=socket(AF_INET,SOCK_STREAM,0);sockaddr_in address={};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=0;
 if(bind(listener,(sockaddr*)&address,sizeof(address)) || listen(listener,1))return 4;
 socklen_t length=sizeof(address);getsockname(listener,(sockaddr*)&address,&length);int port=ntohs(address.sin_port);
 std::atomic<int> client{-1};std::atomic<bool> closeConnection{false};
 std::thread server([&]{int accepted=accept(listener,nullptr,nullptr);client=accepted;while(accepted>=0&&!closeConnection)std::this_thread::sleep_for(std::chrono::milliseconds(5));if(accepted>=0){shutdown(accepted,SHUT_RDWR);close(accepted);}});
 NSString *args=[NSString stringWithFormat:@"{\"server\":\"rtmp://127.0.0.1:%d/live\",\"key\":\"blackhole\",\"bitrate\":500}",port];
 bool started=dante_engine_command(engine,"stream.start",args.UTF8String);
 for(int i=0;i<200&&client<0;i++)pump(.01);
 bool connected=client>=0;auto before=std::chrono::steady_clock::now();bool stopAccepted=dante_engine_command(engine,"stream.stop","{}");
 double cancelMS=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-before).count();
 pump(.2);bool busyWhileBlocked=streaming(engine);closeConnection=true;shutdown(listener,SHUT_RDWR);server.join();close(listener);
 for(int i=0;i<500&&streaming(engine);i++)pump(.01);bool idleAfterSocketClose=!streaming(engine);
 int repeatedPassed=0;
 for(int repeat=0;repeat<10;repeat++){
  bool began=dante_engine_command(engine,"stream.start","{\"server\":\"rtmp://127.0.0.1:19351/live\",\"key\":\"test\",\"bitrate\":500}");
  bool stopped=dante_engine_command(engine,"stream.stop","{}");for(int i=0;i<300&&streaming(engine);i++)pump(.01);
  if(began&&stopped&&!streaming(engine))repeatedPassed++;
 }
 bool passed=started&&connected&&stopAccepted&&cancelMS<100&&busyWhileBlocked&&idleAfterSocketClose&&repeatedPassed==10;
 dante_engine_destroy(engine);[[NSFileManager defaultManager] removeItemAtPath:config error:nil];
 NSDictionary *report=@{@"passed":@(passed),@"startAccepted":@(started),@"loopbackSocketAccepted":@(connected),@"cancelAccepted":@(stopAccepted),@"cancelReturnMilliseconds":@(cancelMS),@"busyWhileHandshakeBlocked":@(busyWhileBlocked),@"idleAfterSocketClosed":@(idleAfterSocketClose),@"repeatedRefusedConnectionCancellations":@(repeatedPassed),@"noDeviceCapture":@YES,@"target":@"loopback only; server never answers RTMP handshake"};
 NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];[data writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
 fprintf(stdout,"%s cancellation returned %.3f ms, pending=%d, drained=%d, repeated=%d/10\n",passed?"PASS":"FAIL",cancelMS,busyWhileBlocked,idleAfterSocketClose,repeatedPassed);return passed?0:1;
}}
