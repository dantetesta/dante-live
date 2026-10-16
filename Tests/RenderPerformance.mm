#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <graphics/graphics.h>
#include <atomic>
#include <cassert>
#include <initializer_list>
#include <sys/resource.h>

// Synthetic source only: count real render submissions without a webcam/network.
static std::atomic<uint64_t> draws{0};
static void pump(double seconds) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
}
static double cpu() {rusage r={};getrusage(RUSAGE_SELF,&r);return r.ru_utime.tv_sec+r.ru_utime.tv_usec/1e6+r.ru_stime.tv_sec+r.ru_stime.tv_usec/1e6;}
int main(int argc,char **argv) {@autoreleasepool {
    assert(argc==2);[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    auto *engine=dante_engine_create_with_config(argv[1],2560,1440,30,directory.UTF8String);assert(engine);
    obs_source_info info={};info.id="dante_perf_synthetic";info.type=OBS_SOURCE_TYPE_INPUT;info.output_flags=OBS_SOURCE_VIDEO|OBS_SOURCE_DO_NOT_DUPLICATE;
    info.get_name=[](void*){return "Synthetic render counter";};info.create=[](obs_data_t*,obs_source_t*)->void*{return &draws;};info.destroy=[](void*){};
    info.get_width=[](void*)->uint32_t{return 2560;};info.get_height=[](void*)->uint32_t{return 1440;};
    info.video_render=[](void*,gs_effect_t*){draws++;auto *effect=obs_get_base_effect(OBS_EFFECT_SOLID);vec4 color={.1f,.4f,.7f,1.f};gs_effect_set_vec4(gs_effect_get_param_by_name(effect,"color"),&color);while(gs_effect_loop(effect,"Solid"))gs_draw_sprite(nullptr,0,2560,1440);};
    obs_register_source(&info);
    assert(dante_engine_command(engine,"source.add","{\"type\":\"dante_perf_synthetic\",\"name\":\"Synthetic\"}"));
    NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1280,400) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;
    NSView *left=[[NSView alloc]initWithFrame:NSMakeRect(0,0,640,360)],*right=[[NSView alloc]initWithFrame:NSMakeRect(640,0,640,360)];
    [window.contentView addSubview:left];[window.contentView addSubview:right];
    void *preview=dante_engine_preview_create(engine,(__bridge void*)left,false),*program=dante_engine_preview_create(engine,(__bridge void*)right,true);assert(preview&&program);
    // Offscreen displays still execute their callbacks; no operator window is touched.
    for(bool studio:{false,true}) {
        assert(dante_engine_command(engine,"scene.select",studio?"{\"studio\":true}":"{\"studio\":false}"));pump(1);
        auto before=draws.load();auto frames=obs_get_total_frames(),lagged=obs_get_lagged_frames();double start=cpu();pump(5);
        printf("{\"studio\":%s,\"frames\":%u,\"lagged\":%u,\"sourceDraws\":%llu,\"averageRenderMS\":%.3f,\"cpuSeconds\":%.3f}\n",studio?"true":"false",obs_get_total_frames()-frames,obs_get_lagged_frames()-lagged,(unsigned long long)(draws.load()-before),obs_get_average_frame_time_ns()/1e6,cpu()-start);fflush(stdout);
    }
    dante_engine_preview_destroy(preview);dante_engine_preview_destroy(program);[window close];dante_engine_destroy(engine);
    [[NSFileManager defaultManager]removeItemAtPath:directory error:nil];return 0;
}}
