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
    auto *ocr=[[VNRecognizeTextRequest alloc]init];ocr.recognitionLevel=VNRequestTextRecognitionLevelFast;
    NSData *ocrPNG=[staticImage representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    auto *ocrHandler=[[VNImageRequestHandler alloc]initWithData:ocrPNG options:@{}];NSError *ocrError=nil;
    BOOL ocrOK=[ocrHandler performRequests:@[ocr] error:&ocrError];if(!ocrOK)fprintf(stderr,"Vision OCR unavailable: %s\n",ocrError.localizedDescription.UTF8String);assert(ocrOK);
    BOOL upright=NO;for(VNRecognizedTextObservation *o in ocr.results){NSString *text=[o topCandidates:1].firstObject.string;if([text containsString:@"DANTE LIVE"]&&[text containsString:@"LIVE10"])upright=YES;}assert(upright);
    // A family outside the old six-font menu must change the actual output.
    NSArray<NSString*> *oldChoices=@[@"Helvetica Neue",@"Avenir Next",@"Georgia",@"Menlo",@"Trebuchet MS",@"Verdana"];
    NSString *testFamily=nil;
    for(NSString *candidate in [[NSFontManager sharedFontManager] availableFontFamilies]) {
        if(![oldChoices containsObject:candidate] && [[NSFontManager sharedFontManager] fontWithFamily:candidate traits:0 weight:5 size:36]) {testFamily=candidate;break;}
    }
    assert(testFamily);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"font":testFamily}});pump();
    auto *otherFont=capture(nil);
    assert(memcmp(staticImage.bitmapData,otherFont.bitmapData,1280*720*4)!=0);
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
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"displayMode":@0,@"speed":@0,@"text":@"TESTE",@"gradientEnabled":@YES,@"background":@0xEE0000,@"gradientEndColor":@0x0000EE,@"gradientAxis":@0,@"gradientStart":@0,@"gradientEndPosition":@100,@"backgroundOpacity":@1,@"gradientEndOpacity":@1}});pump();
    assert(channel(10,700,0)>150&&channel(10,700,2)<70);
    assert(channel(1270,700,2)>150&&channel(1270,700,0)<70);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"gradientAxis":@2,@"gradientStart":@25,@"gradientEndPosition":@75}});pump();
    assert(channel(10,665,0)>150&&channel(10,665,2)<70);
    assert(channel(10,715,2)>150&&channel(10,715,0)<70);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"backgroundOpacity":@0,@"gradientEndOpacity":@0}});pump();
    assert(channel(10,700,0)<30&&channel(1270,700,2)<30);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"backgroundOpacity":@1,@"gradientEndOpacity":@1,@"gradientEnabled":@NO,@"background":@0x142632,@"speed":@300,@"scrollDirection":@1}});pump(.55);
    auto whiteCenter=[](NSBitmapImageRep *image) {
        double sum=0,count=0;auto *bytes=image.bitmapData;
        for(int y=665;y<720;y++)for(int x=0;x<1280;x++) {
            auto *pixel=bytes+y*image.bytesPerRow+x*4;
            if(pixel[0]>180&&pixel[1]>180&&pixel[2]>180){sum+=x;count++;}
        }
        return count>20?sum/count:-1.0;
    };
    double before=whiteCenter(capture(nil));pump(.25);double after=whiteCenter(capture(nil));
    assert(before>=0&&after>before+20);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"displayMode":@1,@"text":@"PRIMEIRA\n\nSEGUNDA",@"phraseInterval":@1,@"slideDirection":@0}});pump(.7);
    auto *phraseOne=capture(@"phrase-one.png");assert(whiteCenter(phraseOne)>=0);
    pump(1);auto *phraseTwo=capture(@"phrase-two.png");assert(whiteCenter(phraseTwo)>=0);
    assert(memcmp(phraseOne.bitmapData,phraseTwo.bitmapData,1280*720*4)!=0);
    command(e,"source.update",@{@"name":@"Faixa QA",@"settings":@{@"slideDirection":@1}});pump(.1);
    auto *entering=capture(nil);pump(.3);auto *settled=capture(nil);
    assert(memcmp(entering.bitmapData,settled.bitmapData,1280*720*4)!=0);
    puts("PASS: two-color gradient and opacity in program pixels, reverse scroll, line-based phrases and slide motion");
    obs_source_release(sceneSource);obs_remove_raw_video_callback(frame,nullptr);dante_engine_destroy(e);[[NSFileManager defaultManager]removeItemAtPath:directory error:nil];return 0;
}}
