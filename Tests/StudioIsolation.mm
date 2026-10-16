#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <graphics/vec2.h>
#include <string>
#include <cassert>
#include <vector>

static void pump(double seconds) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static void command(dante_engine_t *engine,const char *op,NSDictionary *args) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    std::string json((const char*)data.bytes,data.length);
    if(!dante_engine_command(engine,op,json.c_str())){fprintf(stderr,"%s: %s\n",op,dante_engine_last_error(engine));abort();}
}
static obs_sceneitem_t *item(obs_scene_t *scene,const char *name) {return obs_scene_find_source(scene,name);}
static std::string title(obs_source_t *source) {
    auto *settings=obs_source_get_settings(source);std::string text=obs_data_get_string(settings,"text");obs_data_release(settings);return text;
}
int main(int argc,char **argv) {@autoreleasepool {
    assert(argc==2);[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    auto *engine=dante_engine_create_with_config(argv[1],640,360,30,directory.UTF8String);assert(engine);
    command(engine,"source.add",@{@"type":@"text_ft2_source_v2",@"name":@"Title QA",@"settings":@{@"text":@"Before",@"font":@{@"face":@"Helvetica",@"size":@32}}});
    command(engine,"source.add",@{@"type":@"dante_guest_video",@"name":@"Guest QA"});
    auto *previewSource=obs_get_source_by_name("Cena 1");auto *preview=obs_scene_from_source(previewSource);
    auto *text=obs_get_source_by_name("Title QA");auto *guest=obs_get_source_by_name("Guest QA");
    pump(.2);
    command(engine,"scene.select",@{@"scene":@"Cena 1",@"studio":@YES});
    auto *transition=obs_get_output_source(0);auto *program=obs_transition_get_active_source(transition);
    assert(program!=previewSource);auto *published=obs_scene_from_source(program);
    auto *publishedText=obs_sceneitem_get_source(item(published,"Title QA"));
    assert(publishedText!=text && title(publishedText)=="Before");
    assert(obs_sceneitem_get_source(item(published,"Guest QA"))==guest);
    std::vector<uint8_t> camera(320*180*4,255);obs_source_frame frame={};
    frame.width=320;frame.height=180;frame.format=VIDEO_FORMAT_RGBA;frame.data[0]=camera.data();frame.linesize[0]=320*4;
    obs_source_output_video(guest,&frame);pump(.2);dante_engine_state(engine);
    vec2 guestScale;obs_sceneitem_get_scale(item(published,"Guest QA"),&guestScale);
    assert(guestScale.x==1 && guestScale.y==1); // Initial placement never enlarges a new source.
    vec2 guestPosition;obs_sceneitem_get_pos(item(published,"Guest QA"),&guestPosition);
    assert(guestPosition.x==160 && guestPosition.y==90);
    command(engine,"source.update",@{@"name":@"Title QA",@"settings":@{@"text":@"After"}});
    command(engine,"item.transform",@{@"id":@(obs_sceneitem_get_id(item(preview,"Title QA"))),@"x":@100,@"y":@80,@"cropTop":@5,@"cropBottom":@7});
    command(engine,"item.visible",@{@"id":@(obs_sceneitem_get_id(item(preview,"Guest QA"))),@"value":@NO});
    pump(.2);vec2 position;obs_sceneitem_get_pos(item(published,"Title QA"),&position);
    assert(title(text)=="After" && title(publishedText)=="Before" && position.x!=100);
    assert(obs_sceneitem_visible(item(published,"Guest QA")));
    puts("PASS: text, item position, vertical crop and visibility stay in preview; guest uses one live source");
    obs_source_release(program);
    for(NSString *style in @[@"cut",@"fade"]) {
        command(engine,"scene.take",@{@"scene":@"Cena 1",@"transition":style,@"duration":@120});pump(.35);
        program=obs_transition_get_active_source(transition);published=obs_scene_from_source(program);
        assert(title(obs_sceneitem_get_source(item(published,"Title QA")))=="After");
        obs_sceneitem_get_pos(item(published,"Title QA"),&position);assert(position.x==100 && position.y==80);
        obs_sceneitem_crop crop;obs_sceneitem_get_crop(item(published,"Title QA"),&crop);assert(crop.top==5 && crop.bottom==7);
        assert(!obs_sceneitem_visible(item(published,"Guest QA")));obs_source_release(program);
    }
    puts("PASS: Cut and Fade publish all staged edits even to the same scene");
    std::string saved=dante_engine_save(engine);
    assert(saved.find("Dante program")==std::string::npos);
    obs_source_release(text);obs_source_release(guest);obs_source_release(previewSource);obs_source_release(transition);
    assert(dante_engine_load(engine,saved.c_str()));
    command(engine,"scene.select",@{@"scene":@"Cena 1",@"studio":@NO});
    transition=obs_get_output_source(0);program=obs_transition_get_active_source(transition);previewSource=obs_get_source_by_name("Cena 1");
    assert(program==previewSource);obs_source_release(program);obs_source_release(previewSource);obs_source_release(transition);
    dante_engine_destroy(engine);[[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
    puts("PASS: private snapshots excluded from project; restore, disable studio and teardown");return 0;
}}
