#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <atomic>
#include <cmath>
#include <string>
static std::atomic<uint32_t> width{0},height{0};
static NSMutableArray *checks;static int failures=0;
static void check(bool ok,NSString *name){[checks addObject:@{@"name":name,@"passed":@(ok)}];printf("%s %s\n",ok?"PASS":"FAIL",name.UTF8String);fflush(stdout);if(!ok)failures++;}
static id parse(const char *json){return [NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];}
static bool command(dante_engine_t *e,const char *op,id args){NSData *d=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];std::string s((const char*)d.bytes,d.length);return dante_engine_command(e,op,s.c_str());}
static NSDictionary *item(dante_engine_t *e,NSString *name){for(NSDictionary *scene in parse(dante_engine_state(e))[@"scenes"])for(NSDictionary *i in scene[@"items"])if([i[@"name"] isEqual:name])return i;return nil;}
static bool near(id n,double expected){return fabs([n doubleValue]-expected)<.02;}
static void pump(double seconds){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static NSString *fixture(NSString *directory,int w,int h){NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w*4 bitsPerPixel:32];memset(bitmap.bitmapData,255,w*h*4);NSString *path=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"image-%dx%d.png",w,h]];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];return path;}
int main(int argc,char **argv){@autoreleasepool{
 if(argc!=3)return 2;[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];checks=[NSMutableArray array];
 NSString *config=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"DantePlacement-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 auto *e=dante_engine_create_with_config(argv[1],640,360,10,config.UTF8String);if(!e)return 3;
 obs_source_info info={};info.id="dante_test_dimensions";info.type=OBS_SOURCE_TYPE_INPUT;info.output_flags=OBS_SOURCE_VIDEO;
 info.get_name=[](void*){return "Synthetic delayed dimensions";};info.create=[](obs_data_t*,obs_source_t *s)->void*{return s;};info.destroy=[](void*){};
 info.get_width=[](void*){return width.load();};info.get_height=[](void*){return height.load();};info.video_render=[](void*,gs_effect_t*){};
 info.get_properties=[](void*){auto *props=obs_properties_create();auto *fps=obs_properties_add_frame_rate(props,"frame_rate","FPS");media_frames_per_second min={24000,1001},max={60,1};obs_property_frame_rate_fps_range_add(fps,min,max);return props;};obs_register_source(&info);
 NSDictionary *schema=parse(dante_engine_type_properties(e,"dante_test_dimensions"));NSArray *ranges=schema[@"properties"][0][@"ranges"];
 check(ranges.count==1&&[ranges[0][@"minNumerator"] intValue]==24000&&[ranges[0][@"minDenominator"] intValue]==1001&&[ranges[0][@"maxNumerator"] intValue]==60,@"fractional FPS ranges serialized from native properties");
 for(NSArray *size in @[@[@200,@100],@[@1280,@720]]){int w=[size[0] intValue],h=[size[1] intValue];NSString *name=[NSString stringWithFormat:@"Image %d",w];
  check(command(e,"source.add",@{@"name":name,@"type":@"image_source",@"settings":@{@"file":fixture(config,w,h)}}),@"image fixture source created");pump(.2);NSDictionary *i=item(e,name);
  check(near(i[@"scaleX"],w==200?1:.5)&&near(i[@"x"],w==200?220:0)&&near(i[@"y"],w==200?130:0)&&![i[@"pendingPlacement"] boolValue],w==200?@"small image centered without enlargement":@"large image aspect-fit downscaled");}
 command(e,"source.add",@{@"name":@"Delayed",@"type":@"dante_test_dimensions"});NSDictionary *i=item(e,@"Delayed");NSNumber *identifier=i[@"id"];
 check([i[@"pendingPlacement"] boolValue]&&[i[@"awaitingVideo"] boolValue]&&near(i[@"x"],320),@"zero dimensions expose waiting state with center anchor");
 width=320;height=180;pump(.1);i=item(e,@"Delayed");check(![i[@"pendingPlacement"] boolValue]&&! [i[@"awaitingVideo"] boolValue]&&near(i[@"x"],160)&&near(i[@"y"],90)&&near(i[@"scaleX"],1),@"first dimensions resolve centered native placement");
 width=0;height=0;command(e,"source.add",@{@"name":@"Edited pending",@"type":@"dante_test_dimensions"});NSNumber *editedID=item(e,@"Edited pending")[@"id"];
 command(e,"item.transform",@{@"id":editedID,@"x":@42,@"y":@55,@"scaleX":@.7,@"scaleY":@.7});width=640;height=360;pump(.1);i=item(e,@"Edited pending");
 check(![i[@"pendingPlacement"] boolValue]&&near(i[@"x"],42)&&near(i[@"y"],55)&&near(i[@"scaleX"],.7),@"manual transform cancels delayed automatic placement");
 command(e,"item.transform",@{@"id":identifier,@"x":@30,@"rotation":@35,@"cropLeft":@20,@"scaleX":@.6,@"scaleY":@.6});
 check(command(e,"item.center",@{@"id":identifier}),@"center command accepted");pump(.1);i=item(e,@"Delayed");NSArray *corners=i[@"boxCorners"];
 check(fabs(([corners[0][0] doubleValue]+[corners[2][0] doubleValue])/2-320)<.5&&fabs(([corners[0][1] doubleValue]+[corners[2][1] doubleValue])/2-180)<.5&&near(i[@"rotation"],35)&&[i[@"cropLeft"] intValue]==20,@"center preserves crop rotation scale and centers transformed box");
 check(command(e,"item.native",@{@"id":identifier}),@"native-size command accepted");pump(.1);i=item(e,@"Delayed");check(near(i[@"scaleX"],1)&&near(i[@"rotation"],0)&&[i[@"cropLeft"] intValue]==0&&near(i[@"x"],0),@"native-size resets transform crop and centers");
 width=0;height=0;check(command(e,"item.fit",@{@"id":identifier})&&[item(e,@"Delayed")[@"pendingPlacement"] boolValue],@"fit queues while dimensions are unavailable");width=160;height=90;pump(.1);i=item(e,@"Delayed");check(near(i[@"scaleX"],4)&&near(i[@"x"],0)&&![i[@"pendingPlacement"] boolValue],@"explicit pending fit can enlarge once dimensions arrive");
 width=0;height=0;command(e,"source.add",@{@"name":@"Legacy default",@"type":@"dante_test_dimensions"});NSNumber *legacyID=item(e,@"Legacy default")[@"id"];
 command(e,"item.transform",@{@"id":legacyID,@"x":@0,@"y":@0});check(command(e,"source.update",@{@"name":@"Legacy default",@"settings":@{},@"autoPlace":@YES})&&[item(e,@"Legacy default")[@"pendingPlacement"] boolValue],@"explicit configuration repairs untouched legacy zero-size placement");
 command(e,"source.update",@{@"name":@"Edited pending",@"settings":@{},@"autoPlace":@YES});check(![item(e,@"Edited pending")[@"pendingPlacement"] boolValue]&&near(item(e,@"Edited pending")[@"x"],42),@"explicit repair preserves existing edited composition");width=320;height=180;pump(.1);check(near(item(e,@"Legacy default")[@"x"],160),@"legacy capture first dimensions center once");
 width=0;height=0;command(e,"item.fit",@{@"id":identifier});std::string pendingProject=dante_engine_save(e);check(dante_engine_load(e,pendingProject.c_str())&&[item(e,@"Delayed")[@"pendingPlacement"] boolValue],@"pending placement persists through project save and load");width=320;height=180;pump(.1);check(near(item(e,@"Delayed")[@"scaleX"],2)&&![item(e,@"Delayed")[@"pendingPlacement"] boolValue],@"restored pending fit resolves once dimensions arrive");
 command(e,"scene.create",@{@"name":@"Offscreen"});command(e,"source.add",@{@"scene":@"Offscreen",@"name":@"Preview only",@"type":@"dante_test_dimensions"});
 auto *source=obs_get_source_by_name("Preview only");pump(.1);check(!obs_source_showing(source),@"inactive-scene source initially not showing");
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,320,180) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;
 void *preview=dante_engine_source_preview_create(e,(__bridge void*)window.contentView,"Preview only");pump(.15);check(preview&&obs_source_showing(source),@"source preview retains and activates only existing source");
 command(e,"source.remove",@{@"scene":@"Offscreen",@"id":item(e,@"Preview only")[@"id"]});dante_engine_preview_resize(preview,640,360);pump(.15);check(obs_source_showing(source),@"preview survives removal of scene item");dante_engine_preview_destroy(preview);pump(.1);check(!obs_source_showing(source),@"source preview balances showing on destroy");obs_source_release(source);[window close];
 dante_engine_destroy(e);check(true,@"engine teardown after previews and synthetic sources");[[NSFileManager defaultManager] removeItemAtPath:config error:nil];
 NSDictionary *report=@{@"passed":@(failures==0),@"failures":@(failures),@"noDeviceCapture":@YES,@"checks":checks};[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];return failures?1:0;
}}
