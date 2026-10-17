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
struct Source {
    std::atomic<uint32_t> width{512},height{512};
    std::vector<Tile> tiles;
    gs_texture_t *background=nullptr;
    double textWidth=0,speed=90;
    uint64_t started=0;
    bool marquee=false;
};
static void clear(Source *s) {
    for(auto &tile:s->tiles)gs_texture_destroy(tile.texture);
    s->tiles.clear();gs_texture_destroy(s->background);s->background=nullptr;
}
static gs_texture_t *texture(NSBitmapImageRep *b) {
    if(!b)return nullptr;
    auto *t=gs_texture_create((uint32_t)b.pixelsWide,(uint32_t)b.pixelsHigh,GS_RGBA,1,nullptr,GS_DYNAMIC);
    if(t)gs_texture_set_image(t,b.bitmapData,(uint32_t)b.bytesPerRow,false);
    return t;
}
static void update(void *raw,obs_data_t *data) {@autoreleasepool {
    auto *s=(Source*)raw;
    NSMutableArray<NSBitmapImageRep*> *images=[NSMutableArray array];
    uint32_t width=512,height=512;double textWidth=0;
    NSBitmapImageRep *back=nil;
    if(s->marquee) {
        width=(uint32_t)std::clamp<int64_t>(obs_data_get_int(data,"width"),320,7680);
        height=(uint32_t)std::clamp<int64_t>(obs_data_get_int(data,"height"),40,320);
        const char *rawText=obs_data_get_string(data,"text");
        NSString *text=strnlen(rawText,16385)<=16384?([NSString stringWithUTF8String:rawText]?:@""):@"";
        text=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
        // Bound shaping and GPU allocation, preserving composed characters.
        __block NSUInteger end=0,count=0;
        [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString*,NSRange range,NSRange,BOOL *stop){end=NSMaxRange(range);if(++count==250)*stop=YES;}];
        text=[text substringToIndex:end];
        double size=obs_data_get_double(data,"fontSize");if(!std::isfinite(size))size=36;
        size=std::clamp(size,12.0,std::min(96.0,double(height)-16));
        NSString *face=[NSString stringWithUTF8String:obs_data_get_string(data,"font")]?:@"Helvetica Neue";
        NSFont *font=[NSFont fontWithName:face size:size]?:[NSFont systemFontOfSize:size];
        NSFontDescriptorSymbolicTraits traits=0;
        if(obs_data_get_bool(data,"bold"))traits|=NSFontBoldTrait;
        if(obs_data_get_bool(data,"italic"))traits|=NSFontItalicTrait;
        font=[NSFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:traits] size:size]?:font;
        NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:color((uint32_t)obs_data_get_int(data,"ink"))};
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
        back=bitmap(1,1);auto c=color((uint32_t)obs_data_get_int(data,"background"));
        back.bitmapData[0]=(uint8_t)lround(c.redComponent*255);back.bitmapData[1]=(uint8_t)lround(c.greenComponent*255);back.bitmapData[2]=(uint8_t)lround(c.blueComponent*255);back.bitmapData[3]=255;
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
    s->started=os_gettime_ns();s->background=texture(back);
    uint32_t x=0;for(NSBitmapImageRep *image in images){auto *t=texture(image);if(t)s->tiles.push_back({t,x,(uint32_t)image.pixelsWide});x+=(uint32_t)image.pixelsWide;}
    obs_leave_graphics();
}}
static void render(void *raw,gs_effect_t*) {
    auto *s=(Source*)raw;uint32_t w=s->width,h=s->height;
    auto *effect=obs_get_base_effect(OBS_EFFECT_DEFAULT);auto *param=gs_effect_get_param_by_name(effect,"image");
    gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);
    if(s->background){gs_effect_set_texture(param,s->background);while(gs_effect_loop(effect,"Draw"))gs_draw_sprite(s->background,0,w,h);}
    double left=0;
    if(s->marquee)left=s->speed==0?24:double(w)-std::fmod(double(os_gettime_ns()-s->started)/1e9*s->speed,w+s->textWidth+80);
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
        i.get_name=marquee?+[](void*){return "Faixa de texto rolante";}:+[](void*){return "QR Code";};
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
        };obs_register_source(&i);
    }
}
}
