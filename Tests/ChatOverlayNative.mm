#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <atomic>
#include <cassert>
#include <string>
#include <vector>
static std::atomic<int> red{0}, frames{0};
static void frame(void*,video_data *data){red=data->data[0][360*data->linesize[0]+640*4];++frames;}
static void pump(){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:.5];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static void command(dante_engine_t *e,const char *op,const char *json){if(!dante_engine_command(e,op,json)){fprintf(stderr,"%s\n",dante_engine_last_error(e));abort();}}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    auto *e=dante_engine_create_with_config(argv[1],1280,720,30,directory.UTF8String);assert(e);
    command(e,"source.add",R"({"type":"dante_superchat","name":"Overlay native QA"})");
    video_scale_info conversion={};conversion.format=VIDEO_FORMAT_RGBA;conversion.width=1280;conversion.height=720;
    obs_add_raw_video_callback(&conversion,frame,nullptr);
    pump();assert(red<10);puts("PASS: empty chat source emits no fake content into program");
    std::vector<uint8_t> pixels(1100*420*4);for(size_t i=0;i<pixels.size();i+=4){pixels[i]=222;pixels[i+1]=30;pixels[i+2]=77;pixels[i+3]=255;}
    assert(!dante_chat_frame("Overlay native QA",pixels.data(),1100,420,1,true));
    assert(dante_chat_frame("Overlay native QA",pixels.data(),1100,420,4400,true));pump();
    fprintf(stderr,"pixels: frames=%d red=%d\n",frames.load(),red.load());assert(frames>0&&red>200);puts("PASS: actual program frames contain overlay RGBA pixels after animated entrance");
    auto *sceneSource=obs_get_source_by_name("Cena 1");auto *scene=obs_scene_from_source(sceneSource);auto *item=obs_scene_find_source(scene,"Overlay native QA");assert(item);
    auto id=obs_sceneitem_get_id(item);std::string hide="{\"id\":"+std::to_string(id)+",\"value\":false}";
    auto *tracked=obs_get_source_by_name("Overlay native QA");assert(obs_source_active(tracked));
    command(e,"item.visible",hide.c_str());pump();assert(red<10);assert(!obs_source_active(tracked));
    std::string show="{\"id\":"+std::to_string(id)+",\"value\":true}";command(e,"item.visible",show.c_str());pump();assert(red>200);
    command(e,"scene.select",R"({"scene":"Cena 1","studio":true})");pump();assert(red>200);
    command(e,"item.visible",hide.c_str());pump();assert(obs_source_active(tracked)); // Hidden only in preview.
    command(e,"scene.take",R"({"scene":"Cena 1","transition":"cut","duration":0})");pump();assert(!obs_source_active(tracked));
    command(e,"item.visible",show.c_str());pump();assert(!obs_source_active(tracked)); // Shown only in preview.
    command(e,"scene.take",R"({"scene":"Cena 1","transition":"cut","duration":0})");pump();assert(obs_source_active(tracked));
    obs_source_release(tracked);
    puts("PASS: program-active highlight detection follows eye and Cut, ignoring preview-only changes");
    assert(dante_chat_frame("Overlay native QA",nullptr,0,0,0,false));pump();assert(red<10);
    puts("PASS: eye visibility and session reset clear real program frames, including studio snapshot");
    command(e,"source.update",R"({"name":"Overlay native QA","settings":{"layoutWidth":640,"layoutHeight":300}})");
    auto *overlay=obs_get_source_by_name("Overlay native QA");assert(obs_source_get_width(overlay)==640&&obs_source_get_height(overlay)==300);
    assert(!dante_chat_frame("Overlay native QA",pixels.data(),1100,420,4400,false));
    std::vector<uint8_t> resized(640*300*4,255);assert(dante_chat_frame("Overlay native QA",resized.data(),640,300,2560,false));
    assert(obs_source_get_width(overlay)==640&&obs_source_get_height(overlay)==300);obs_source_release(overlay);
    command(e,"source.add",R"({"type":"dante_youtube_alert","name":"Activity QA"})");
    auto *activity=obs_get_source_by_name("Activity QA");assert(activity&&obs_source_get_width(activity)==620&&obs_source_get_height(activity)==180);
    std::vector<uint8_t> alert(620*180*4,255);assert(dante_chat_frame("Activity QA",alert.data(),620,180,2480,true));
    assert(dante_chat_frame("Activity QA",nullptr,0,0,0,false));obs_source_release(activity);
    puts("PASS: resized native texture dimensions, old-frame rejection and activity source publish/clear");
    obs_source_release(sceneSource);obs_remove_raw_video_callback(frame,nullptr);dante_engine_destroy(e);
    [[NSFileManager defaultManager]removeItemAtPath:directory error:nil];return 0;
}}
