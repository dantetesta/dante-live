#pragma once
#include <array>
#include <complex>

// A video-only OBS source. It reads a selected source's PCM through libobs's
// capture callback; it never changes that source's audio or monitors it.
namespace DanteVisualizer {
constexpr int fftSize = 1024, bandCount = 48, waveCount = 128;
struct Configuration {
    uint32_t width = 900, height = 280, primary = 0x48D8E8, secondary = 0x986BFF;
    int style = 0;
    float sensitivity = 1.0f;
    std::string uuid, name;
};
struct Source {
    std::mutex configMutex, samplesMutex, frameMutex, bindingMutex;
    Configuration config;
    obs_source_t *bound = nullptr;
    float samples[2048] = {};
    size_t writeAt = 0, available = 0;
    std::array<float, bandCount> smooth{};
    std::vector<uint8_t> frame;
    uint32_t frameWidth = 0, frameHeight = 0;
    uint64_t lastAudio = 0, lastBindAttempt = 0;
    std::atomic<uint64_t> lastFrame{0};
    gs_texture_t *texture = nullptr;
    std::atomic<uint32_t> width{900}, height{280};
    std::atomic<bool> fresh{false};
};
static float finite(float n) { return std::isfinite(n) ? std::clamp(n, -1.0f, 1.0f) : 0.0f; }
static void audio(void *raw, obs_source_t *, const audio_data *data, bool muted) {
    auto *s = static_cast<Source *>(raw);
    if (!data || !data->frames || !data->data[0]) return;
    const float *left = reinterpret_cast<const float *>(data->data[0]);
    const float *right = data->data[1] ? reinterpret_cast<const float *>(data->data[1]) : nullptr;
    std::lock_guard<std::mutex> lock(s->samplesMutex);
    const uint32_t begin = data->frames > 2048 ? data->frames - 2048 : 0;
    for (uint32_t i = begin; i < data->frames; ++i) {
        s->samples[s->writeAt] = muted ? 0.0f : finite(right ? (left[i] + right[i]) * 0.5f : left[i]);
        s->writeAt = (s->writeAt + 1) % 2048;
    }
    s->available = std::min<size_t>(2048, s->available + data->frames - begin);
    s->lastAudio = os_gettime_ns();
}
static void bind(Source *s, const Configuration &config) {
    std::lock_guard<std::mutex> lock(s->bindingMutex);
    obs_source_t *wanted = nullptr;
    if (!config.uuid.empty()) wanted = obs_get_source_by_uuid(config.uuid.c_str());
    else if (!config.name.empty()) wanted = obs_get_source_by_name(config.name.c_str());
    if (wanted && (!(obs_source_get_output_flags(wanted) & OBS_SOURCE_AUDIO) ||
        !strcmp(obs_source_get_unversioned_id(wanted), "dante_audio_visualizer"))) {
        obs_source_release(wanted); wanted = nullptr;
    }
    if (wanted == s->bound) { obs_source_release(wanted); return; }
    if (s->bound) {
        obs_source_remove_audio_capture_callback(s->bound, audio, s);
        obs_source_release(s->bound);
    }
    s->bound = wanted;
    {
        std::lock_guard<std::mutex> sampleLock(s->samplesMutex);
        std::fill(std::begin(s->samples), std::end(s->samples), 0.0f);
        s->writeAt = s->available = 0; s->lastAudio = 0;
    }
    if (wanted) obs_source_add_audio_capture_callback(wanted, audio, s);
}
static void fft(std::array<std::complex<float>, fftSize> &values) {
    for (int i = 1, j = 0; i < fftSize; ++i) {
        int bit = fftSize >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(values[i], values[j]);
    }
    for (int length = 2; length <= fftSize; length <<= 1) {
        const float angle = -2.0f * float(M_PI) / float(length);
        const std::complex<float> step(std::cos(angle), std::sin(angle));
        for (int base = 0; base < fftSize; base += length) {
            std::complex<float> unit(1, 0);
            for (int k = 0; k < length / 2; ++k) {
                auto a = values[base + k], b = values[base + k + length / 2] * unit;
                values[base + k] = a + b; values[base + k + length / 2] = a - b;
                unit *= step;
            }
        }
    }
}
static void analyze(Source *s, const Configuration &config, float *wave, float *bands) {
    std::array<float, fftSize> input{};
    {
        std::lock_guard<std::mutex> lock(s->samplesMutex);
        const size_t count = std::min<size_t>(fftSize, s->available);
        for (size_t i = 0; i < count; ++i)
            input[fftSize - count + i] = s->samples[(s->writeAt + 2048 - count + i) % 2048];
        if (!s->lastAudio || os_gettime_ns() - s->lastAudio > 300000000ULL) input.fill(0);
    }
    std::array<std::complex<float>, fftSize> spectrum;
    for (int i = 0; i < fftSize; ++i) {
        float window = 0.5f - 0.5f * std::cos(2.0f * float(M_PI) * i / (fftSize - 1));
        spectrum[i] = {input[i] * window, 0};
    }
    fft(spectrum);
    for (int b = 0; b < bandCount; ++b) {
        int first = std::clamp(int(std::exp(std::log(2.0) + double(b) / bandCount * std::log(480.0 / 2.0))), 2, 479);
        int last = std::clamp(int(std::exp(std::log(2.0) + double(b + 1) / bandCount * std::log(480.0 / 2.0))), first + 1, 480);
        float power = 0;
        for (int bin = first; bin < last; ++bin) power = std::max(power, std::abs(spectrum[bin]));
        float amplitude = power * (4.0f / fftSize);
        float level = std::clamp(std::sqrt(std::max(0.0f, amplitude * config.sensitivity - 0.0025f)) * 1.65f, 0.0f, 1.0f);
        s->smooth[b] += (level - s->smooth[b]) * (level > s->smooth[b] ? 0.55f : 0.16f);
        bands[b] = s->smooth[b];
    }
    for (int i = 0; i < waveCount; ++i) wave[i] = std::clamp(input[i * fftSize / waveCount] * config.sensitivity, -1.0f, 1.0f);
}
static CGColorRef rgba(uint32_t rgb, CGFloat alpha) {
    CGFloat values[] = {CGFloat((rgb >> 16) & 255) / 255, CGFloat((rgb >> 8) & 255) / 255,
                        CGFloat(rgb & 255) / 255, alpha};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColorRef color = CGColorCreate(space, values);
    CGColorSpaceRelease(space);
    return color;
}
static void stroke(CGContextRef c, uint32_t color, CGFloat alpha, CGFloat width) {
    CGColorRef ink = rgba(color, alpha); CGContextSetStrokeColorWithColor(c, ink); CGColorRelease(ink);
    CGContextSetLineWidth(c, width); CGContextSetLineCap(c, kCGLineCapRound); CGContextSetLineJoin(c, kCGLineJoinRound);
}
static void fill(CGContextRef c, uint32_t color, CGFloat alpha) {
    CGColorRef ink = rgba(color, alpha); CGContextSetFillColorWithColor(c, ink); CGColorRelease(ink);
}
static void line(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextMoveToPoint(c, x1, y1); CGContextAddLineToPoint(c, x2, y2); CGContextStrokePath(c);
}
static void ellipse(CGContextRef c, CGFloat x, CGFloat y, CGFloat r) { CGContextFillEllipseInRect(c, CGRectMake(x-r, y-r, r*2, r*2)); }
static void rounded(CGContextRef c, CGRect rect, CGFloat radius) {
    CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, nullptr);
    CGContextAddPath(c, path); CGContextFillPath(c); CGPathRelease(path);
}
static void draw(CGContextRef c, const Configuration &config, const float *wave, const float *bands) {
    const CGFloat w = config.width, h = config.height, mid = h * 0.5;
    CGContextClearRect(c, CGRectMake(0, 0, w, h));
    const int style = config.style;
    const CGFloat inset = std::max<CGFloat>(10, std::min(w, h) * 0.055);
    if (style == 0 || style == 6) { // continuous wave / translucent ribbon
        const CGFloat amplitude = h * 0.38;
        if (style == 6) { fill(c, config.primary, 0.18); CGContextBeginPath(c); CGContextMoveToPoint(c, inset, mid); }
        else { stroke(c, config.primary, 0.20, 9); CGContextBeginPath(c); }
        for (int i = 0; i < waveCount; ++i) {
            CGFloat x = inset + (w - 2*inset) * i / (waveCount - 1), y = mid + wave[i] * amplitude;
            if (style == 6) CGContextAddLineToPoint(c, x, y);
            else if (i == 0) CGContextMoveToPoint(c, x, y); else CGContextAddLineToPoint(c, x, y);
        }
        if (style == 6) { CGContextAddLineToPoint(c, w-inset, mid); CGContextClosePath(c); CGContextFillPath(c); }
        else CGContextStrokePath(c);
        stroke(c, config.primary, 0.92, std::max<CGFloat>(2.5, h*0.014)); CGContextBeginPath(c);
        for (int i = 0; i < waveCount; ++i) {
            CGFloat x = inset + (w - 2*inset)*i/(waveCount-1), y = mid + wave[i]*amplitude;
            if (!i) CGContextMoveToPoint(c,x,y); else CGContextAddLineToPoint(c,x,y);
        }
        CGContextStrokePath(c);
        if (style == 6) { stroke(c, config.secondary, 0.55, 1.5); line(c,inset,mid,w-inset,mid); }
    } else if (style == 1 || style == 2 || style == 3) { // bars / mirror / capsules
        const CGFloat slot = (w - 2*inset)/bandCount, bar = std::max<CGFloat>(2, slot*0.55);
        stroke(c, config.secondary, 0.18, 1); line(c,inset,mid,w-inset,mid);
        for (int i = 0; i < bandCount; ++i) {
            CGFloat x = inset + i*slot + (slot-bar)/2, level = bands[i];
            CGFloat length = std::max<CGFloat>(2, level * (style==2 ? h*0.38 : h*0.76));
            fill(c, i%4==0 ? config.secondary : config.primary, 0.35 + level*0.6);
            if (style == 2) {
                rounded(c,CGRectMake(x,mid+3,bar,length),bar/2); rounded(c,CGRectMake(x,mid-3-length,bar,length),bar/2);
            } else if (style == 3) {
                int steps = 8; CGFloat step = (h-2*inset)/steps;
                for(int j=0;j<steps && j<1+int(level*steps);++j) rounded(c,CGRectMake(x,inset+j*step,bar,step*0.62),bar/2);
            } else rounded(c,CGRectMake(x,inset,bar,length),bar/2);
        }
    } else if (style == 4 || style == 5 || style == 9) { // orbit / halo / perspective tunnel
        CGFloat cx=w/2, cy=h/2, base=std::max<CGFloat>(8,std::min(w*0.32,h*0.31));
        if (style == 9) {
            CGFloat energy=0;
            for(int i=0;i<bandCount;++i)energy=std::max<CGFloat>(energy,bands[i]);
            const CGFloat beat=energy*base*0.21;
            for(int layer=5;layer>=0;--layer) {
                CGFloat scale=0.25+layer*0.16, radius=(base+beat)*scale;
                CGFloat offset=(5-layer)*base*0.09;
                stroke(c,layer%2?config.primary:config.secondary,0.12+0.10*layer+energy*0.10,1.4+layer*0.3);
                CGContextStrokeEllipseInRect(c,CGRectMake(cx-radius+offset,cy-radius*0.75-offset*0.38,radius*2,radius*1.5));
                if(layer>0) {
                    stroke(c,config.secondary,0.10+energy*0.30,1);
                    for(int spoke=0;spoke<8;++spoke){CGFloat angle=spoke*M_PI/4;
                        CGFloat next=(base+beat)*(scale-0.16);
                        line(c,cx+offset+std::cos(angle)*radius,cy-offset*0.38+std::sin(angle)*radius*0.75,
                             cx+offset+base*0.09+std::cos(angle)*next,cy-(offset+base*0.09)*0.38+std::sin(angle)*next*0.75);
                    }
                }
            }
        } else {
            stroke(c,config.secondary,0.25,1.5); CGContextStrokeEllipseInRect(c,CGRectMake(cx-base,cy-base,base*2,base*2));
            for(int i=0;i<bandCount;++i) {
                CGFloat angle=(CGFloat(i)/bandCount)*2*M_PI-M_PI_2, depth=bands[i]*std::min(w,h)*0.25;
                CGFloat x1=cx+std::cos(angle)*(base+3), y1=cy+std::sin(angle)*(base+3);
                if(style==4) { stroke(c,i%4?config.primary:config.secondary,0.35+bands[i]*0.65,2.2); line(c,x1,y1,cx+std::cos(angle)*(base+5+depth),cy+std::sin(angle)*(base+5+depth)); }
                else {fill(c,i%4?config.primary:config.secondary,0.35+bands[i]*0.65); ellipse(c,cx+std::cos(angle)*(base+depth),cy+std::sin(angle)*(base+depth),2.5+bands[i]*4);}
            }
        }
    } else if (style == 7) { // spectral particles
        for(int i=0;i<bandCount;++i) {
            CGFloat x=inset+(w-2*inset)*(i+0.5)/bandCount;
            int dots=1+int(bands[i]*8);
            for(int j=0;j<dots;++j){fill(c,j%3?config.primary:config.secondary,0.26+0.65*(1.0-j/10.0));ellipse(c,x,inset+j*(h-2*inset)/9,1.6+bands[i]*2.2);}
        }
    } else if (style == 8) { // isometric columns, shaded faces
        const int columns=24; CGFloat slot=(w-2*inset)/columns, depth=std::min(slot*0.28,h*0.08);
        for(int i=0;i<columns;++i) {
            CGFloat x=inset+i*slot+slot*0.12, y=inset+i%2*depth*0.35;
            CGFloat tall=std::max<CGFloat>(3,bands[i*2]*h*0.72), bw=slot*0.58;
            fill(c,config.primary,0.30+bands[i*2]*0.6);CGContextFillRect(c,CGRectMake(x,y,bw,tall));
            fill(c,config.secondary,0.35+bands[i*2]*0.5);CGContextBeginPath(c);CGContextMoveToPoint(c,x+bw,y);CGContextAddLineToPoint(c,x+bw+depth,y+depth);CGContextAddLineToPoint(c,x+bw+depth,y+tall+depth);CGContextAddLineToPoint(c,x+bw,y+tall);CGContextClosePath(c);CGContextFillPath(c);
            fill(c,config.primary,0.85);CGContextBeginPath(c);CGContextMoveToPoint(c,x,y+tall);CGContextAddLineToPoint(c,x+depth,y+tall+depth);CGContextAddLineToPoint(c,x+bw+depth,y+tall+depth);CGContextAddLineToPoint(c,x+bw,y+tall);CGContextClosePath(c);CGContextFillPath(c);
        }
    }
}
static void tick(void *raw, float) {
    auto *s = static_cast<Source *>(raw);
    uint64_t now = os_gettime_ns();
    if (now - s->lastFrame.load() < 33333333ULL) return;
    s->lastFrame = now;
    Configuration config;
    { std::lock_guard<std::mutex> lock(s->configMutex); config = s->config; }
    if (now - s->lastBindAttempt > 1000000000ULL) {
        s->lastBindAttempt = now;
        bool missing;
        {std::lock_guard<std::mutex> lock(s->bindingMutex);missing=!s->bound;}
        if (missing) bind(s, config);
    }
    float wave[waveCount], bands[bandCount]; analyze(s, config, wave, bands);
    const size_t stride = size_t(config.width)*4;
    std::vector<uint8_t> pixels(stride*config.height, 0);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels.data(),config.width,config.height,8,stride,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if(!context)return;
    draw(context,config,wave,bands);CGContextRelease(context);
    {std::lock_guard<std::mutex> lock(s->frameMutex);s->frame.swap(pixels);s->frameWidth=config.width;s->frameHeight=config.height;s->fresh=true;}
}
static void render(void *raw, gs_effect_t *) {
    auto *s=static_cast<Source *>(raw);
    if (s->fresh.load()) {
        std::lock_guard<std::mutex> lock(s->frameMutex);
        if(s->fresh.exchange(false)) {
            if(!s->texture || gs_texture_get_width(s->texture)!=s->frameWidth || gs_texture_get_height(s->texture)!=s->frameHeight) {
                gs_texture_destroy(s->texture);s->texture=gs_texture_create(s->frameWidth,s->frameHeight,GS_RGBA,1,nullptr,GS_DYNAMIC);
            }
            if(s->texture)gs_texture_set_image(s->texture,s->frame.data(),s->frameWidth*4,false);
        }
    }
    if (!s->texture) return;
    auto *effect=obs_get_base_effect(OBS_EFFECT_DEFAULT);
    gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);
    gs_effect_set_texture(gs_effect_get_param_by_name(effect,"image"),s->texture);
    while(gs_effect_loop(effect,"Draw"))gs_draw_sprite(s->texture,0,s->width,s->height);
    gs_blend_state_pop();
}
static void update(void *raw, obs_data_t *data) {
    auto *s=static_cast<Source *>(raw);
    Configuration next;
    next.width=uint32_t(std::clamp<int64_t>(obs_data_get_int(data,"layoutWidth"),240,1920));
    next.height=uint32_t(std::clamp<int64_t>(obs_data_get_int(data,"layoutHeight"),80,1080));
    next.style=int(std::clamp<int64_t>(obs_data_get_int(data,"style"),0,9));
    next.primary=uint32_t(obs_data_get_int(data,"primary"))&0xFFFFFF;
    next.secondary=uint32_t(obs_data_get_int(data,"secondary"))&0xFFFFFF;
    double sensitivity=obs_data_get_double(data,"sensitivity");
    next.sensitivity=std::isfinite(sensitivity)?float(std::clamp(sensitivity,0.25,4.0)):1.0f;
    next.uuid=obs_data_get_string(data,"audioSourceUUID");next.name=obs_data_get_string(data,"audioSourceName");
    Configuration previous;
    {std::lock_guard<std::mutex> lock(s->configMutex);previous=s->config;s->config=next;}
    s->width=next.width;s->height=next.height;
    if(previous.uuid!=next.uuid || previous.name!=next.name)bind(s,next);
    s->lastFrame=0;
}
static void registerSource() {
    obs_source_info i={};i.id="dante_audio_visualizer";i.type=OBS_SOURCE_TYPE_INPUT;
    i.output_flags=OBS_SOURCE_VIDEO|OBS_SOURCE_CUSTOM_DRAW|OBS_SOURCE_DO_NOT_DUPLICATE;
    i.get_name=[](void*){return "Visualizador de áudio";};
    i.create=[](obs_data_t *data,obs_source_t*)->void*{auto *s=new Source;update(s,data);return s;};
    i.destroy=[](void *raw){auto *s=static_cast<Source *>(raw);Configuration empty;bind(s,empty);obs_enter_graphics();gs_texture_destroy(s->texture);obs_leave_graphics();delete s;};
    i.update=update;i.video_tick=tick;i.video_render=render;
    i.get_width=[](void *raw){return static_cast<Source *>(raw)->width.load();};
    i.get_height=[](void *raw){return static_cast<Source *>(raw)->height.load();};
    i.get_defaults=[](obs_data_t *data){obs_data_set_default_int(data,"layoutWidth",900);obs_data_set_default_int(data,"layoutHeight",280);obs_data_set_default_int(data,"style",0);obs_data_set_default_int(data,"primary",0x48D8E8);obs_data_set_default_int(data,"secondary",0x986BFF);obs_data_set_default_double(data,"sensitivity",1.0);};
    obs_register_source(&i);
}
}
