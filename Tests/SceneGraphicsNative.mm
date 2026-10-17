#import <AppKit/AppKit.h>
#import <Vision/Vision.h>
#include "DanteEngine.h"
#include <obs.h>
#include <cassert>
#include <mutex>
#include <vector>
#include <string>
static std::mutex lock;
static std::vector<uint8_t> framePixels;
static void frame(void*,video_data *d){std::lock_guard<std::mutex> guard(lock);framePixels.resize(1280*720*4);for(int y=0;y<720;y++)memcpy(framePixels.data()+y*1280*4,d->data[0]+y*d->linesize[0],1280*4);}
static void pump(double seconds=.3){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(end.timeIntervalSinceNow>0)[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static void command(dante_engine_t *e,const char *op,NSDictionary *args){NSData *d=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];NSString *json=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];if(!dante_engine_command(e,op,json.UTF8String)){fprintf(stderr,"%s\n",dante_engine_last_error(e));abort();}}
static NSBitmapImageRep *capture(NSString *name){std::lock_guard<std::mutex> guard(lock);assert(!framePixels.empty());auto *b=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nil pixelsWide:1280 pixelsHigh:720 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:1280*4 bitsPerPixel:32];memcpy(b.bitmapData,framePixels.data(),framePixels.size());if(name)[[b representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:[@"build/scene-graphics-qa/" stringByAppendingString:name] atomically:YES];return b;}
static int channel(int x,int y,int c){std::lock_guard<std::mutex> guard(lock);return framePixels[(y*1280+x)*4+c];}
int main(int argc,char **argv){@autoreleasepool {
    assert(argc==2);[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    auto *e=dante_engine_create_with_config(argv[1],1280,720,30,directory.UTF8String);assert(e);
    video_scale_info conversion={};conversion.format=VIDEO_FORMAT_RGBA;conversion.width=1280;conversion.height=720;obs_add_raw_video_callback(&conversion,frame,nullptr);
    command(e,"source.add",@{@"type":@"dante_marquee",@"name":@"Faixa QA",@"settings":@{@"text":@"DANTE LIVE  •  CUPOM: LIVE10  •  example.org",@"speed":@0,@"height":@100,@"background":@0xA02030,@"ink":@0xFFFFFF,@"bold":@YES,@"italic":@YES}});pump();
    auto *sceneSource=obs_get_source_by_name("Cena 1");auto *scene=obs_scene_from_source(sceneSource);auto *item=obs_scene_find_source(scene,"Faixa QA");assert(item);
    assert(obs_source_get_width(obs_sceneitem_get_source(item))==1280);assert(channel(10,710,0)>140&&channel(1270,710,0)>140&&channel(10,600,0)<10);
    auto *staticImage=capture(@"marquee-static.png");int textPixels=0;for(int y=620;y<720;y++)for(int x=0;x<1280;x++)if(staticImage.bitmapData[(y*1280+x)*4+1]>150)textPixels++;assert(textPixels>500);
    auto *ocr=[[VNRecognizeTextRequest alloc]init];ocr.recognitionLevel=VNRequestTextRecognitionLevelAccurate;
    auto *ocrHandler=[[VNImageRequestHandler alloc]initWithCGImage:staticImage.CGImage options:@{}];assert([ocrHandler performRequests:@[ocr] error:nil]);
    BOOL upright=NO;for(VNRecognizedTextObservation *o in ocr.results){NSString *text=[o topCandidates:1].firstObject.string;if([text containsString:@"DANTE LIVE"]&&[text containsString:@"LIVE10"])upright=YES;}assert(upright);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"height":@60}});pump();assert(channel(10,650,0)<10&&channel(10,710,0)>140);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"speed":@500}});pump(.8);auto *first=capture(nil);pump(.4);auto *second=capture(@"marquee-moving.png");assert(memcmp(first.bitmapData,second.bitmapData,1280*720*4)!=0);
    // Studio copies the editable input: changes must wait for Cut/Transition.
    command(e,"scene.select",@{@"scene":@"Cena 1",@"studio":@YES});pump();
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"background":@0x20A030,@"text":@"TEXTO NOVO",@"speed":@0}});pump();assert(channel(10,710,0)>140&&channel(10,710,1)<80);
    command(e,"scene.take",@{@"scene":@"Cena 1",@"transition":@"cut",@"duration":@0});pump();assert(channel(10,710,1)>140&&channel(10,710,0)<80);
    puts("PASS: full-width bottom placement, variable height, static text styling, moving frames, bounded crop, Studio isolation and Cut");
    command(e,"scene.select",@{@"scene":@"Cena 1",@"studio":@NO});
    NSData *json=[NSData dataWithContentsOfFile:@"build/scene-graphics-qa/qr-settings.json"];NSDictionary *settings=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];assert(settings);
    command(e,"source.add",@{@"type":@"dante_qrcode",@"name":@"QR QA",@"settings":settings});pump();
    auto *image=capture(@"program-qr.png");VNDetectBarcodesRequest *request=[[VNDetectBarcodesRequest alloc]init];request.symbologies=@[VNBarcodeSymbologyQR];
    auto *handler=[[VNImageRequestHandler alloc]initWithCGImage:image.CGImage options:@{}];NSError *error=nil;assert([handler performRequests:@[request] error:&error]);BOOL decoded=NO;for(VNBarcodeObservation *o in request.results)if([o.payloadStringValue isEqual:@"https://example.org/cupom"])decoded=YES;assert(decoded);
    std::string saved=dante_engine_save(e);assert(saved.find("imagePNG")!=std::string::npos&&saved.find("TEXTO NOVO")!=std::string::npos);assert(dante_engine_load(e,saved.c_str()));pump();
    // Invalid or oversized PNG headers are rejected without allocating the image.
    command(e,"source.update",@{@"name":@"QR QA",@"settings":@{@"imagePNG":@"not-a-png"}});pump();assert(channel(640,360,0)<10);
    puts("PASS: QR decoded from actual program pixels; source settings survive save/reload; malformed bitmap cleared");
    obs_source_release(sceneSource);obs_remove_raw_video_callback(frame,nullptr);dante_engine_destroy(e);[[NSFileManager defaultManager]removeItemAtPath:directory error:nil];return 0;
}}
