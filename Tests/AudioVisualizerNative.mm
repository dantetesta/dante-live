#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <cassert>
#include <cmath>
#include <mutex>
#include <vector>

static std::mutex frameMutex;
static std::vector<uint8_t> framePixels;
static void onFrame(void *, video_data *frame) {
    std::lock_guard<std::mutex> lock(frameMutex);
    framePixels.resize(1280 * 720 * 4);
    for (int y=0; y<720; ++y) memcpy(framePixels.data()+y*1280*4,frame->data[0]+y*frame->linesize[0],1280*4);
}
static void pump(double seconds) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static void command(dante_engine_t *engine,const char *name,NSDictionary *args) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    NSString *json=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    if(!dante_engine_command(engine,name,json.UTF8String)){fprintf(stderr,"%s\n",dante_engine_last_error(engine));abort();}
}
static int coloredPixels() {
    std::lock_guard<std::mutex> lock(frameMutex);
    int count=0;
    for(size_t i=0;i+3<framePixels.size();i+=4)
        if(framePixels[i+1]>80 && framePixels[i+2]>80 && framePixels[i+2]>framePixels[i])++count;
    return count;
}
static void saveFrame(int style) {
    std::lock_guard<std::mutex> lock(frameMutex);
    auto *image=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nil pixelsWide:1280 pixelsHigh:720 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:1280*4 bitsPerPixel:32];
    memcpy(image.bitmapData,framePixels.data(),framePixels.size());
    NSString *folder=@"build/audio-visualizer-qa";
    [[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"style-%02d.png",style]];
    [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];
}
static void le16(NSMutableData *data,uint16_t value){uint8_t b[2]={uint8_t(value),uint8_t(value>>8)};[data appendBytes:b length:2];}
static void le32(NSMutableData *data,uint32_t value){uint8_t b[4]={uint8_t(value),uint8_t(value>>8),uint8_t(value>>16),uint8_t(value>>24)};[data appendBytes:b length:4];}
static NSString *sineWAV(NSString *folder) {
    const int sampleRate=48000, frames=sampleRate*3;
    NSMutableData *wav=[NSMutableData data];
    [wav appendBytes:"RIFF" length:4];le32(wav,36+frames*2);[wav appendBytes:"WAVEfmt " length:8];
    le32(wav,16);le16(wav,1);le16(wav,1);le32(wav,sampleRate);le32(wav,sampleRate*2);le16(wav,2);le16(wav,16);
    [wav appendBytes:"data" length:4];le32(wav,frames*2);
    for(int i=0;i<frames;++i)le16(wav,uint16_t(int16_t(std::sin(2*M_PI*440*i/sampleRate)*25000)));
    NSString *path=[folder stringByAppendingPathComponent:@"tone.wav"];assert([wav writeToFile:path atomically:YES]);return path;
}
int main(int argc,char **argv) {@autoreleasepool {
    assert(argc==2);[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *path=sineWAV(folder);
    auto *engine=dante_engine_create_with_config(argv[1],1280,720,30,folder.UTF8String);assert(engine);
    video_scale_info conversion={};conversion.format=VIDEO_FORMAT_RGBA;conversion.width=1280;conversion.height=720;
    obs_add_raw_video_callback(&conversion,onFrame,nullptr);
    command(engine,"source.add",@{@"type":@"ffmpeg_source",@"name":@"Tom QA",@"settings":@{@"is_local_file":@YES,@"local_file":path,@"looping":@YES}});
    auto *audio=obs_get_source_by_name("Tom QA");assert(audio);NSString *uuid=[NSString stringWithUTF8String:obs_source_get_uuid(audio)];
    command(engine,"source.add",@{@"type":@"dante_audio_visualizer",@"name":@"Visual QA",@"settings":@{@"audioSourceUUID":uuid,@"style":@1,@"layoutWidth":@900,@"layoutHeight":@280}});
    auto *visual=obs_get_source_by_name("Visual QA");assert(visual);
    assert(obs_source_get_width(visual)==900&&obs_source_get_height(visual)==280);
    command(engine,"media.restart",@{@"name":@"Tom QA"});pump(1.5);
    int active=coloredPixels();assert(active>450);
    for(int style=0;style<10;++style) {
        command(engine,"source.update",@{@"name":@"Visual QA",@"settings":@{@"style":@(style)}});
        pump(0.25);
        assert(coloredPixels()>100);
        saveFrame(style);
    }
    command(engine,"source.update",@{@"name":@"Visual QA",@"settings":@{@"style":@1}});pump(0.4);
    active=coloredPixels();assert(active>450);
    obs_source_set_muted(audio,true);pump(1.2);
    int silent=coloredPixels();assert(active>silent*2);
    command(engine,"source.update",@{@"name":@"Visual QA",@"settings":@{@"layoutWidth":@1200,@"layoutHeight":@360,@"style":@8}});
    pump(0.25);
    assert(obs_source_get_width(visual)==1200&&obs_source_get_height(visual)==360);
    std::string saved=dante_engine_save(engine);assert(saved.find("audioSourceUUID")!=std::string::npos);
    assert(dante_engine_load(engine,saved.c_str()));pump(0.4);
    auto *restored=obs_get_source_by_name("Visual QA");assert(restored&&obs_source_get_width(restored)==1200);obs_source_release(restored);
    obs_source_release(visual);obs_source_release(audio);
    obs_remove_raw_video_callback(onFrame,nullptr);dante_engine_destroy(engine);
    [[NSFileManager defaultManager]removeItemAtPath:folder error:nil];
    printf("PASS: real PCM drives pixels, mute decays, content resize and source binding persist\n");
    return 0;
}}
