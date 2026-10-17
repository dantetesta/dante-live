#pragma once
// Live inputs, like cameras: shared with the program snapshot. Only styles are
// persisted. No author/message data is ever put into obs_data or project JSON.
struct DanteChatTexture {
    gs_texture_t *texture=nullptr;
    uint32_t width=1100,height=420;
    std::atomic<uint64_t> started{0};
};
static void dante_register_chat_sources() {
    for (bool lower : {false,true}) {
        obs_source_info i={};i.id=lower?"dante_superchat":"dante_youtube_chat";
        i.type=OBS_SOURCE_TYPE_INPUT;i.output_flags=OBS_SOURCE_VIDEO|OBS_SOURCE_DO_NOT_DUPLICATE|OBS_SOURCE_CUSTOM_DRAW;
        i.get_name=lower?+[](void*){return "Destaque do YouTube";}:+[](void*){return "Chat do YouTube";};
        i.create=[](obs_data_t*,obs_source_t *source)->void* {
            auto *v=new DanteChatTexture;
            if(strcmp(obs_source_get_unversioned_id(source),"dante_youtube_chat")==0){v->width=480;v->height=720;}return v;
        };
        i.destroy=[](void *raw){auto *v=(DanteChatTexture*)raw;obs_enter_graphics();gs_texture_destroy(v->texture);obs_leave_graphics();delete v;};
        i.get_width=[](void *raw){return ((DanteChatTexture*)raw)->width;};
        i.get_height=[](void *raw){return ((DanteChatTexture*)raw)->height;};
        i.get_defaults=[](obs_data_t *d){obs_data_set_default_int(d,"style",0);obs_data_set_default_string(d,"font","Helvetica Neue");obs_data_set_default_double(d,"fontSize",30);};
        i.show=[](void *raw){((DanteChatTexture*)raw)->started=os_gettime_ns();};
        i.video_render=[](void *raw,gs_effect_t*) {
            auto *v=(DanteChatTexture*)raw;if(!v->texture)return;
            double t=std::min(1.0,double(os_gettime_ns()-v->started.load())/280000000.0),ease=1-std::pow(1-t,3);
            gs_blend_state_push();gs_blend_function(GS_BLEND_ONE,GS_BLEND_INVSRCALPHA);
            gs_matrix_push();gs_matrix_translate3f(0,float((1-ease)*32),0);
            auto *effect=obs_get_base_effect(OBS_EFFECT_DEFAULT);
            gs_effect_set_texture(gs_effect_get_param_by_name(effect,"image"),v->texture);
            while(gs_effect_loop(effect,"Draw"))gs_draw_sprite(v->texture,0,v->width,v->height);
            gs_matrix_pop();gs_blend_state_pop();
        };
        obs_register_source(&i);
    }
}
extern "C" bool dante_chat_frame(const char *name,const uint8_t *pixels,uint32_t w,uint32_t h,uint32_t stride,bool animate) {
    if(!name)return false;auto *s=obs_get_source_by_name(name);if(!s)return false;
    const char *type=obs_source_get_unversioned_id(s);
    if(strcmp(type,"dante_superchat")&&strcmp(type,"dante_youtube_chat")){obs_source_release(s);return false;}
    auto *v=(DanteChatTexture*)obs_obj_get_data(s);
    if(pixels&&(w!=v->width||h!=v->height||stride<w*4)){obs_source_release(s);return false;}
    obs_enter_graphics();
    if(!pixels){gs_texture_destroy(v->texture);v->texture=nullptr;}
    else {
        if(!v->texture)v->texture=gs_texture_create(w,h,GS_RGBA,1,nullptr,GS_DYNAMIC);
        if(v->texture)gs_texture_set_image(v->texture,pixels,stride,false);
        if(animate)v->started=os_gettime_ns();
    }
    bool ok=!pixels||v->texture;obs_leave_graphics();obs_source_release(s);return ok;
}
