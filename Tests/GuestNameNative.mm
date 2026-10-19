#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <cassert>
#include <mutex>
#include <vector>

static std::mutex frameMutex;
static std::vector<uint8_t> pixels;
static void onFrame(void *, video_data *frame) {
    std::lock_guard<std::mutex> lock(frameMutex);
    pixels.resize(1280*720*4);
    for(int y=0;y<720;++y)memcpy(pixels.data()+y*1280*4,frame->data[0]+y*frame->linesize[0],1280*4);
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
static uint64_t fingerprint() {
    std::lock_guard<std::mutex> lock(frameMutex);uint64_t hash=1469598103934665603ULL;
    for(size_t i=0;i<pixels.size();i+=19){hash^=pixels[i];hash*=1099511628211ULL;}
    return hash;
}
static size_t colored() {
    std::lock_guard<std::mutex> lock(frameMutex);size_t count=0;
    for(size_t i=0;i+3<pixels.size();i+=4)if(pixels[i]>40||pixels[i+1]>40||pixels[i+2]>40)++count;
    return count;
}
static void screenshot(int style) {
    std::lock_guard<std::mutex> lock(frameMutex);
    auto *image=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nil pixelsWide:1280 pixelsHigh:720 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:1280*4 bitsPerPixel:32];
    memcpy(image.bitmapData,pixels.data(),pixels.size());
    NSString *folder=@"build/guest-name-qa";
    [[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"style-%02d.png",style]] atomically:YES];
}
int main(int argc,char **argv) {@autoreleasepool {
    assert(argc==2);[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil]);
    auto *engine=dante_engine_create_with_config(argv[1],1280,720,30,folder.UTF8String);assert(engine);
    video_scale_info conversion={};conversion.format=VIDEO_FORMAT_RGBA;conversion.width=1280;conversion.height=720;
    obs_add_raw_video_callback(&conversion,onFrame,nullptr);
    command(engine,"source.add",@{@"type":@"dante_guest_name",@"name":@"Nome QA",@"settings":@{@"guestName":@"Marina Costa"}});
    auto *source=obs_get_source_by_name("Nome QA");assert(source);
    pump(0.5);assert(colored()>1000);
    uint64_t previous=fingerprint();
    command(engine,"source.update",@{@"name":@"Nome QA",@"settings":@{@"guestName":@"Antônio Lopes"}});
    pump(0.3);assert(fingerprint()!=previous);
    previous=fingerprint();
    for(int style=0;style<6;++style) {
        command(engine,"source.update",@{@"name":@"Nome QA",@"settings":@{@"style":@(style)}});
        pump(0.25);assert(colored()>150);screenshot(style);
        if(style)assert(fingerprint()!=previous);
        previous=fingerprint();
    }
    command(engine,"source.update",@{@"name":@"Nome QA",@"settings":@{@"layoutWidth":@760,@"layoutHeight":@130,@"fontFace":@"Menlo"}});
    pump(0.3);assert(obs_source_get_width(source)==760 && obs_source_get_height(source)==130);
    std::string saved=dante_engine_save(engine);assert(saved.find("Antônio Lopes")!=std::string::npos);
    assert(dante_engine_load(engine,saved.c_str()));pump(0.3);
    auto *restored=obs_get_source_by_name("Nome QA");assert(restored&&obs_source_get_width(restored)==760);obs_source_release(restored);
    obs_source_release(source);obs_remove_raw_video_callback(onFrame,nullptr);dante_engine_destroy(engine);
    [[NSFileManager defaultManager]removeItemAtPath:folder error:nil];
    printf("PASS: guest name renders, updates without source replacement, six styles and responsive dimensions persist\n");
    return 0;
}}
