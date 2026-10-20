#pragma once
#include <CoreText/CoreText.h>

// A separate scene item so the guest's name can move, hide and change style
// without modifying the camera or its active WebRTC connection.
namespace DanteGuestName {
struct Configuration {
    std::string name = "Convidado", font = "Helvetica Neue";
    uint32_t width = 520, height = 104, accent = 0x51D4DF, background = 0x121923, ink = 0xFFFFFF;
    int style = 0, fontSize = 48;
    bool bold = false, italic = false, underline = false;
};
struct Source {
    std::mutex mutex;
    Configuration config;
    std::vector<uint8_t> frame;
    uint32_t frameWidth=0, frameHeight=0;
    gs_texture_t *texture = nullptr;
    std::atomic<uint32_t> width{520}, height{104};
    std::atomic<bool> dirty{true};
};
static void color(CGContextRef context, uint32_t rgb, CGFloat opacity, bool stroke = false) {
    CGFloat values[] = {CGFloat((rgb >> 16) & 255) / 255, CGFloat((rgb >> 8) & 255) / 255,
        CGFloat(rgb & 255) / 255, opacity};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColorRef value = CGColorCreate(space, values); CGColorSpaceRelease(space);
    if (stroke) CGContextSetStrokeColorWithColor(context, value);
    else CGContextSetFillColorWithColor(context, value);
    CGColorRelease(value);
}
static void rounded(CGContextRef context, CGRect rect, CGFloat radius, bool fill) {
    CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, nullptr);
    CGContextAddPath(context, path);
    if (fill) CGContextFillPath(context); else CGContextStrokePath(context);
    CGPathRelease(path);
}
static void draw(CGContextRef context, const Configuration &v) {
    CGFloat w=v.width, h=v.height, margin=std::max<CGFloat>(5,h*0.055);
    CGRect card=CGRectMake(margin,margin,w-2*margin,h-2*margin);
    int style=std::clamp(v.style,0,5);
    if(style!=5) {
        CGFloat opacity = style==1 ? 0.66 : style==4 ? 0.92 : 0.88;
        color(context,style==4 ? v.accent : v.background,opacity);
        rounded(context,card,style==2 ? 7 : style==3 ? 2 : h*0.22,true);
    }
    if(style==0 || style==1 || style==2) {
        color(context,v.accent,1);
        CGFloat bar=std::max<CGFloat>(5,h*0.065);
        rounded(context,CGRectMake(margin,margin,bar,h-2*margin),bar/2,true);
    } else if(style==3) {
        color(context,v.accent,1);
        CGContextFillRect(context,CGRectMake(margin,margin,w-2*margin,std::max<CGFloat>(5,h*0.075)));
    } else if(style==5) {
        color(context,v.accent,1);CGContextFillRect(context,CGRectMake(margin,margin,w*0.11,std::max<CGFloat>(3,h*0.05)));
    }
    if(style==1 || style==2) {
        color(context,v.accent,style==1 ? 0.75 : 0.9,true);
        CGContextSetLineWidth(context,std::max<CGFloat>(1.5,h*0.018));rounded(context,card,style==2 ? 7 : h*0.22,false);
    }
    NSString *label=[NSString stringWithUTF8String:v.name.c_str()];
    if(!label || !label.length) label=@"Convidado";
    NSString *fontName=[NSString stringWithUTF8String:v.font.c_str()];
    if(!fontName.length)fontName=@"Helvetica Neue";
    CGFloat left=margin+(style<=2 ? h*0.20 : h*0.13), right=margin+h*0.13;
    if(style==5)left=margin;
    CGFloat available=std::max<CGFloat>(20,w-left-right);
    CGFloat size=std::min<CGFloat>(v.fontSize,h*0.58);
    CTFontRef font=nullptr;CTLineRef line=nullptr;
    for(int attempt=0;attempt<12;++attempt) {
        if(font)CFRelease(font);if(line)CFRelease(line);
        font=CTFontCreateWithName((__bridge CFStringRef)fontName,size,nullptr);
        if(!font)font=CTFontCreateWithName(CFSTR("Helvetica Neue"),size,nullptr);
        CTFontSymbolicTraits traits=(v.bold ? kCTFontBoldTrait : 0)|(v.italic ? kCTFontItalicTrait : 0);
        if(traits){CTFontRef styled=CTFontCreateCopyWithSymbolicTraits(font,size,nullptr,traits,traits);if(styled){CFRelease(font);font=styled;}}
        uint32_t ink=style==4 ? v.background : v.ink;
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGFloat values[]={CGFloat((ink>>16)&255)/255,CGFloat((ink>>8)&255)/255,CGFloat(ink&255)/255,1};
        CGColorRef textColor=CGColorCreate(space,values);CGColorSpaceRelease(space);
        NSDictionary *attributes=@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font,
                                    (__bridge NSString *)kCTForegroundColorAttributeName:(__bridge id)textColor,
                                    (__bridge NSString *)kCTUnderlineStyleAttributeName:@(v.underline ? kCTUnderlineStyleSingle : 0)};
        NSAttributedString *attributed=[[NSAttributedString alloc]initWithString:label attributes:attributes];
        line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
        CGColorRelease(textColor);
        if(CTLineGetTypographicBounds(line,nullptr,nullptr,nullptr)<=available || size<=13)break;
        size*=0.82;
    }
    if(line){
        CGContextSetTextMatrix(context,CGAffineTransformIdentity);
        CGContextSetTextPosition(context,left,(h-size)*0.5+size*0.13);
        CTLineDraw(line,context);CFRelease(line);
    }
    if(font)CFRelease(font);
}
static void update(void *raw,obs_data_t *data) {
    auto *s=static_cast<Source *>(raw);Configuration next;
    next.width=uint32_t(std::clamp<int64_t>(obs_data_get_int(data,"layoutWidth"),180,1600));
    next.height=uint32_t(std::clamp<int64_t>(obs_data_get_int(data,"layoutHeight"),55,320));
    next.name=obs_data_get_string(data,"guestName");
    next.font=obs_data_get_string(data,"fontFace");
    next.fontSize=int(std::clamp<int64_t>(obs_data_get_int(data,"fontSize"),18,120));
    next.bold=obs_data_get_bool(data,"guestNameBold");
    next.italic=obs_data_get_bool(data,"guestNameItalic");
    next.underline=obs_data_get_bool(data,"guestNameUnderline");
    next.style=int(std::clamp<int64_t>(obs_data_get_int(data,"style"),0,5));
    next.accent=uint32_t(obs_data_get_int(data,"accent"))&0xFFFFFF;
    next.background=uint32_t(obs_data_get_int(data,"background"))&0xFFFFFF;
    next.ink=uint32_t(obs_data_get_int(data,"ink"))&0xFFFFFF;
    {std::lock_guard<std::mutex> lock(s->mutex);s->config=next;}
    s->width=next.width;s->height=next.height;s->dirty=true;
}
static void tick(void *raw,float) {
    auto *s=static_cast<Source *>(raw);if(!s->dirty.exchange(false))return;
    Configuration v;{std::lock_guard<std::mutex> lock(s->mutex);v=s->config;}
    std::vector<uint8_t> pixels(size_t(v.width)*v.height*4,0);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels.data(),v.width,v.height,8,v.width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);if(!context)return;
    draw(context,v);CGContextRelease(context);
    {std::lock_guard<std::mutex> lock(s->mutex);s->frame.swap(pixels);s->frameWidth=v.width;s->frameHeight=v.height;}
}
static void render(void *raw,gs_effect_t *) {
    auto *s=static_cast<Source *>(raw);
    std::lock_guard<std::mutex> lock(s->mutex);
    if(!s->frame.empty()) {
        if(!s->texture || gs_texture_get_width(s->texture)!=s->frameWidth || gs_texture_get_height(s->texture)!=s->frameHeight) {
            gs_texture_destroy(s->texture);s->texture=gs_texture_create(s->frameWidth,s->frameHeight,GS_RGBA,1,nullptr,GS_DYNAMIC);
        }
        if(s->texture)gs_texture_set_image(s->texture,s->frame.data(),s->frameWidth*4,false);
        s->frame.clear();
    }
    if(!s->texture)return;
    auto *effect=obs_get_base_effect(OBS_EFFECT_DEFAULT);
    gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);
    gs_effect_set_texture(gs_effect_get_param_by_name(effect,"image"),s->texture);
    while(gs_effect_loop(effect,"Draw"))gs_draw_sprite(s->texture,0,s->width,s->height);
    gs_blend_state_pop();
}
static void registerSource(){
    obs_source_info i={};i.id="dante_guest_name";i.type=OBS_SOURCE_TYPE_INPUT;
    i.output_flags=OBS_SOURCE_VIDEO|OBS_SOURCE_CUSTOM_DRAW|OBS_SOURCE_DO_NOT_DUPLICATE;
    i.get_name=[](void*){return "Nome do convidado";};
    i.create=[](obs_data_t *data,obs_source_t*)->void*{auto *s=new Source;update(s,data);return s;};
    i.destroy=[](void *raw){auto *s=static_cast<Source*>(raw);obs_enter_graphics();gs_texture_destroy(s->texture);obs_leave_graphics();delete s;};
    i.update=update;i.video_tick=tick;i.video_render=render;
    i.get_width=[](void *raw){return static_cast<Source*>(raw)->width.load();};
    i.get_height=[](void *raw){return static_cast<Source*>(raw)->height.load();};
    i.get_defaults=[](obs_data_t *data){obs_data_set_default_int(data,"layoutWidth",520);obs_data_set_default_int(data,"layoutHeight",104);obs_data_set_default_int(data,"style",0);obs_data_set_default_int(data,"fontSize",48);obs_data_set_default_int(data,"accent",0x51D4DF);obs_data_set_default_int(data,"background",0x121923);obs_data_set_default_int(data,"ink",0xFFFFFF);obs_data_set_default_string(data,"fontFace","Helvetica Neue");obs_data_set_default_string(data,"guestName","Convidado");};
    obs_register_source(&i);
}
}
