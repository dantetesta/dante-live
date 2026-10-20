#pragma once
// CPU rasterization only on settings edits. Animation and clipping stay on GPU.
// Unlike live chat inputs these sources are duplicated for Studio snapshots.
namespace DanteGraphics {
static NSColor *color(uint32_t value) {
    return [NSColor colorWithSRGBRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
}
static NSBitmapImageRep *bitmap(int w,int h) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w*4 bitsPerPixel:32];
}
struct Tile { gs_texture_t *texture=nullptr; uint32_t x=0,width=0; };
struct Phrase { gs_texture_t *texture=nullptr; uint32_t width=0,height=0; };
struct Source {
    std::atomic<uint32_t> width{512},height{512};
    std::vector<Tile> tiles;
    std::vector<Phrase> phrases;
    gs_texture_t *background=nullptr;
    double textWidth=0,speed=90,phraseInterval=5;
    uint64_t started=0;
    bool marquee=false,phraseMode=false,reverseScroll=false,slideDown=false;
};
static void clear(Source *s) {
    for(auto &tile:s->tiles)gs_texture_destroy(tile.texture);
    s->tiles.clear();for(auto &phrase:s->phrases)gs_texture_destroy(phrase.texture);
    s->phrases.clear();gs_texture_destroy(s->background);s->background=nullptr;
}
static gs_texture_t *texture(NSBitmapImageRep *b) {
    if(!b)return nullptr;
    auto *t=gs_texture_create((uint32_t)b.pixelsWide,(uint32_t)b.pixelsHigh,GS_RGBA,1,nullptr,GS_DYNAMIC);
    if(t)gs_texture_set_image(t,b.bitmapData,(uint32_t)b.bytesPerRow,false);
    return t;
}
static NSBitmapImageRep *bandBackground(obs_data_t *data,int width,int height) {
    bool gradient=obs_data_get_bool(data,"gradientEnabled");
    int axis=std::clamp<int>((int)obs_data_get_int(data,"gradientAxis"),0,3);
    int pixels=gradient ? (axis<2 ? width : height) : 1;
    auto *image=bitmap(axis<2 ? pixels : 1,axis<2 ? 1 : pixels);
    if(!image)return nil;
    auto first=color((uint32_t)obs_data_get_int(data,"background"));
    auto last=color((uint32_t)obs_data_get_int(data,"gradientEndColor"));
    double firstAlpha=obs_data_get_double(data,"backgroundOpacity"),lastAlpha=obs_data_get_double(data,"gradientEndOpacity");
    firstAlpha=std::isfinite(firstAlpha)?std::clamp(firstAlpha,0.0,1.0):1;
    lastAlpha=std::isfinite(lastAlpha)?std::clamp(lastAlpha,0.0,1.0):1;
    double start=std::clamp(obs_data_get_double(data,"gradientStart")/100.0,0.0,0.95);
    double finish=std::clamp(obs_data_get_double(data,"gradientEndPosition")/100.0,start+0.01,1.0);
    for(int i=0;i<pixels;i++) {
        double progress=pixels>1 ? double(i)/double(pixels-1) : 0;
        if(axis==1||axis==3)progress=1-progress;
        double mix=gradient?std::clamp((progress-start)/(finish-start),0.0,1.0):0;
        double alpha=firstAlpha*(1-mix)+lastAlpha*mix;
        uint8_t *out=image.bitmapData+i*4;
        out[0]=(uint8_t)lround((first.redComponent*(1-mix)+last.redComponent*mix)*alpha*255);
        out[1]=(uint8_t)lround((first.greenComponent*(1-mix)+last.greenComponent*mix)*alpha*255);
        out[2]=(uint8_t)lround((first.blueComponent*(1-mix)+last.blueComponent*mix)*alpha*255);
        out[3]=(uint8_t)lround(alpha*255);
    }
    return image;
}
static NSBitmapImageRep *phraseImage(NSString *text,NSString *face,double requested,int width,int height,uint32_t ink,bool bold,bool italic,bool underline) {
    NSAttributedString *content=nil;NSRect measured=NSZeroRect;
    int maxWidth=std::max(16,width-32),maxHeight=std::max(16,height-10);
    for(double size=requested;size>=12;size-=1) {
        NSFont *font=[[NSFontManager sharedFontManager] fontWithFamily:face traits:0 weight:5 size:size];
        if(!font)font=[NSFont fontWithName:face size:size];
        if(!font)font=[NSFont systemFontOfSize:size];
        NSFontTraitMask traits=0;if(bold)traits|=NSBoldFontMask;if(italic)traits|=NSItalicFontMask;
        font=[[NSFontManager sharedFontManager] convertFont:font toHaveTrait:traits]?:font;
        auto *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;paragraph.lineBreakMode=NSLineBreakByWordWrapping;
        content=[[NSAttributedString alloc]initWithString:text attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color(ink),NSParagraphStyleAttributeName:paragraph,NSUnderlineStyleAttributeName:@(underline ? NSUnderlineStyleSingle : NSUnderlineStyleNone)}];
        measured=[content boundingRectWithSize:NSMakeSize(maxWidth,10000) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading];
        if(measured.size.height<=maxHeight||size<=12)break;
    }
    int w=std::clamp((int)std::ceil(measured.size.width)+16,16,maxWidth+16);
    int h=std::clamp((int)std::ceil(measured.size.height)+6,16,height);
    auto *image=bitmap(w,h);if(!image)return nil;
    memset(image.bitmapData,0,image.bytesPerRow*image.pixelsHigh);
    [NSGraphicsContext saveGraphicsState];
    auto *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:image];
    CGContextTranslateCTM(context.CGContext,0,h);CGContextScaleCTM(context.CGContext,1,-1);
    NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:context.CGContext flipped:YES];
    [content drawWithRect:NSMakeRect(8,3,w-16,h-6) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading context:nil];
    [NSGraphicsContext restoreGraphicsState];
    return image;
}
static void update(void *raw,obs_data_t *data) {@autoreleasepool {
    auto *s=(Source*)raw;
    NSMutableArray<NSBitmapImageRep*> *images=[NSMutableArray array];
    NSMutableArray<NSBitmapImageRep*> *phraseImages=[NSMutableArray array];
    uint32_t width=512,height=512;double textWidth=0;
    NSBitmapImageRep *back=nil;
    if(s->marquee) {
        width=(uint32_t)std::clamp<int64_t>(obs_data_get_int(data,"width"),320,7680);
        height=(uint32_t)std::clamp<int64_t>(obs_data_get_int(data,"height"),40,320);
        const char *rawText=obs_data_get_string(data,"text");
        NSString *text=strnlen(rawText,16385)<=16384?([NSString stringWithUTF8String:rawText]?:@""):@"";
        // Bound shaping and GPU allocation, preserving composed characters.
        __block NSUInteger end=0,count=0;
        [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString*,NSRange range,NSRange,BOOL *stop){end=NSMaxRange(range);if(++count==250)*stop=YES;}];
        text=[text substringToIndex:end];
        double size=obs_data_get_double(data,"fontSize");if(!std::isfinite(size))size=36;
        size=std::clamp(size,12.0,std::min(96.0,double(height)-16));
        NSString *face=[NSString stringWithUTF8String:obs_data_get_string(data,"font")]?:@"Helvetica Neue";
        NSFont *font=[[NSFontManager sharedFontManager] fontWithFamily:face traits:0 weight:5 size:size];
        if(!font)font=[NSFont fontWithName:face size:size];
        if(!font)font=[NSFont systemFontOfSize:size];
        NSFontDescriptorSymbolicTraits traits=0;
        if(obs_data_get_bool(data,"bold"))traits|=NSFontBoldTrait;
        if(obs_data_get_bool(data,"italic"))traits|=NSFontItalicTrait;
        font=[NSFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:traits] size:size]?:font;
        NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:color((uint32_t)obs_data_get_int(data,"ink")),NSUnderlineStyleAttributeName:@(obs_data_get_bool(data,"underline") ? NSUnderlineStyleSingle : NSUnderlineStyleNone)};
        if(obs_data_get_int(data,"displayMode")==1) {
            for(NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                NSString *phrase=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if(!phrase.length)continue;
                auto *image=phraseImage(phrase,face,size,width,height,(uint32_t)obs_data_get_int(data,"ink"),obs_data_get_bool(data,"bold"),obs_data_get_bool(data,"italic"),obs_data_get_bool(data,"underline"));
                if(image)[phraseImages addObject:image];
            }
        } else {
            text=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
            NSSize measured=[text sizeWithAttributes:attrs];
            textWidth=std::min(32768.0,std::ceil(measured.width)+16);
            double y=std::max(0.0,(double(height)-measured.height)/2);
            for(int x=0;x<(int)textWidth;x+=2048) {
                int w=std::min(2048,(int)textWidth-x);auto *b=bitmap(w,height);if(!b)break;
                memset(b.bitmapData,0,b.bytesPerRow*b.pixelsHigh);
                [NSGraphicsContext saveGraphicsState];
                auto *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:b];
                CGContextTranslateCTM(context.CGContext,0,height);CGContextScaleCTM(context.CGContext,1,-1);
                NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:context.CGContext flipped:YES];
                [text drawAtPoint:NSMakePoint(8-x,y) withAttributes:attrs];
                [NSGraphicsContext restoreGraphicsState];[images addObject:b];
            }
        }
        back=bandBackground(data,width,height);
    } else {
        const char *encoded=obs_data_get_string(data,"imagePNG");
        if(encoded && strlen(encoded)<=2*1024*1024) {
            NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[NSString stringWithUTF8String:encoded] options:0];
            // Only small generated PNGs. Reject oversized dimensions before decoding pixels.
            const uint8_t *png=(const uint8_t*)bytes.bytes;
            if(bytes.length>=24&&!memcmp(png,"\x89PNG\r\n\x1a\n",8)) {
                auto dimension=[&](int off){return (uint32_t(png[off])<<24)|(uint32_t(png[off+1])<<16)|(uint32_t(png[off+2])<<8)|png[off+3];};
                uint32_t w=dimension(16),h=dimension(20);
                if(w>=32&&w<=2048&&h==w) {
                    NSBitmapImageRep *decoded=[NSBitmapImageRep imageRepWithData:bytes];
                    if(decoded&&decoded.pixelsWide==w&&decoded.pixelsHigh==h){auto *b=bitmap(w,h);
                        CGContextDrawImage([NSGraphicsContext graphicsContextWithBitmapImageRep:b].CGContext,CGRectMake(0,0,w,h),decoded.CGImage);
                        [images addObject:b];width=w;height=h;}
                }
            }
        }
    }
    // Render callbacks already hold the graphics lock. No inverse mutex order.
    obs_enter_graphics();clear(s);s->width=width;s->height=height;s->textWidth=textWidth;
    double speed=obs_data_get_double(data,"speed");s->speed=std::isfinite(speed)?std::clamp(speed,0.0,500.0):90;
    double interval=obs_data_get_double(data,"phraseInterval");s->phraseInterval=std::isfinite(interval)?std::clamp(interval,1.0,30.0):5;
    s->phraseMode=s->marquee&&obs_data_get_int(data,"displayMode")==1;
    s->reverseScroll=obs_data_get_int(data,"scrollDirection")==1;
    s->slideDown=obs_data_get_int(data,"slideDirection")==1;
    s->started=os_gettime_ns();s->background=texture(back);
    uint32_t x=0;for(NSBitmapImageRep *image in images){auto *t=texture(image);if(t)s->tiles.push_back({t,x,(uint32_t)image.pixelsWide});x+=(uint32_t)image.pixelsWide;}
    for(NSBitmapImageRep *image in phraseImages){auto *t=texture(image);if(t)s->phrases.push_back({t,(uint32_t)image.pixelsWide,(uint32_t)image.pixelsHigh});}
    obs_leave_graphics();
}}
static void render(void *raw,gs_effect_t*) {
    auto *s=(Source*)raw;uint32_t w=s->width,h=s->height;
    auto *effect=obs_get_base_effect(OBS_EFFECT_DEFAULT);auto *param=gs_effect_get_param_by_name(effect,"image");
    gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);
    if(s->background){gs_effect_set_texture(param,s->background);while(gs_effect_loop(effect,"Draw"))gs_draw_sprite(s->background,0,w,h);}
    if(s->phraseMode) {
        if(!s->phrases.empty()) {
            double elapsed=double(os_gettime_ns()-s->started)/1e9;
            uint64_t cycle=(uint64_t)(elapsed/s->phraseInterval);
            double phase=std::fmod(elapsed,s->phraseInterval);
            double duration=std::min(0.45,s->phraseInterval*0.35);
            double progress=phase<duration ? 1-std::pow(1-phase/duration,3) : 1;
            int sign=s->slideDown ? -1 : 1;
            auto draw=[&](const Phrase &phrase,double offset) {
                int x=((int)w-(int)phrase.width)/2;
                int y=(int)std::lround(((int)h-(int)phrase.height)/2+offset);
                int from=std::max(0,-y),to=std::min((int)phrase.height,(int)h-y);
                if(to<=from)return;
                gs_matrix_push();gs_matrix_translate3f((float)x,(float)std::max(0,y),0);
                gs_effect_set_texture(param,phrase.texture);
                while(gs_effect_loop(effect,"Draw"))gs_draw_sprite_subregion(phrase.texture,0,0,from,phrase.width,to-from);
                gs_matrix_pop();
            };
            size_t index=(size_t)(cycle%s->phrases.size());
            if(cycle>0&&progress<1)draw(s->phrases[(index+s->phrases.size()-1)%s->phrases.size()],-sign*progress*h);
            draw(s->phrases[index],sign*(1-progress)*h);
        }
        gs_blend_state_pop();return;
    }
    double left=0;
    if(s->marquee) {
        double moved=std::fmod(double(os_gettime_ns()-s->started)/1e9*s->speed,w+s->textWidth+80);
        left=s->speed==0?24:(s->reverseScroll ? -s->textWidth+moved : double(w)-moved);
    }
    for(auto &tile:s->tiles) {
        int x=(int)std::floor(left+tile.x),start=std::max(0,-x),finish=std::min((int)tile.width,(int)w-x);
        if(finish<=start)continue;
        gs_matrix_push();gs_matrix_translate3f(float(std::max(0,x)),0,0);
        gs_effect_set_texture(param,tile.texture);
        while(gs_effect_loop(effect,"Draw"))gs_draw_sprite_subregion(tile.texture,0,start,0,finish-start,h);
        gs_matrix_pop();
    }
    gs_blend_state_pop();
}
static void registerSources() {
    for(bool marquee:{true,false}) {
        obs_source_info i={};i.id=marquee?"dante_marquee":"dante_qrcode";i.type=OBS_SOURCE_TYPE_INPUT;
        i.output_flags=OBS_SOURCE_VIDEO|OBS_SOURCE_CUSTOM_DRAW;
        i.get_name=marquee?+[](void*){return "Faixa de texto animada";}:+[](void*){return "QR Code";};
        i.create=[](obs_data_t *d,obs_source_t *source)->void*{auto *s=new Source;s->marquee=!strcmp(obs_source_get_unversioned_id(source),"dante_marquee");update(s,d);return s;};
        i.destroy=[](void *raw){auto *s=(Source*)raw;obs_enter_graphics();clear(s);obs_leave_graphics();delete s;};
        i.update=update;i.video_render=render;
        i.get_width=[](void *raw){return ((Source*)raw)->width.load();};i.get_height=[](void *raw){return ((Source*)raw)->height.load();};
        i.get_defaults=[](obs_data_t *d){
            obs_video_info v={};obs_get_video_info(&v);
            obs_data_set_default_int(d,"width",v.base_width?v.base_width:1920);obs_data_set_default_int(d,"height",80);
            obs_data_set_default_string(d,"text","Sua mensagem aqui • site, aviso ou cupom de desconto");
            obs_data_set_default_string(d,"font","Helvetica Neue");obs_data_set_default_double(d,"fontSize",36);
            obs_data_set_default_int(d,"ink",0xFFFFFF);obs_data_set_default_int(d,"background",0x142632);obs_data_set_default_double(d,"speed",90);
            obs_data_set_default_double(d,"backgroundOpacity",1);obs_data_set_default_int(d,"gradientEndColor",0x35B8C8);
            obs_data_set_default_double(d,"gradientEndOpacity",1);obs_data_set_default_int(d,"gradientAxis",0);
            obs_data_set_default_double(d,"gradientStart",0);obs_data_set_default_double(d,"gradientEndPosition",100);
            obs_data_set_default_double(d,"phraseInterval",5);
        };obs_register_source(&i);
    }
}
}
