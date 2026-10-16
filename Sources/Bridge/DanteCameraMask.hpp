#pragma once
#include <obs.h>
#include <graphics/graphics.h>
#include <graphics/vec2.h>
#include <atomic>
#include <algorithm>
#include <cmath>

// One native OBS filter: the same GPU composition feeds preview and live output.
// OBS effect syntax is translated by the active Metal/OpenGL backend.
namespace DanteMask {
static constexpr const char *type = "dante_camera_mask";
static thread_local bool creationSucceeded=false;
static const char *shader = R"(
uniform float4x4 ViewProj;
uniform texture2d image;
uniform float2 uvScale;
uniform float2 uvOffset;
uniform float2 outputSize;
uniform float radius;
uniform float ellipse;
sampler_state sampleImage { Filter = Linear; AddressU = Clamp; AddressV = Clamp; };
struct Vertex { float4 pos : POSITION; float2 uv : TEXCOORD0; };
Vertex VSDefault(Vertex v_in) { Vertex o; o.pos = mul(float4(v_in.pos.xyz,1.0),ViewProj); o.uv=v_in.uv; return o; }
float4 PSMask(Vertex v_in) : TARGET {
    float alpha=1.0;
    if(ellipse>0.5) {
        float distance=length((v_in.uv-0.5)*2.0);
        alpha=saturate((1.0-distance)*min(outputSize.x,outputSize.y)*0.5);
    } else if(radius>0.0) {
        float2 q=abs((v_in.uv-0.5)*outputSize)-(outputSize*0.5-radius);
        float distance=length(max(q,0.0))+min(max(q.x,q.y),0.0)-radius;
        alpha=saturate(0.5-distance);
    }
    return image.Sample(sampleImage,v_in.uv*uvScale+uvOffset)*alpha;
}
technique Draw { pass { vertex_shader=VSDefault(v_in); pixel_shader=PSMask(v_in); } }
)";
struct Filter {
    obs_source_t *source=nullptr;
    gs_effect_t *effect=nullptr;
    gs_eparam_t *uvScale=nullptr,*uvOffset=nullptr,*outputSize=nullptr,*radiusParam=nullptr,*ellipseParam=nullptr;
    std::atomic<int> shape{0};
    std::atomic<float> aspect{16.f/9.f},zoom{1.f},panX{0.f},panY{0.f},roundness{.2f};
};
struct Frame { uint32_t width=0,height=0; vec2 scale={1,1},offset={0,0}; float radius=0,ellipse=0; };
static float bounded(obs_data_t *settings,const char *key,float low,float high,float fallback) {
    const double value=obs_data_get_double(settings,key);
    return std::isfinite(value) ? std::clamp(float(value),low,high) : fallback;
}
static void update(void *raw,obs_data_t *settings) {
    auto *f=static_cast<Filter*>(raw);
    f->shape.store(int(std::clamp(obs_data_get_int(settings,"shape"),0LL,6LL)));
    f->aspect.store(bounded(settings,"aspect",.25f,4.f,16.f/9.f));
    f->zoom.store(bounded(settings,"zoom",1.f,4.f,1.f));
    f->panX.store(bounded(settings,"panX",-1.f,1.f,0.f));f->panY.store(bounded(settings,"panY",-1.f,1.f,0.f));
    f->roundness.store(bounded(settings,"roundness",0.f,1.f,.2f));
}
static Frame frame(Filter *f) {
    Frame result;auto *target=obs_filter_get_target(f->source);if(!target)return result;
    const float width=obs_source_get_base_width(target),height=obs_source_get_base_height(target);
    if(width<1||height<1)return result;
    const int shape=f->shape.load();
    const float ratio=shape==0 ? width/height : (shape==1||shape==3||shape==4) ? 1.f : f->aspect.load();
    result.width=uint32_t(std::max(1.f,std::floor(std::min(width,height*ratio))));
    result.height=uint32_t(std::max(1.f,std::floor(std::min(height,width/ratio))));
    const float zoom=shape==0 ? 1.f : f->zoom.load();
    result.scale={result.width/width/zoom,result.height/height/zoom};
    result.offset={(1-result.scale.x)*(1+f->panX.load())*.5f,(1-result.scale.y)*(1+f->panY.load())*.5f};
    result.ellipse=(shape==2||shape==3) ? 1.f : 0.f;
    result.radius=(shape==4||shape==6) ? std::min(result.width,result.height)*.5f*f->roundness.load() : 0.f;
    return result;
}
static void defaults(obs_data_t *s) {
    obs_data_set_default_int(s,"shape",0);obs_data_set_default_double(s,"aspect",16.0/9.0);
    obs_data_set_default_double(s,"zoom",1);obs_data_set_default_double(s,"panX",0);obs_data_set_default_double(s,"panY",0);
    obs_data_set_default_double(s,"roundness",.2);
}
static void *create(obs_data_t *settings,obs_source_t *source) {
    creationSucceeded=false;auto *f=new Filter;f->source=source;
    obs_enter_graphics();f->effect=gs_effect_create(shader,"dante-camera-mask.effect",nullptr);obs_leave_graphics();
    if(!f->effect){delete f;return nullptr;}
    f->uvScale=gs_effect_get_param_by_name(f->effect,"uvScale");f->uvOffset=gs_effect_get_param_by_name(f->effect,"uvOffset");
    f->outputSize=gs_effect_get_param_by_name(f->effect,"outputSize");f->radiusParam=gs_effect_get_param_by_name(f->effect,"radius");f->ellipseParam=gs_effect_get_param_by_name(f->effect,"ellipse");
    update(f,settings);creationSucceeded=true;return f;
}
static void destroy(void *raw) { auto *f=static_cast<Filter*>(raw);obs_enter_graphics();gs_effect_destroy(f->effect);obs_leave_graphics();delete f; }
static void render(void *raw,gs_effect_t*) {
    auto *f=static_cast<Filter*>(raw);const auto value=frame(f);
    if(!value.width||!value.height){obs_source_skip_video_filter(f->source);return;}
    if(!obs_source_process_filter_begin(f->source,GS_RGBA,OBS_NO_DIRECT_RENDERING))return;
    vec2 size={float(value.width),float(value.height)};
    gs_effect_set_vec2(f->uvScale,&value.scale);gs_effect_set_vec2(f->uvOffset,&value.offset);gs_effect_set_vec2(f->outputSize,&size);
    gs_effect_set_float(f->radiusParam,value.radius);gs_effect_set_float(f->ellipseParam,value.ellipse);
    gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);
    obs_source_process_filter_end(f->source,f->effect,value.width,value.height);gs_blend_state_pop();
}
static obs_properties_t *properties(void*) {
    auto *props=obs_properties_create();auto *shape=obs_properties_add_list(props,"shape","Formato",OBS_COMBO_TYPE_LIST,OBS_COMBO_FORMAT_INT);
    const char *names[]={"Nativo","Quadrado","Oval","Redondo","Quadrado arredondado","Retângulo","Retângulo arredondado"};
    for(int i=0;i<7;i++)obs_property_list_add_int(shape,names[i],i);
    obs_properties_add_float_slider(props,"aspect","Proporção largura/altura",.25,4,.01);
    obs_properties_add_float_slider(props,"roundness","Arredondamento",0,1,.01);
    obs_properties_add_float_slider(props,"zoom","Zoom",1,4,.01);
    obs_properties_add_float_slider(props,"panX","Enquadramento horizontal",-1,1,.01);
    obs_properties_add_float_slider(props,"panY","Enquadramento vertical",-1,1,.01);
    return props;
}
static void registerFilter() {
    obs_source_info info={};info.id=type;info.type=OBS_SOURCE_TYPE_FILTER;info.output_flags=OBS_SOURCE_VIDEO|OBS_SOURCE_SRGB;
    info.get_name=[](void*){return "Formato e enquadramento da câmera";};info.create=create;info.destroy=destroy;info.update=update;
    info.get_defaults=defaults;info.get_properties=properties;info.video_render=render;
    info.get_width=[](void *raw){return frame(static_cast<Filter*>(raw)).width;};info.get_height=[](void *raw){return frame(static_cast<Filter*>(raw)).height;};
    obs_register_source(&info);
}
static obs_source_t *find(obs_source_t *source) {
    obs_source_t *result=nullptr;
    obs_source_enum_filters(source,[](obs_source_t*,obs_source_t *filter,void *raw){
        auto **result=static_cast<obs_source_t**>(raw);
        if(!*result&&strcmp(obs_source_get_id(filter),type)==0)*result=obs_source_get_ref(filter);
    },&result);
    return result;
}
}
