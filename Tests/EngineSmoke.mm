#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <stdio.h>
#include <string>
#include <cmath>
#include <vector>

static NSMutableArray *checks;
static int failures=0;
static id parse(const char *s) {return [NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:s] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];}
static void check(bool ok,NSString *name) {
    [checks addObject:@{@"name":name,@"passed":@(ok)}];
    fprintf(stdout,"%s %s\n",ok?"PASS":"FAIL",name.UTF8String);fflush(stdout);if(!ok)failures++;
}
static bool command(dante_engine_t *e,const char *name,id args) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    std::string json((const char*)data.bytes,data.length);bool ok=dante_engine_command(e,name,json.c_str());
    if(!ok)fprintf(stdout,"command %s: %s\n",name,dante_engine_last_error(e));return ok;
}
static void pump(double seconds) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}
static NSDictionary *state(dante_engine_t *e) {return parse(dante_engine_state(e));}
static bool configuredOutput(dante_engine_t *e,NSString *kind,int audioBitrate) {
    NSDictionary *settings=state(e)[@"outputs"][kind][@"settings"];
    if([kind isEqual:@"stream"] && ([settings[@"bframes"] boolValue] || !([settings[@"tune"] isEqual:@""] || [settings[@"tune"] isEqual:@"zerolatency"])))return false;
    return [settings[@"bitrate"] intValue]==1200 && [settings[@"audioBitrate"] intValue]==audioBitrate &&
        [settings[@"keyframeSeconds"] intValue]==2 && [settings[@"rateControl"] isEqual:@"CBR"];
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=3){fprintf(stderr,"Usage: EngineSmoke app-path evidence-directory\n");return 2;}
        [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        checks=[NSMutableArray array];NSString *directory=[NSString stringWithUTF8String:argv[2]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *configDirectory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"DanteLive-EngineSmoke-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        dante_engine_t *e=dante_engine_create_with_config(argv[1],640,360,10,configDirectory.UTF8String);
        check(e!=nullptr,@"isolated engine startup 640x360 10fps");
        if(!e){fprintf(stderr,"%s\n",dante_engine_last_error(nullptr));return 1;}
        NSDictionary *configAttributes=[[NSFileManager defaultManager] attributesOfItemAtPath:configDirectory error:nil];
        check([configAttributes[NSFileType] isEqual:NSFileTypeDirectory] && [configAttributes[NSFilePosixPermissions] unsignedIntValue]==0700,@"module configuration isolated in private temporary directory");
        id catalog=parse(dante_engine_catalog(e));
        id captureSchema=parse(dante_engine_type_properties_with_settings(e,"screen_capture","{\"type\":1}"));
        check([captureSchema[@"requiresInstance"] boolValue],@"capture properties require instance without accessing devices");
        check(!command(e,"video.configure",@{@"width":@641,@"height":@360,@"fps":@10}),@"odd video dimensions rejected");
        check(command(e,"video.configure",@{@"width":@320,@"height":@180,@"fps":@12}),@"idle video reconfiguration");
        check([state(e)[@"width"] intValue]==320 && [state(e)[@"fps"] intValue]==12,@"video configuration read-back");
        check(command(e,"video.configure",@{@"width":@640,@"height":@360,@"fps":@10}),@"restore smoke canvas");
        check(command(e,"source.add",@{@"type":@"color_source_v3",@"name":@"Synthetic color",@"settings":@{@"color":@0xFFFF8844,@"width":@640,@"height":@360}}),@"real synthetic color source creation");
        NSArray *items=state(e)[@"scenes"][0][@"items"];
        check(items.count==1,@"one source present");
        NSNumber *itemID=items.count?items[0][@"id"]:@0;
        check(command(e,"item.transform",@{@"id":itemID,@"x":@12,@"y":@24,@"scaleX":@0.8,@"scaleY":@0.8,@"rotation":@15,@"cropLeft":@4}),@"numeric transform/crop");
        pump(0.2);
        items=state(e)[@"scenes"][0][@"items"];
        check(items.count && [items[0][@"x"] intValue]==12 && [items[0][@"rotation"] intValue]==15 && [items[0][@"cropLeft"] intValue]==4,@"transform read-back");
        NSArray *corners=items.count ? items[0][@"boxCorners"] : nil;
        bool geometry=false;
        if(corners.count==4){double dx=[corners[1][0] doubleValue]-[corners[0][0] doubleValue],dy=[corners[1][1] doubleValue]-[corners[0][1] doubleValue];
            geometry=fabs([corners[0][0] doubleValue]-12)<0.01 && fabs([corners[0][1] doubleValue]-24)<0.01 &&
                fabs(hypot(dx,dy)-636*0.8)<0.05 && fabs(atan2(dy,dx)-15*M_PI/180)<0.001 && [items[0][@"boundsType"] intValue]==0;}
        check(geometry,@"engine box corners include crop scale and rotation");
        check(command(e,"item.locked",@{@"id":itemID,@"value":@YES}),@"lock source");
        check(!command(e,"item.transform",@{@"id":itemID,@"x":@50}),@"locked transform rejected");
        command(e,"item.locked",@{@"id":itemID,@"value":@NO});
        check(command(e,"item.fit",@{@"id":itemID}),@"fit source to canvas");
        check(command(e,"filter.add",@{@"name":@"Synthetic color",@"filter":@"Color correction",@"type":@"color_filter_v2",@"settings":@{@"brightness":@0.1}}),@"visual filter add");
        check(command(e,"source.add",@{@"type":@"text_ft2_source_v2",@"name":@"Synthetic title",@"settings":@{@"text":@"Dante Live — teste real",@"font":@{@"face":@"Helvetica",@"size":@36}}}),@"native text source creation");
        NSString *tonePath=[directory stringByAppendingPathComponent:@"synthetic-tone.wav"];
        uint32_t frames=48000,bytes=frames*4,rate=48000,byteRate=192000,riffSize=bytes+36,fmtSize=16;
        uint16_t pcm=1,channels=2,blockAlign=4,bits=16;
        NSMutableData *wav=[NSMutableData data];
        [wav appendBytes:"RIFF" length:4];[wav appendBytes:&riffSize length:4];[wav appendBytes:"WAVEfmt " length:8];
        [wav appendBytes:&fmtSize length:4];[wav appendBytes:&pcm length:2];[wav appendBytes:&channels length:2];
        [wav appendBytes:&rate length:4];[wav appendBytes:&byteRate length:4];[wav appendBytes:&blockAlign length:2];[wav appendBytes:&bits length:2];
        [wav appendBytes:"data" length:4];[wav appendBytes:&bytes length:4];
        std::vector<int16_t> samples(frames*2);for(uint32_t i=0;i<frames;i++)samples[i*2]=samples[i*2+1]=(int16_t)(sin(i*2*M_PI*440/48000)*10000);
        [wav appendBytes:samples.data() length:bytes];[wav writeToFile:tonePath atomically:YES];
        check(command(e,"source.add",@{@"type":@"ffmpeg_source",@"name":@"Synthetic audio",@"settings":@{@"local_file":tonePath,@"is_local_file":@YES,@"looping":@YES}}),@"local synthetic WAV media source");
        check(command(e,"audio.set",@{@"name":@"Synthetic audio",@"volume":@0.5,@"monitoring":@0,@"muted":@NO}),@"mixer gain and no-monitoring configuration");
        check(!command(e,"source.add",@{@"type":@"color_source_v3",@"name":@"Synthetic color"}),@"duplicate source name rejected");
        size_t count=[state(e)[@"scenes"][0][@"items"] count];
        check(!command(e,"source.add",@{@"type":@"dante_missing_source",@"name":@"Unavailable"}),@"unknown source type rejected");
        check([state(e)[@"scenes"][0][@"items"] count]==count,@"failed add creates no scene item");
        check(command(e,"scene.duplicate",@{@"name":@"Scene B"}),@"scene duplication");
        check(command(e,"scene.select",@{@"scene":@"Scene B",@"studio":@YES}),@"studio preview selection");
        check([state(e)[@"programScene"] isEqual:@"Cena 1"],@"studio selection preserves program");
        check(command(e,"scene.take",@{@"duration":@150,@"transition":@"fade"}),@"fade transition start");pump(0.5);
        check([state(e)[@"programScene"] isEqual:@"Scene B"],@"program read-back after transition");
        std::string saved=dante_engine_save(e);
        check(!dante_engine_command(e,"item.transform","{\"x\":null}"),@"invalid numeric argument rejected");
        check(!command(e,"audio.set",@{@"name":@"Synthetic color",@"syncMS":@9e15}),@"audio sync overflow rejected");
        NSMutableDictionary *invalid=[parse(saved.c_str()) mutableCopy];invalid[@"width"]=@641;
        std::string invalidJSON([[NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil] length], '\0');
        NSData *invalidData=[NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil];invalidJSON.assign((const char*)invalidData.bytes,invalidData.length);
        check(!dante_engine_load(e,invalidJSON.c_str()),@"invalid project dimensions rejected before replacement");
        check(saved==std::string(dante_engine_save(e)),@"failed import preserves entire project");
        check(command(e,"scene.create",@{@"name":@"Disposable"}),@"scene creation");
        check(dante_engine_load(e,saved.c_str()),@"project roundtrip load");
        check([state(e)[@"scenes"] count]==2,@"project restores exact scene count");
        check([state(e)[@"selectedScene"] isEqual:@"Scene B"],@"project restores selection");
        NSString *filename=[NSString stringWithFormat:@"smoke-%@.mkv",NSUUID.UUID.UUIDString];
        NSString *recording=[directory stringByAppendingPathComponent:filename];
        check(!command(e,"recording.start",@{@"path":recording,@"audioBitrate":@129}),@"unsupported AAC bitrate rejected");
        check(!command(e,"recording.start",@{@"path":recording,@"audioBitrate":@160.5}),@"fractional AAC bitrate rejected");
        check(!command(e,"recording.start",@{@"path":recording,@"audioBitrate":@"128"}),@"nonnumeric AAC bitrate rejected");
        bool started=command(e,"recording.start",@{@"path":recording,@"bitrate":@1200});check(started,@"real MKV recording start");
        if(started)check(configuredOutput(e,@"recording",160),@"recording encoder readback CBR1200 keyframe2 AAC160 default");
        NSDictionary *during=@{};
        bool localRTMP=getenv("DANTE_TEST_RTMP")!=nullptr;
        if(started){
            if(localRTMP){check(command(e,"stream.start",@{@"server":@"rtmp://127.0.0.1:19350/live",@"key":@"test",@"bitrate":@1200}),@"local RTMP connection start");
                check(configuredOutput(e,@"stream",128),@"stream encoder readback CBR1200 keyframe2 AAC128 default");
                check(!command(e,"stream.start",@{@"server":@"rtmp://127.0.0.1:19350/live",@"key":@"test"}),@"duplicate RTMP start blocked while connecting");}
            pump(2);
            bool meterAudible=false;for(NSDictionary *sc in state(e)[@"scenes"])for(NSDictionary *item in sc[@"items"])
                if([item[@"name"] isEqual:@"Synthetic audio"] && [item[@"level"] doubleValue]>-70)meterAudible=true;
            check(meterAudible,@"real audio meter detects synthetic WAV");
            check(command(e,"audio.set",@{@"name":@"Synthetic audio",@"muted":@YES}),@"mixer mute during recording");pump(2);
            check(command(e,"audio.set",@{@"name":@"Synthetic audio",@"muted":@NO}),@"mixer unmute during recording");pump(2);
            during=state(e);check([during[@"recording"] boolValue],@"recording remains active");
            if(localRTMP){check([during[@"outputs"][@"stream"][@"started"] boolValue] && [during[@"outputs"][@"stream"][@"bytes"] unsignedLongLongValue]>0,@"simultaneous local RTMP carries encoded bytes");
                check(command(e,"stream.stop",@{}),@"local RTMP stop");}
            check(!command(e,"video.configure",@{@"width":@320,@"height":@180,@"fps":@10}),@"video reconfiguration blocked during output");
            check(!dante_engine_load(e,saved.c_str()),@"project replacement rejected during recording");
            check(command(e,"recording.stop",@{}),@"recording stop request");
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
            while([state(e)[@"recording"] boolValue] && deadline.timeIntervalSinceNow>0)pump(0.1);
            check(![state(e)[@"recording"] boolValue],@"recording finalized");
            NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:recording error:nil];
            check([attributes[NSFileSize] unsignedLongLongValue]>1000,@"MKV bytes written");
            check(!command(e,"recording.start",@{@"path":recording}),@"existing recording is never overwritten");
        }
        NSString *replayDirectory=[directory stringByAppendingPathComponent:[@"replay-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:replayDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        check(command(e,"replay.start",@{@"directory":replayDirectory,@"seconds":@2,@"bitrate":@1200,@"audioBitrate":@192}),@"real replay buffer start");
        check(configuredOutput(e,@"replay",192),@"explicit AAC192 encoder setting applied and read back");
        pump(3);check(command(e,"replay.save",@{}),@"real replay save request");
        NSString *replayPath=@"";NSDate *replayDeadline=[NSDate dateWithTimeIntervalSinceNow:6];
        while(!replayPath.length && replayDeadline.timeIntervalSinceNow>0) {
            pump(0.1);for(NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:replayDirectory error:nil])
                if([file.pathExtension.lowercaseString isEqual:@"mkv"]){replayPath=[replayDirectory stringByAppendingPathComponent:file];break;}
        }
        check(replayPath.length>0,@"replay MKV file created");
        check(command(e,"replay.stop",@{}),@"replay stop request");
        replayDeadline=[NSDate dateWithTimeIntervalSinceNow:8];
        while([state(e)[@"replaying"] boolValue] && replayDeadline.timeIntervalSinceNow>0)pump(0.1);
        check(![state(e)[@"replaying"] boolValue],@"replay returns idle");
        check([[[NSFileManager defaultManager] attributesOfItemAtPath:replayPath error:nil][NSFileSize] unsignedLongLongValue]>1000,@"saved replay contains encoded bytes");
        check(command(e,"stream.start",@{@"server":@"rtmp://127.0.0.1:19351/live",@"key":@"unavailable",@"bitrate":@1200}),@"unavailable loopback connection attempt");
        bool pending=[state(e)[@"streaming"] boolValue];
        if(pending)check(!dante_engine_load(e,saved.c_str()),@"project replacement rejected while RTMP connection pending");
        check(command(e,"stream.stop",@{}),@"cancel unavailable RTMP connection");
        NSDate *cancelDeadline=[NSDate dateWithTimeIntervalSinceNow:8];
        while([state(e)[@"streaming"] boolValue] && cancelDeadline.timeIntervalSinceNow>0)pump(0.1);
        check(![state(e)[@"streaming"] boolValue],@"cancelled RTMP connection returns idle");
        NSDictionary *finalState=state(e);
        dante_engine_destroy(e);check(true,@"engine teardown completed");
        NSDictionary *report=@{@"checks":checks,@"failures":@(failures),@"catalog":catalog ?: @{},@"duringRecording":during,@"finalState":finalState,@"recording":recording,@"replay":replayPath,@"pendingConnectionObserved":@(pending),@"testCanvas":@"640x360/10fps",@"hardware":@"current Mac only; Intel untested",@"devicesUsed":@[],@"noDeviceCapture":@YES,@"streamTargets":localRTMP ? @[@"rtmp://127.0.0.1:19350/live/test",@"rtmp://127.0.0.1:19351/live/unavailable"] : @[@"rtmp://127.0.0.1:19351/live/unavailable"],@"moduleConfigDirectory":configDirectory,@"networkScopeNote":@"The harness requests only loopback streaming. Module initialization traffic is not measured by this test."};
        NSData *reportData=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
        [reportData writeToFile:[directory stringByAppendingPathComponent:@"engine-smoke.json"] atomically:YES];
        [[NSFileManager defaultManager] removeItemAtPath:configDirectory error:nil];
        fprintf(stdout,"Recording: %s\nFailures: %d\n",recording.UTF8String,failures);return failures?1:0;
    }
}
