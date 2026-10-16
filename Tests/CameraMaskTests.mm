#import <AppKit/AppKit.h>
#include "DanteEngine.h"
#include <obs.h>
#include <util/base.h>
#include <graphics/graphics.h>
#include <vector>
#include <string>
static void pump(double t){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:t];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static bool command(dante_engine_t *e,const char *op,NSDictionary *args){NSData*d=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];std::string s((const char*)d.bytes,d.length);return dante_engine_command(e,op,s.c_str());}
static std::vector<uint8_t> pixels(obs_source_t*s){uint32_t w=obs_source_get_width(s),h=obs_source_get_height(s);std::vector<uint8_t> result(w*h*4);
 obs_enter_graphics();auto*t=gs_texrender_create(GS_RGBA,GS_ZS_NONE);auto*stage=gs_stagesurface_create(w,h,GS_RGBA);
 if(gs_texrender_begin(t,w,h)){vec4 clear={};gs_clear(GS_CLEAR_COLOR,&clear,0,0);gs_ortho(0,w,0,h,-100,100);gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);obs_source_video_render(s);gs_blend_state_pop();gs_texrender_end(t);
 gs_stage_texture(stage,gs_texrender_get_texture(t));uint8_t*data=nullptr;uint32_t stride=0;if(gs_stagesurface_map(stage,&data,&stride)){for(uint32_t y=0;y<h;y++)memcpy(result.data()+y*w*4,data+y*stride,w*4);gs_stagesurface_unmap(stage);}}
 gs_stagesurface_destroy(stage);gs_texrender_destroy(t);obs_leave_graphics();return result;
}
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=2)return 2;[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 NSString *root=[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString];auto*e=dante_engine_create_with_config(argv[1],640,360,10,root.UTF8String);if(!e)return 3;
 NSBitmapImageRep*img=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nullptr pixelsWide:200 pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:800 bitsPerPixel:32];
 for(int y=0;y<100;y++)for(int x=0;x<200;x++){auto*p=img.bitmapData+(y*200+x)*4;p[0]=x<100?255:0;p[1]=0;p[2]=x<100?0:255;p[3]=255;}
 NSString*file=[root stringByAppendingPathComponent:@"mask.png"];[[img representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:file atomically:YES];
 base_set_log_handler([](int level,const char*format,va_list args,void*){if(level<=LOG_WARNING){vfprintf(stderr,format,args);fprintf(stderr,"\n");}},nullptr);
 int fail=0;auto check=[&](bool ok,const char*label){printf("%s: %s\n",ok?"PASS":"FAIL",label);fflush(stdout);if(!ok)fail++;};
 check(command(e,"source.add",@{@"type":@"image_source",@"name":@"Mask QA",@"settings":@{@"file":file}}),"synthetic image source");pump(.3);auto*s=obs_get_source_by_name("Mask QA");
 for(int shape=1;shape<=6;shape++){
  check(command(e,"source.cameraMask",@{@"name":@"Mask QA",@"settings":@{@"shape":@(shape),@"aspect":@1.5,@"roundness":@.5}}),"GPU mask filter created/updated");pump(.1);
  auto rgba=pixels(s);auto w=obs_source_get_width(s),h=obs_source_get_height(s);check(w>0&&h>0&&!rgba.empty(),"mask dimensions and GPU readback");
  if(rgba.empty())continue;printf("shape %d size %u x %u alpha %d\n",shape,w,h,rgba[3]);auto center=(h/2*w+w/2)*4;check(rgba[center+3]>240,"center stays opaque");check((shape==1||shape==5)?rgba[3]>240:rgba[3]<10,"shape corner transparency");
 }
 command(e,"source.cameraMask",@{@"name":@"Mask QA",@"settings":@{@"shape":@3,@"zoom":@2,@"panX":@-1}});pump(.1);auto left=pixels(s);auto w=obs_source_get_width(s),h=obs_source_get_height(s);auto center=(h/2*w+w/2)*4;
 command(e,"source.cameraMask",@{@"name":@"Mask QA",@"settings":@{@"shape":@3,@"zoom":@2,@"panX":@1}});pump(.1);auto right=pixels(s);
 check(left[center]>200&&left[center+2]<10&&right[center]<10&&right[center+2]>200,"zoom and framing select different source pixels");
 std::string saved=dante_engine_save(e);obs_source_release(s);check(dante_engine_load(e,saved.c_str()),"mask project restore");pump(.1);s=obs_get_source_by_name("Mask QA");check(obs_source_get_width(s)==100&&pixels(s)[3]<10,"restored circle retains shape");
 check(command(e,"source.cameraMask",@{@"name":@"Mask QA",@"settings":@{@"shape":@0}}),"native mask removal");check(obs_source_get_width(s)==200&&obs_source_get_height(s)==100,"native dimensions restored");obs_source_release(s);dante_engine_destroy(e);[[NSFileManager defaultManager]removeItemAtPath:root error:nil];return fail?1:0;
}}
