#import <AppKit/AppKit.h>
#import <VideoToolbox/VideoToolbox.h>
#include "DanteEngine.h"
#include <obs.h>
#include <obs-audio-controls.h>
#include <graphics/vec2.h>
#include <graphics/matrix4.h>
#include <graphics/graphics.h>
#include <util/base.h>
#include <util/platform.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

static std::string creationError;
static NSString *S(const char *s) { return s ? [NSString stringWithUTF8String:s] ?: @"" : @""; }
static std::string J(id value) {
    if (!value || ![NSJSONSerialization isValidJSONObject:value]) return "{}";
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return data ? std::string((const char *)data.bytes, data.length) : "{}";
}
static id parse(const char *json) {
    if (!json) return nil;
    NSData *data = [S(json) dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
}
static obs_data_t *settings(id object) { auto json = J(object ?: @{}); return obs_data_create_from_json(json.c_str()); }
static id jsonSettings(obs_data_t *data) { return data ? parse(obs_data_get_json_with_defaults(data)) ?: @{} : @{}; }
static std::mutex hardwareLogMutex;
static std::map<std::string,bool> hardwareSessions;
static void privateLog(int, const char *format, va_list args, void *) {
    // Read only this fixed engine event. Never format or persist arbitrary log payloads,
    // which may contain authenticated streaming URLs or source properties.
    if (format && strstr(format,"session created with hardware encoding")) {
        va_list copy;va_copy(copy,args);const char *name=va_arg(copy,const char*);va_end(copy);
        if(name){std::lock_guard<std::mutex> lock(hardwareLogMutex);hardwareSessions[name]=true;}
    }
}
static bool hardwareEncoder(const char *id) {
    CFArrayRef values=nullptr;if(VTCopyVideoEncoderList(nullptr,&values)!=noErr || !values)return false;
    bool hardware=false;
    for(NSDictionary *entry in (__bridge NSArray*)values) {
        if([entry[(__bridge NSString*)kVTVideoEncoderList_EncoderID] isEqual:S(id)]) {
            hardware=[entry[(__bridge NSString*)kVTVideoEncoderList_IsHardwareAccelerated] boolValue];break;
        }
    }
    CFRelease(values);return hardware;
}
struct Meter { obs_volmeter_t *meter = nullptr; std::atomic<float> level{-96.0f}; std::atomic<uint64_t> lastSignalNS{0}; };
struct Output {
    obs_output_t *output = nullptr;
    obs_encoder_t *video = nullptr;
    obs_encoder_t *audio = nullptr;
    obs_service_t *service = nullptr;
    std::atomic<int> stopCode{0};
    std::atomic<bool> started{false};
    std::atomic<bool> starting{false};
    std::atomic<bool> stopping{false};
    std::atomic<bool> cancelRequested{false}, stopWorkerRunning{false};
    std::thread stopWorker;
    std::string encoder, encoderName;
};
struct dante_engine {
    std::string scratch, error, backend, backendPath;
    bool recovering=false;
    uint32_t width = 1280, height = 720, fps = 30;
    std::vector<obs_scene_t *> scenes;
    obs_scene_t *selected = nullptr, *program = nullptr;
    obs_source_t *transition = nullptr;
    std::mutex previewLock;
    std::map<obs_source_t *, std::unique_ptr<Meter>> meters;
    Output recording, streaming, replay;
    NSMutableArray *modules = [NSMutableArray array];
};
static bool fail(dante_engine *e, const char *message) { if(e) e->error = message; return false; }
static obs_scene_t *findScene(dante_engine *e, NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return e->selected;
    for (auto *s : e->scenes) if ([S(obs_source_get_name(obs_scene_get_source(s))) isEqual:name]) return s;
    return nullptr;
}
static bool uniqueName(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return false;
    auto *source = obs_get_source_by_name(name.UTF8String);
    bool available = source == nullptr; obs_source_release(source); return available;
}
static bool registeredType(NSString *name,enum obs_source_type expected) {
    if(![name isKindOfClass:NSString.class] || !name.length)return false;
    const char *id=nullptr;
    for(size_t i=0;expected==OBS_SOURCE_TYPE_FILTER ? obs_enum_filter_types(i,&id) : obs_enum_input_types(i,&id);++i)
        if([name isEqual:S(id)])return true;
    return false;
}
static void meterCallback(void *data, const float *, const float *peak, const float *inputPeak) {
    auto *m = static_cast<Meter *>(data);
    float level = std::max(peak[0], peak[1]);
    // Timestamp signal in the audio callback so brief sound between UI polls is retained.
    // No allocations, locks, file IO or UI work here. Input peak is before the volume fader.
    if (std::max(inputPeak[0], inputPeak[1]) > -90.f) m->lastSignalNS.store(os_gettime_ns(), std::memory_order_relaxed);
    m->level.store(std::isfinite(level) ? std::max(-96.f, level) : -96.f, std::memory_order_relaxed);
}
static Meter *ensureMeter(dante_engine *e, obs_source_t *source) {
    if (!(obs_source_get_output_flags(source) & OBS_SOURCE_AUDIO)) return nullptr;
    auto it = e->meters.find(source); if (it != e->meters.end()) return it->second.get();
    auto m = std::make_unique<Meter>();
    m->meter = obs_volmeter_create(OBS_FADER_LOG);
    obs_volmeter_add_callback(m->meter, meterCallback, m.get());
    obs_volmeter_attach_source(m->meter, source);
    obs_source_get_ref(source); // Keep callback key alive until detach.
    auto *result = m.get(); e->meters[source] = std::move(m); return result;
}
static void clearMeters(dante_engine *e) {
    for (auto &pair : e->meters) {
        obs_volmeter_remove_callback(pair.second->meter, meterCallback, pair.second.get());
        obs_volmeter_destroy(pair.second->meter); obs_source_release(pair.first);
    }
    e->meters.clear();
}
static void outputStart(void *data, calldata_t *) { auto *o = static_cast<Output *>(data); o->started = true;o->starting=false; }
static void outputStop(void *data, calldata_t *cd) {
    auto *o = static_cast<Output *>(data); o->stopCode = (int)calldata_int(cd,"code"); o->started = false;o->starting=false; o->stopping = false;
}
static bool busy(Output &o) {return o.starting || o.stopping || o.stopWorkerRunning || (o.output && obs_output_active(o.output));}
static bool reconnectAllowed(void *data,obs_output_t *,int) {return !static_cast<Output*>(data)->cancelRequested.load();}
static void releaseOutput(Output &o) {
    o.cancelRequested=true;
    if(o.stopWorker.joinable())o.stopWorker.join();
    if (o.output) {
        if (busy(o)) obs_output_force_stop(o.output);
        auto *signals = obs_output_get_signal_handler(o.output);
        signal_handler_disconnect(signals,"start",outputStart,&o);
        signal_handler_disconnect(signals,"stop",outputStop,&o);
        obs_output_set_reconnect_callback(o.output,nullptr,nullptr);
        obs_output_release(o.output); o.output = nullptr;
    }
    obs_encoder_release(o.video); o.video = nullptr;
    obs_encoder_release(o.audio); o.audio = nullptr;
    obs_service_release(o.service); o.service = nullptr;
    o.started = false;o.starting=false; o.stopping = false;
}
static bool active(dante_engine *e) {
    return busy(e->recording)||busy(e->streaming)||busy(e->replay);
}
static NSString *defaultEncoder() {
    const char *id = nullptr;
    for (size_t i=0; obs_enum_encoder_types(i,&id); ++i)
        if (obs_get_encoder_type(id)==OBS_ENCODER_VIDEO && !strcmp(obs_get_encoder_codec(id),"h264") &&
            hardwareEncoder(id)) return S(id);
    return @"obs_x264";
}
static bool startOutput(dante_engine *e, Output &o, NSString *kind, NSDictionary *a) {
    if (busy(o)) return fail(e,"A saída já está ativa ou conectando.");
    releaseOutput(o); o.stopCode = 0;o.cancelRequested=false;
    bool stream = [kind isEqual:@"stream"], replay = [kind isEqual:@"replay"];
    NSString *encoder = [a[@"encoder"] isKindOfClass:NSString.class] && [a[@"encoder"] length] ? a[@"encoder"] : defaultEncoder();
    const char *codec = obs_get_encoder_codec(encoder.UTF8String);
    if (!codec || strcmp(codec,"h264")) return fail(e,"Escolha um encoder H.264 disponível para esta saída.");
    int bitrate = a[@"bitrate"] ? [a[@"bitrate"] intValue] : 6000;
    if (bitrate < 100 || bitrate > 200000) return fail(e,"Bitrate fora do intervalo de 100 a 200000 kbps.");
    int audioBitrate=a[@"audioBitrate"] ? [a[@"audioBitrate"] intValue] : stream ? 128 : 160;
    if((a[@"audioBitrate"] && [a[@"audioBitrate"] doubleValue]!=audioBitrate) ||
        (audioBitrate!=128 && audioBitrate!=160 && audioBitrate!=192 && audioBitrate!=256 && audioBitrate!=320))
        return fail(e,"O bitrate AAC deve ser 128, 160, 192, 256 ou 320 kbps.");
    if (stream && (![a[@"server"] isKindOfClass:NSString.class] ||
        (![(NSString*)a[@"server"] hasPrefix:@"rtmp://"] && ![(NSString*)a[@"server"] hasPrefix:@"rtmps://"])))
        return fail(e,"Informe um servidor RTMP ou RTMPS válido.");
    if (!stream && !replay) {
        NSString *path = a[@"path"];
        if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath || ![path.pathExtension.lowercaseString isEqual:@"mkv"])
            return fail(e,"Escolha um caminho absoluto com extensão .mkv.");
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return fail(e,"O arquivo já existe. Escolha outro nome para preservar a gravação.");
    }
    obs_data_t *video = obs_encoder_defaults(encoder.UTF8String);
    if (!video) video = obs_data_create();
    obs_data_set_int(video,"bitrate",bitrate); obs_data_set_string(video,"rate_control","CBR");
    obs_data_set_int(video,"keyint_sec",2); obs_data_set_string(video,"profile","high");
    o.encoderName=std::string("Dante ")+kind.UTF8String+" video";
    {std::lock_guard<std::mutex> lock(hardwareLogMutex);hardwareSessions.erase(o.encoderName);}
    o.video = obs_video_encoder_create(encoder.UTF8String,o.encoderName.c_str(),video,nullptr);
    obs_data_release(video);
    obs_data_t *audio = settings(@{@"bitrate":@(audioBitrate)});
    const char *aac = obs_get_encoder_codec("CoreAudio_AAC") ? "CoreAudio_AAC" : "ffmpeg_aac";
    o.audio = obs_audio_encoder_create(aac, (std::string("Dante ")+kind.UTF8String+" audio").c_str(),audio,0,nullptr);
    obs_data_release(audio);
    if (!o.video || !o.audio) { releaseOutput(o); return fail(e,"Não foi possível criar os encoders de áudio e vídeo."); }
    obs_encoder_set_video(o.video,obs_get_video()); obs_encoder_set_audio(o.audio,obs_get_audio());
    NSMutableDictionary *outputSettings = [NSMutableDictionary dictionary];
    if (!stream && !replay) outputSettings[@"path"] = a[@"path"];
    if (replay) {
        NSString *directory = a[@"directory"];
        BOOL isDirectory = NO;
        if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath ||
            ![[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
            releaseOutput(o); return fail(e,"Escolha uma pasta existente para o replay.");
        }
        outputSettings[@"directory"] = directory; outputSettings[@"format"] = @"Dante-Replay-%CCYY-%MM-%DD-%hh-%mm-%ss";
        outputSettings[@"extension"] = @"mkv"; outputSettings[@"max_time_sec"] = @([a[@"seconds"] intValue] ?: 20);
        outputSettings[@"max_size_mb"] = @512;
    }
    obs_data_t *out = settings(outputSettings);
    o.output = obs_output_create(stream ? "rtmp_output" : replay ? "replay_buffer" : "ffmpeg_muxer",kind.UTF8String,out,nullptr);
    obs_data_release(out);
    if (!o.output) { releaseOutput(o); return fail(e,"O módulo de saída não está disponível."); }
    obs_output_set_video_encoder(o.output,o.video); obs_output_set_audio_encoder(o.output,o.audio,0);
    if (stream) {
        obs_data_t *service = settings(@{@"server":a[@"server"],@"key":a[@"key"] ?: @""});
        o.service = obs_service_create("rtmp_custom","Dante RTMP",service,nullptr); obs_data_release(service);
        if (!o.service) { releaseOutput(o); return fail(e,"Serviço RTMP indisponível."); }
        obs_output_set_service(o.output,o.service); obs_output_set_reconnect_settings(o.output,20,2);
        obs_output_set_reconnect_callback(o.output,reconnectAllowed,&o);
    }
    o.encoder = encoder.UTF8String;
    auto *signals = obs_output_get_signal_handler(o.output);
    signal_handler_connect(signals,"start",outputStart,&o); signal_handler_connect(signals,"stop",outputStop,&o);
    o.starting=true;
    if (!obs_output_start(o.output)) {
        const char *error = obs_output_get_last_error(o.output);
        // Streaming errors may contain an authenticated URL; never echo that payload.
        e->error = stream ? "Não foi possível iniciar a transmissão. Verifique o servidor, a chave e a rede." :
            (error && *error ? error : "Não foi possível iniciar a saída. Verifique encoder, permissões e pasta.");
        releaseOutput(o); return false;
    }
    return true;
}

dante_engine_t *dante_engine_create(const char *bundlePath,uint32_t width,uint32_t height,uint32_t fps) {
    return dante_engine_create_with_config(bundlePath,width,height,fps,nullptr);
}
dante_engine_t *dante_engine_create_with_config(const char *bundlePath,uint32_t width,uint32_t height,uint32_t fps,const char *moduleConfigDirectory) {
    creationError.clear();
    if (obs_initialized()) { creationError="Já existe um motor neste processo."; return nullptr; }
    if (width<16 || height<16 || width>8192 || height>8192 || width%2 || height%2 || !fps || fps>120) {
        creationError="Configuração de vídeo inválida."; return nullptr;
    }
    NSString *bundle = S(bundlePath), *frameworks = [bundle stringByAppendingPathComponent:@"Contents/Frameworks"];
    NSString *moduleConfig=moduleConfigDirectory ? S(moduleConfigDirectory) :
        [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"Dante Live/engine"];
    NSError *directoryError=nil;
    if(!moduleConfig.isAbsolutePath || ![[NSFileManager defaultManager] createDirectoryAtPath:moduleConfig withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&directoryError]) {
        creationError="Não foi possível preparar a pasta privada de configuração do motor.";return nullptr;
    }
    auto *e = new dante_engine; e->width=width; e->height=height; e->fps=fps;
    base_set_log_handler(privateLog,nullptr);
    obs_add_data_path([[frameworks stringByAppendingPathComponent:@"libobs.framework/Resources"] UTF8String]);
    if (!obs_startup("pt-BR",moduleConfig.UTF8String,nullptr)) { creationError="Falha ao inicializar libobs."; delete e; return nullptr; }
    obs_audio_info audio = {}; audio.samples_per_sec=48000; audio.speakers=SPEAKERS_STEREO;
    if (!obs_reset_audio(&audio)) { creationError="Falha ao inicializar áudio."; obs_shutdown(); delete e; return nullptr; }
    obs_video_info video = {}; video.base_width=width; video.base_height=height; video.output_width=width; video.output_height=height;
    video.fps_num=fps; video.fps_den=1; video.output_format=VIDEO_FORMAT_NV12; video.colorspace=VIDEO_CS_709;
    video.range=VIDEO_RANGE_PARTIAL; video.scale_type=OBS_SCALE_BICUBIC; video.gpu_conversion=true;
    NSArray *backends;
#if defined(__arm64__)
    backends = @[@"libobs-metal.dylib",@"libobs-opengl.dylib"];
#else
    backends = @[@"libobs-opengl.dylib"];
#endif
    int result = -1;
    for (NSString *backend in backends) {
        NSString *path = [frameworks stringByAppendingPathComponent:backend];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        video.graphics_module=path.UTF8String; result=obs_reset_video(&video);
        if (result==OBS_VIDEO_SUCCESS) { e->backend=backend.UTF8String;e->backendPath=path.UTF8String; break; }
    }
    if (result!=OBS_VIDEO_SUCCESS) { creationError="Não foi possível inicializar Metal/OpenGL."; obs_shutdown(); delete e; return nullptr; }
    NSArray *names=@[@"image-source",@"mac-avcapture",@"mac-capture",@"mac-videotoolbox",@"coreaudio-encoder",@"obs-ffmpeg",@"obs-filters",@"obs-outputs",@"obs-transitions",@"obs-x264",@"rtmp-services",@"text-freetype2"];
    for (NSString *name in names) {
        NSString *moduleRoot = [bundle stringByAppendingPathComponent:[NSString stringWithFormat:@"Contents/PlugIns/%@.plugin/Contents",name]];
        NSString *binary = [moduleRoot stringByAppendingPathComponent:[@"MacOS/" stringByAppendingString:name]];
        NSString *data = [moduleRoot stringByAppendingPathComponent:@"Resources"];
        obs_module_t *module=nullptr;
        int status=obs_open_module(&module,binary.UTF8String,data.UTF8String);
        bool loaded=status==MODULE_SUCCESS && obs_init_module(module);
        [e->modules addObject:@{@"name":name,@"loaded":@(loaded),@"code":@(status)}];
    }
    obs_post_load_modules();
    e->transition=obs_source_create_private("fade_transition","Dante fade",nullptr);
    if (!e->transition) { creationError="Módulo de transição ausente."; obs_shutdown(); delete e; return nullptr; }
    obs_transition_set_size(e->transition,width,height);
    obs_set_output_source(0,e->transition);
    auto *scene=obs_scene_create("Cena 1"); e->scenes.push_back(scene); e->selected=e->program=scene;
    obs_source_inc_showing(obs_scene_get_source(scene));
    obs_transition_set(e->transition,obs_scene_get_source(scene));
    return e;
}
void dante_engine_destroy(dante_engine_t *e) {
    if (!e) return;
    releaseOutput(e->recording); releaseOutput(e->streaming); releaseOutput(e->replay);
    clearMeters(e); obs_set_output_source(0,nullptr); obs_transition_clear(e->transition);
    if(e->selected)obs_source_dec_showing(obs_scene_get_source(e->selected));
    obs_source_release(e->transition);
    // OBS 32 canvases retain scene references. Remove them before releasing our
    // references so source destruction finishes before module unload (FreeType etc.).
    for(auto *scene:e->scenes){obs_source_remove(obs_scene_get_source(scene));obs_scene_release(scene);}
    e->scenes.clear();obs_wait_for_destroy_queue();
    obs_shutdown(); delete e;
}
const char *dante_engine_last_error(dante_engine_t *e) { return e ? e->error.c_str() : creationError.c_str(); }

static NSArray *propertyList(obs_properties_t *properties) {
    NSMutableArray *result=[NSMutableArray array];
    for (auto *p=obs_properties_first(properties); p; obs_property_next(&p)) {
        int type=obs_property_get_type(p);
        NSMutableDictionary *item=[@{@"name":S(obs_property_name(p)),@"label":S(obs_property_description(p)),
            @"description":S(obs_property_description(p)),@"help":S(obs_property_long_description(p)),@"type":@(type),@"visible":@(obs_property_visible(p)),@"enabled":@(obs_property_enabled(p))} mutableCopy];
        if(type==OBS_PROPERTY_INT) { item[@"min"]=@(obs_property_int_min(p)); item[@"max"]=@(obs_property_int_max(p)); item[@"step"]=@(obs_property_int_step(p)); }
        if(type==OBS_PROPERTY_FLOAT) { item[@"min"]=@(obs_property_float_min(p)); item[@"max"]=@(obs_property_float_max(p)); item[@"step"]=@(obs_property_float_step(p)); }
        if(type==OBS_PROPERTY_TEXT) item[@"textType"]=@(obs_property_text_type(p));
        if(type==OBS_PROPERTY_PATH) { item[@"pathType"]=@(obs_property_path_type(p)); item[@"filter"]=S(obs_property_path_filter(p)); }
        if(type==OBS_PROPERTY_LIST) {
            NSMutableArray *options=[NSMutableArray array]; auto format=obs_property_list_format(p); item[@"format"]=@(format);
            for(size_t i=0;i<obs_property_list_item_count(p);++i) {
                id value= format==OBS_COMBO_FORMAT_STRING ? S(obs_property_list_item_string(p,i)) :
                    format==OBS_COMBO_FORMAT_FLOAT ? @(obs_property_list_item_float(p,i)) :
                    format==OBS_COMBO_FORMAT_BOOL ? @(obs_property_list_item_bool(p,i)) : @(obs_property_list_item_int(p,i));
                [options addObject:@{@"label":S(obs_property_list_item_name(p,i)),@"name":S(obs_property_list_item_name(p,i)),@"value":value,@"disabled":@(obs_property_list_item_disabled(p,i))}];
            }
            item[@"options"]=options;item[@"items"]=options;
        }
        if(type==OBS_PROPERTY_FRAME_RATE) {
            NSMutableArray *ranges=[NSMutableArray array];
            for(size_t i=0;i<obs_property_frame_rate_fps_ranges_count(p);i++) {
                auto min=obs_property_frame_rate_fps_range_min(p,i),max=obs_property_frame_rate_fps_range_max(p,i);
                [ranges addObject:@{@"minNumerator":@(min.numerator),@"minDenominator":@(min.denominator),@"maxNumerator":@(max.numerator),@"maxDenominator":@(max.denominator)}];
            }
            item[@"ranges"]=ranges;
        }
        if(type==OBS_PROPERTY_GROUP) item[@"children"]=propertyList(obs_property_group_content(p));
        [result addObject:item];
    }
    return result;
}
static const char *propertiesFor(dante_engine *e,obs_source_t *source,const char *type,const char *candidate=nullptr) {
    auto *data=source ? obs_source_get_settings(source) : obs_get_source_defaults(type);
    if(!data)data=obs_data_create();
    if(source){auto *copy=settings(jsonSettings(data));obs_data_release(data);data=copy;}
    if(candidate){id object=parse(candidate);if([object isKindOfClass:NSDictionary.class]){auto *update=settings(object);obs_data_apply(data,update);obs_data_release(update);}}
    // Capture modules may dereference instance data from get_properties(NULL).
    // Never instantiate a device merely to render an add-source form.
    if(!source && type && (!strcmp(type,"screen_capture") || !strcmp(type,"sck_audio_capture") || !strcmp(type,"av_capture_input") ||
        !strncmp(type,"macos-avcapture",15) || !strncmp(type,"coreaudio",9) || !strcmp(type,"display_capture") || !strcmp(type,"window_capture"))) {
        e->scratch=J(@{@"settings":jsonSettings(data),@"properties":@[],@"instanceRequired":@YES,@"requiresInstance":@YES,
            @"message":@"Crie a fonte para escolher o dispositivo e configurar a captura. O macOS poderá solicitar permissão."});
        obs_data_release(data);return e->scratch.c_str();
    }
    auto *props=source ? obs_source_properties(source) : obs_get_source_properties(type);
    if (props && data) obs_properties_apply_settings(props,data);
    e->scratch=J(@{@"settings":jsonSettings(data),@"properties":props ? propertyList(props) : @[]});
    obs_properties_destroy(props); obs_data_release(data); return e->scratch.c_str();
}
const char *dante_engine_properties(dante_engine_t *e,const char *name) {
    if(!e)return "{}"; auto *s=obs_get_source_by_name(name); if(!s)return "{}";
    propertiesFor(e,s,nullptr); obs_source_release(s); return e->scratch.c_str();
}
const char *dante_engine_type_properties(dante_engine_t *e,const char *type) { return e ? propertiesFor(e,nullptr,type) : "{}"; }
const char *dante_engine_type_properties_with_settings(dante_engine_t *e,const char *type,const char *candidate) {return e ? propertiesFor(e,nullptr,type,candidate) : "{}";}
const char *dante_engine_properties_with_settings(dante_engine_t *e,const char *name,const char *candidate) {
    if(!e)return "{}";auto *source=obs_get_source_by_name(name);if(!source)return "{}";
    propertiesFor(e,source,nullptr,candidate);obs_source_release(source);return e->scratch.c_str();
}
const char *dante_engine_filter_properties(dante_engine_t *e,const char *name,const char *filter) {
    if(!e)return "{}"; auto *s=obs_get_source_by_name(name); if(!s)return "{}";
    auto *f=obs_source_get_filter_by_name(s,filter); if(f) propertiesFor(e,f,nullptr); else e->scratch="{}";
    obs_source_release(f); obs_source_release(s); return e->scratch.c_str();
}
const char *dante_engine_catalog(dante_engine_t *e) {
    if(!e)return "{}";
    NSMutableArray *sources=[NSMutableArray array],*filters=[NSMutableArray array],*encoders=[NSMutableArray array];
    const char *id=nullptr;
    for(size_t i=0;obs_enum_input_types(i,&id);++i) {
        uint32_t flags=obs_get_source_output_flags(id);
        if(flags&OBS_SOURCE_CAP_DISABLED)continue;
        [sources addObject:@{@"id":S(id),@"name":S(obs_source_get_display_name(id)),@"flags":@(flags)}];
    }
    for(size_t i=0;obs_enum_filter_types(i,&id);++i)
        [filters addObject:@{@"id":S(id),@"name":S(obs_source_get_display_name(id)),@"flags":@(obs_get_source_output_flags(id))}];
    for(size_t i=0;obs_enum_encoder_types(i,&id);++i)
        [encoders addObject:@{@"id":S(id),@"name":S(obs_encoder_get_display_name(id)),@"codec":S(obs_get_encoder_codec(id)),
            @"type":@(obs_get_encoder_type(id)),@"hardware":@(hardwareEncoder(id))}];
    e->scratch=J(@{@"sources":sources,@"filters":filters,@"encoders":encoders,@"modules":e->modules,@"defaultEncoder":defaultEncoder()}); return e->scratch.c_str();
}
static NSDictionary *outputState(Output &o,bool secret=false) {
    if(!o.output)return @{@"active":@NO,@"busy":@NO,@"starting":@NO,@"started":@NO,@"stopping":@NO,@"error":@"",@"code":@(o.stopCode.load())};
    const char *error=obs_output_get_last_error(o.output);
    obs_data_t *videoSettings=obs_encoder_get_settings(o.video),*audioSettings=obs_encoder_get_settings(o.audio);
    NSDictionary *encoderSettings=@{@"bitrate":@(obs_data_get_int(videoSettings,"bitrate")),
        @"audioBitrate":@(obs_data_get_int(audioSettings,"bitrate")),@"keyframeSeconds":@(obs_data_get_int(videoSettings,"keyint_sec")),
        @"rateControl":S(obs_data_get_string(videoSettings,"rate_control"))};
    obs_data_release(videoSettings);obs_data_release(audioSettings);
    bool confirmed=false;{std::lock_guard<std::mutex> lock(hardwareLogMutex);auto it=hardwareSessions.find(o.encoderName);confirmed=it!=hardwareSessions.end()&&it->second;}
    return @{@"active":@(obs_output_active(o.output)),@"busy":@(busy(o)),@"starting":@(o.starting.load()),@"started":@(o.started.load()),@"stopping":@(o.stopping.load()),
        @"reconnecting":@(obs_output_reconnecting(o.output)),@"frames":@(obs_output_get_total_frames(o.output)),
        @"dropped":@(obs_output_get_frames_dropped(o.output)),@"bytes":@(obs_output_get_total_bytes(o.output)),
        @"congestion":@(obs_output_get_congestion(o.output)),@"encoder":S(o.encoder.c_str()),@"settings":encoderSettings,@"hardwareConfirmed":@(confirmed),@"code":@(o.stopCode.load()),
        @"error":secret && error && *error ? @"Falha na transmissão. Verifique servidor, chave e rede." : S(error)};
}
struct ItemContext { dante_engine *engine; NSMutableArray *items; };
static void cancelPlacement(obs_sceneitem_t *item) {
    auto *data=obs_sceneitem_get_private_settings(item);obs_data_set_bool(data,"dante_pending_placement",false);obs_data_release(data);
}
static bool placeItem(dante_engine *e,obs_sceneitem_t *item,int mode) {
    auto *source=obs_sceneitem_get_source(item);float width=obs_source_get_width(source),height=obs_source_get_height(source);
    if(width<=0 || height<=0)return false;
    if(mode==3) {
        obs_sceneitem_force_update_transform(item);matrix4 box;obs_sceneitem_get_box_transform(item,&box);
        vec3 midpoint,center;vec3_set(&midpoint,.5f,.5f,0);vec3_transform(&center,&midpoint,&box);
        vec2 position;obs_sceneitem_get_pos(item,&position);position.x+=e->width/2.f-center.x;position.y+=e->height/2.f-center.y;
        obs_sceneitem_set_pos(item,&position);cancelPlacement(item);return true;
    }
    float factor=mode==2 ? 1.f : std::min(e->width/width,e->height/height);if(mode==0)factor=std::min(1.f,factor);
    vec2 scale={factor,factor},position={(e->width-width*factor)/2,(e->height-height*factor)/2};
    obs_sceneitem_crop crop={};obs_sceneitem_defer_update_begin(item);
    obs_sceneitem_set_bounds_type(item,OBS_BOUNDS_NONE);obs_sceneitem_set_alignment(item,OBS_ALIGN_TOP|OBS_ALIGN_LEFT);
    obs_sceneitem_set_scale(item,&scale);obs_sceneitem_set_pos(item,&position);obs_sceneitem_set_rot(item,0);obs_sceneitem_set_crop(item,&crop);
    obs_sceneitem_defer_update_end(item);cancelPlacement(item);return true;
}
static bool requestPlacement(dante_engine *e,obs_sceneitem_t *item,int mode) {
    if(!(obs_source_get_output_flags(obs_sceneitem_get_source(item))&OBS_SOURCE_VIDEO))return false;
    if(placeItem(e,item,mode))return true;
    auto *data=obs_sceneitem_get_private_settings(item);obs_data_set_bool(data,"dante_pending_placement",true);
    obs_data_set_int(data,"dante_placement_mode",mode);obs_data_release(data);
    // Unknown dimensions are waiting for the source, not a 0x0 successful fit.
    // Keep its selection anchor at the canvas center until the first dimensions.
    vec2 position={e->width/2.f,e->height/2.f};obs_sceneitem_set_pos(item,&position);return true;
}
static bool resolvePlacement(dante_engine *e,obs_sceneitem_t *item) {
    auto *data=obs_sceneitem_get_private_settings(item);bool pending=obs_data_get_bool(data,"dante_pending_placement");
    int mode=(int)obs_data_get_int(data,"dante_placement_mode");obs_data_release(data);
    if(pending && !obs_sceneitem_locked(item) && placeItem(e,item,mode))pending=false;
    return pending;
}
static bool itemState(obs_scene_t *,obs_sceneitem_t *item,void *data) {
    auto *ctx=static_cast<ItemContext *>(data); auto *source=obs_sceneitem_get_source(item);
    bool pendingPlacement=resolvePlacement(ctx->engine,item);
    vec2 pos,scale; obs_sceneitem_get_pos(item,&pos);obs_sceneitem_get_scale(item,&scale);
    obs_sceneitem_crop crop;obs_sceneitem_get_crop(item,&crop);
    matrix4 box;obs_sceneitem_get_box_transform(item,&box);
    NSMutableArray *corners=[NSMutableArray arrayWithCapacity:4];
    const float cornerXY[4][2]={{0,0},{1,0},{1,1},{0,1}};
    for(int index=0;index<4;index++){vec3 point,transformed;vec3_set(&point,cornerXY[index][0],cornerXY[index][1],0);vec3_transform(&transformed,&point,&box);
        [corners addObject:@[@(transformed.x),@(transformed.y)]];}
    auto *meter=ensureMeter(ctx->engine,source);
    const uint64_t lastSignal = meter ? meter->lastSignalNS.load(std::memory_order_relaxed) : 0;
    NSMutableArray *filters=[NSMutableArray array];
    obs_source_enum_filters(source,[](obs_source_t *,obs_source_t *filter,void *p){
        [(__bridge NSMutableArray*)p addObject:@{@"name":S(obs_source_get_name(filter)),@"type":S(obs_source_get_id(filter)),@"enabled":@(obs_source_enabled(filter))}];
    },(__bridge void*)filters);
    [ctx->items addObject:@{@"id":@(obs_sceneitem_get_id(item)),@"name":S(obs_source_get_name(source)),@"type":S(obs_source_get_id(source)),
        @"x":@(pos.x),@"y":@(pos.y),@"scaleX":@(scale.x),@"scaleY":@(scale.y),@"width":@(obs_source_get_width(source)),@"height":@(obs_source_get_height(source)),
        @"rotation":@(obs_sceneitem_get_rot(item)),@"visible":@(obs_sceneitem_visible(item)),@"locked":@(obs_sceneitem_locked(item)),
        @"boxCorners":corners,@"boundsType":@(obs_sceneitem_get_bounds_type(item)),@"pendingPlacement":@(pendingPlacement),@"awaitingVideo":@((obs_source_get_output_flags(source)&OBS_SOURCE_VIDEO) && (!obs_source_get_width(source)||!obs_source_get_height(source))),
        @"cropLeft":@(crop.left),@"cropRight":@(crop.right),@"cropTop":@(crop.top),@"cropBottom":@(crop.bottom),
        @"sourceUUID":S(obs_source_get_uuid(source)),@"sourceActive":@(obs_source_active(source)),
        @"signalAge":@(lastSignal ? double(os_gettime_ns()-lastSignal)/1e9 : -1.0),
        @"volume":@(obs_source_get_volume(source)),@"muted":@(obs_source_muted(source)),@"audio":@((obs_source_get_output_flags(source)&OBS_SOURCE_AUDIO)!=0),
        @"level":@(meter ? meter->level.load() : -96.f),@"syncMS":@(obs_source_get_sync_offset(source)/1000000),
        @"tracks":@(obs_source_get_audio_mixers(source)),@"monitoring":@(obs_source_get_monitoring_type(source)),@"filters":filters,
        @"mediaState":@(obs_source_media_get_state(source)),@"mediaTime":@(obs_source_media_get_time(source)),@"mediaDuration":@(obs_source_media_get_duration(source))}];
    return true;
}
const char *dante_engine_state(dante_engine_t *e) {
    if(!e)return "{}";
    NSMutableArray *scenes=[NSMutableArray array];
    for(auto *scene:e->scenes) { ItemContext ctx={e,[NSMutableArray array]};obs_scene_enum_items(scene,itemState,&ctx);
        [scenes addObject:@{@"name":S(obs_source_get_name(obs_scene_get_source(scene))),@"items":ctx.items}]; }
    NSDictionary *rec=outputState(e->recording),*stream=outputState(e->streaming,true),*replay=outputState(e->replay);
    e->scratch=J(@{@"scenes":scenes,@"selectedScene":e->selected ? S(obs_source_get_name(obs_scene_get_source(e->selected))) : @"",
        @"programScene":e->program ? S(obs_source_get_name(obs_scene_get_source(e->program))) : @"",
        @"width":@(e->width),@"height":@(e->height),@"fps":@(e->fps),@"backend":S(e->backend.c_str()),@"error":S(e->error.c_str()),
        @"recording":rec[@"busy"],@"streaming":stream[@"busy"],@"replaying":replay[@"busy"],
        @"outputs":@{@"recording":rec,@"stream":stream,@"replay":replay},
        @"stats":@{@"activeFPS":@(obs_get_active_fps()),@"renderMS":@(obs_get_average_frame_time_ns()/1000000.0),
            @"renderedFrames":@(obs_get_total_frames()),@"renderSkipped":@(obs_get_lagged_frames())}});
    return e->scratch.c_str();
}

static bool configureVideo(dante_engine *e,uint32_t width,uint32_t height,uint32_t fps) {
    if(active(e))return fail(e,"Pare todas as saídas antes de alterar o vídeo.");
    if(width<16||height<16||width>8192||height>8192||width%2||height%2||fps<1||fps>120)return fail(e,"Vídeo inválido: dimensões pares entre 16 e 8192, FPS entre 1 e 120.");
    if(width==e->width && height==e->height && fps==e->fps)return true;
    releaseOutput(e->recording);releaseOutput(e->streaming);releaseOutput(e->replay);
    obs_video_info old={};if(!obs_get_video_info(&old))return fail(e,"Configuração de vídeo não disponível.");
    old.graphics_module=e->backendPath.c_str();obs_video_info next=old;
    next.base_width=next.output_width=width;next.base_height=next.output_height=height;next.fps_num=fps;next.fps_den=1;
    int result=obs_reset_video(&next);
    if(result!=OBS_VIDEO_SUCCESS){obs_reset_video(&old);return fail(e,"A alteração de vídeo falhou; a configuração anterior foi solicitada novamente.");}
    {std::lock_guard<std::mutex> lock(e->previewLock);e->width=width;e->height=height;e->fps=fps;}
    obs_transition_set_size(e->transition,width,height);return true;
}
bool dante_engine_command(dante_engine_t *e,const char *operation,const char *json) {
    if(!e)return false; e->error.clear();
    id value=parse(json ?: "{}"); if(![value isKindOfClass:NSDictionary.class])return fail(e,"Argumentos JSON inválidos.");
    NSDictionary *a=value; NSString *op=S(operation);
    for(NSString *key in @[@"scene",@"name",@"newName",@"filter",@"type",@"path",@"encoder",@"directory",@"server",@"key",@"transition"])
        if(a[key] && ![a[key] isKindOfClass:NSString.class])return fail(e,"Argumento de texto inválido.");
    for(NSString *key in @[@"id",@"x",@"y",@"scaleX",@"scaleY",@"rotation",@"cropLeft",@"cropRight",@"cropTop",@"cropBottom",@"value",@"index",@"studio",@"autoPlace",@"duration",@"volume",@"muted",@"syncMS",@"tracks",@"monitoring",@"milliseconds",@"seconds",@"bitrate",@"audioBitrate",@"width",@"height",@"fps"])
        if(a[key] && (![a[key] isKindOfClass:NSNumber.class] || !std::isfinite([a[key] doubleValue])))return fail(e,"Argumento numérico inválido.");
    if(a[@"settings"] && ![a[@"settings"] isKindOfClass:NSDictionary.class])return fail(e,"Configurações da fonte inválidas.");
    if(a[@"syncMS"] && fabs([a[@"syncMS"] doubleValue])>3600000)return fail(e,"A compensação de áudio deve ficar entre -3600000 e 3600000 ms.");
    if(a[@"seconds"] && ([a[@"seconds"] doubleValue]<1 || [a[@"seconds"] doubleValue]>3600))return fail(e,"O replay deve durar de 1 a 3600 segundos.");
    if([op isEqual:@"video.configure"])return configureVideo(e,[a[@"width"] unsignedIntValue],[a[@"height"] unsignedIntValue],[a[@"fps"] unsignedIntValue]);
    auto *scene=findScene(e,a[@"scene"]);
    if([op hasPrefix:@"scene."]) {
        if([op isEqual:@"scene.create"] || [op isEqual:@"scene.duplicate"]) {
            if(!uniqueName(a[@"name"]))return fail(e,"Escolha um nome de cena exclusivo.");
            if([op isEqual:@"scene.duplicate"] && !scene)return fail(e,"Cena não encontrada.");
            auto *created=[op isEqual:@"scene.create"] ? obs_scene_create([a[@"name"] UTF8String]) : obs_scene_duplicate(scene,[a[@"name"] UTF8String],OBS_SCENE_DUP_REFS);
            if(!created)return fail(e,"Falha ao criar cena."); e->scenes.push_back(created); return true;
        }
        if(!scene)return fail(e,"Cena não encontrada.");
        if([op isEqual:@"scene.reorderSources"]) {
            NSArray *ids=a[@"ids"];
            if(![ids isKindOfClass:NSArray.class])return fail(e,"Ordem de fontes inválida.");
            std::vector<obs_sceneitem_t *> order;
            for(id identifier in ids) {
                if(![identifier isKindOfClass:NSNumber.class])return fail(e,"Identificador de fonte inválido.");
                auto *item=obs_scene_find_sceneitem_by_id(scene,[identifier longLongValue]);
                if(!item || std::find(order.begin(),order.end(),item)!=order.end())return fail(e,"A lista de fontes mudou. Tente arrastar novamente.");
                order.push_back(item);
            }
            return obs_scene_reorder_items(scene,order.data(),order.size()) || fail(e,"Não foi possível reordenar as fontes.");
        }
        if([op isEqual:@"scene.rename"]) {
            if(!uniqueName(a[@"name"]))return fail(e,"Escolha um nome de cena exclusivo.");
            obs_source_set_name(obs_scene_get_source(scene),[a[@"name"] UTF8String]);return true;
        }
        if([op isEqual:@"scene.select"]) {
            if(e->selected!=scene){auto *previous=e->selected;{std::lock_guard<std::mutex> lock(e->previewLock);e->selected=scene;}
                obs_source_inc_showing(obs_scene_get_source(scene));if(previous)obs_source_dec_showing(obs_scene_get_source(previous));}
            if(![a[@"studio"] boolValue]) { e->program=scene;obs_transition_set(e->transition,obs_scene_get_source(scene)); }
            return true;
        }
        if([op isEqual:@"scene.take"]) {
            if([a[@"transition"] isEqual:@"cut"] || [a[@"duration"] intValue]==0) obs_transition_set(e->transition,obs_scene_get_source(scene));
            else if(!obs_transition_start(e->transition,OBS_TRANSITION_MODE_AUTO,std::clamp([a[@"duration"] intValue],1,20000),obs_scene_get_source(scene)))
                return fail(e,"A transição não pôde iniciar.");
            e->program=scene;return true;
        }
        if([op isEqual:@"scene.order"]) {
            auto it=std::find(e->scenes.begin(),e->scenes.end(),scene);e->scenes.erase(it);
            e->scenes.insert(e->scenes.begin()+std::clamp([a[@"index"] intValue],0,(int)e->scenes.size()),scene);return true;
        }
        if([op isEqual:@"scene.delete"]) {
            if(e->scenes.size()==1)return fail(e,"Mantenha pelo menos uma cena.");
            if(active(e) && e->program==scene)return fail(e,"A cena está no programa de uma saída ativa.");
            e->scenes.erase(std::find(e->scenes.begin(),e->scenes.end(),scene));
            if(e->selected==scene){{std::lock_guard<std::mutex> lock(e->previewLock);e->selected=e->scenes.front();}
                obs_source_dec_showing(obs_scene_get_source(scene));obs_source_inc_showing(obs_scene_get_source(e->selected));}
            if(e->program==scene) {e->program=e->selected;obs_transition_set(e->transition,obs_scene_get_source(e->program));}
            obs_source_remove(obs_scene_get_source(scene));obs_scene_release(scene);clearMeters(e);return true;
        }
    }
    if([op isEqual:@"source.add"] || [op isEqual:@"source.reuse"]) {
        if(!scene)return fail(e,"Cena não encontrada.");
        bool reuse=[op isEqual:@"source.reuse"];
        if(!reuse && !registeredType(a[@"type"],OBS_SOURCE_TYPE_INPUT))return fail(e,"Tipo de fonte não registrado no motor.");
        if(!reuse && !uniqueName(a[@"name"]))return fail(e,"Escolha um nome exclusivo para a fonte.");
        obs_data_t *data=settings(a[@"settings"]);
        auto *source=reuse ? obs_get_source_by_name([a[@"name"] UTF8String]) : obs_source_create([a[@"type"] UTF8String],[a[@"name"] UTF8String],data,nullptr);
        obs_data_release(data);
        if(!source)return fail(e,"Não foi possível criar ou localizar a fonte.");
        auto *item=obs_scene_add(scene,source);obs_source_release(source);
        if(!item)return fail(e,"Fonte incompatível ou cena com referência circular.");
        obs_sceneitem_set_alignment(item,OBS_ALIGN_TOP|OBS_ALIGN_LEFT);requestPlacement(e,item,false);return true;
    }
    if([op hasPrefix:@"item."] || [op isEqual:@"source.remove"]) {
        if(!scene)return fail(e,"Cena não encontrada.");
        auto *item=obs_scene_find_sceneitem_by_id(scene,[a[@"id"] longLongValue]);if(!item)return fail(e,"Elemento não encontrado.");
        if([op isEqual:@"source.remove"]) {obs_sceneitem_remove(item);clearMeters(e);return true;}
        if([op isEqual:@"item.visible"]) {bool desired=[a[@"value"] boolValue];return obs_sceneitem_visible(item)==desired || obs_sceneitem_set_visible(item,desired);}
        if([op isEqual:@"item.locked"]) {bool desired=[a[@"value"] boolValue];if(desired)cancelPlacement(item);return obs_sceneitem_locked(item)==desired || obs_sceneitem_set_locked(item,desired);}
        if([op isEqual:@"item.order"]) {obs_sceneitem_set_order_position(item,[a[@"index"] intValue]);return true;}
        if(obs_sceneitem_locked(item))return fail(e,"Desbloqueie o elemento para editá-lo.");
        if([op isEqual:@"item.fit"] || [op isEqual:@"item.native"] || [op isEqual:@"item.center"]) {
            int mode=[op isEqual:@"item.fit"] ? 1 : [op isEqual:@"item.native"] ? 2 : 3;
            if(!requestPlacement(e,item,mode))return fail(e,"Esta fonte não contém vídeo para ajustar ao canvas.");return true;
        }
        if([op isEqual:@"item.transform"]) {
            vec2 pos,scale;obs_sceneitem_get_pos(item,&pos);obs_sceneitem_get_scale(item,&scale);
            if(a[@"x"])pos.x=[a[@"x"] floatValue];if(a[@"y"])pos.y=[a[@"y"] floatValue];
            if(a[@"scaleX"])scale.x=[a[@"scaleX"] floatValue];if(a[@"scaleY"])scale.y=[a[@"scaleY"] floatValue];
            if(!std::isfinite(pos.x)||!std::isfinite(pos.y)||!std::isfinite(scale.x)||!std::isfinite(scale.y))return fail(e,"Transformação inválida.");
            cancelPlacement(item);obs_sceneitem_defer_update_begin(item);obs_sceneitem_set_pos(item,&pos);obs_sceneitem_set_scale(item,&scale);
            if(a[@"rotation"])obs_sceneitem_set_rot(item,[a[@"rotation"] floatValue]);
            obs_sceneitem_crop crop;obs_sceneitem_get_crop(item,&crop);
            if(a[@"cropLeft"])crop.left=std::max(0,[a[@"cropLeft"] intValue]);if(a[@"cropRight"])crop.right=std::max(0,[a[@"cropRight"] intValue]);
            if(a[@"cropTop"])crop.top=std::max(0,[a[@"cropTop"] intValue]);if(a[@"cropBottom"])crop.bottom=std::max(0,[a[@"cropBottom"] intValue]);
            obs_sceneitem_set_crop(item,&crop);obs_sceneitem_defer_update_end(item);return true;
        }
    }
    if([op hasPrefix:@"source."] || [op hasPrefix:@"audio."] || [op hasPrefix:@"filter."] || [op hasPrefix:@"media."]) {
        auto *source=obs_get_source_by_name([a[@"name"] UTF8String]);if(!source)return fail(e,"Fonte não encontrada.");
        bool result=true;
        if([op isEqual:@"source.update"]) {
            // Explicit repair for an old, not-yet-configured zero-sized capture.
            // Existing non-default composition is never repositioned by settings edits.
            if([a[@"autoPlace"] boolValue] && (!obs_source_get_width(source)||!obs_source_get_height(source))) {
                struct PlacementContext{dante_engine *engine;obs_source_t *source;} context={e,source};
                for(auto *candidate:e->scenes)obs_scene_enum_items(candidate,[](obs_scene_t *,obs_sceneitem_t *item,void *raw){
                    auto *ctx=static_cast<PlacementContext*>(raw);if(obs_sceneitem_get_source(item)!=ctx->source||obs_sceneitem_locked(item))return true;
                    vec2 pos,scale;obs_sceneitem_get_pos(item,&pos);obs_sceneitem_get_scale(item,&scale);obs_sceneitem_crop crop;obs_sceneitem_get_crop(item,&crop);
                    if(pos.x==0&&pos.y==0&&scale.x==1&&scale.y==1&&obs_sceneitem_get_rot(item)==0&&obs_sceneitem_get_bounds_type(item)==OBS_BOUNDS_NONE&&!crop.left&&!crop.right&&!crop.top&&!crop.bottom)requestPlacement(ctx->engine,item,0);
                    return true;
                },&context);
            }
            auto *data=settings(a[@"settings"]);obs_source_update(source,data);obs_data_release(data);
        }
        else if([op isEqual:@"source.rename"]) {if(!uniqueName(a[@"newName"]))result=fail(e,"Escolha um nome exclusivo.");else obs_source_set_name(source,[a[@"newName"] UTF8String]);}
        else if([op isEqual:@"audio.set"]) {
            if(a[@"volume"])obs_source_set_volume(source,std::clamp([a[@"volume"] floatValue],0.f,20.f));
            if(a[@"muted"])obs_source_set_muted(source,[a[@"muted"] boolValue]);
            if(a[@"syncMS"])obs_source_set_sync_offset(source,[a[@"syncMS"] longLongValue]*1000000);
            if(a[@"tracks"])obs_source_set_audio_mixers(source,[a[@"tracks"] unsignedIntValue]&63);
            if(a[@"monitoring"])obs_source_set_monitoring_type(source,(obs_monitoring_type)std::clamp([a[@"monitoring"] intValue],0,2));
        } else if([op isEqual:@"filter.add"]) {
            if(!registeredType(a[@"type"],OBS_SOURCE_TYPE_FILTER)){obs_source_release(source);return fail(e,"Tipo de filtro não registrado no motor.");}
            auto *existing=obs_source_get_filter_by_name(source,[a[@"filter"] UTF8String]);
            if(existing) {obs_source_release(existing);result=fail(e,"Já existe um filtro com esse nome.");}
            else {auto *data=settings(a[@"settings"]);auto *filter=obs_source_create_private([a[@"type"] UTF8String],[a[@"filter"] UTF8String],data);obs_data_release(data);
                if(filter){obs_source_filter_add(source,filter);obs_source_release(filter);}else result=fail(e,"Filtro indisponível.");}
        } else if([op isEqual:@"filter.update"] || [op isEqual:@"filter.remove"]) {
            auto *filter=obs_source_get_filter_by_name(source,[a[@"filter"] UTF8String]);
            if(!filter)result=fail(e,"Filtro não encontrado.");
            else {if([op isEqual:@"filter.remove"])obs_source_filter_remove(source,filter);
                else {auto *data=settings(a[@"settings"]);obs_source_update(filter,data);obs_data_release(data);}obs_source_release(filter);}
        } else if([op isEqual:@"media.play"])obs_source_media_play_pause(source,false);
        else if([op isEqual:@"media.pause"])obs_source_media_play_pause(source,true);
        else if([op isEqual:@"media.restart"])obs_source_media_restart(source);
        else if([op isEqual:@"media.stop"])obs_source_media_stop(source);
        else if([op isEqual:@"media.seek"])obs_source_media_set_time(source,[a[@"milliseconds"] longLongValue]);
        else result=fail(e,"Comando desconhecido.");
        obs_source_release(source);return result;
    }
    if([op isEqual:@"recording.start"])return startOutput(e,e->recording,@"recording",a);
    if([op isEqual:@"stream.start"])return startOutput(e,e->streaming,@"stream",a);
    if([op isEqual:@"replay.start"])return startOutput(e,e->replay,@"replay",a);
    Output *output=[op isEqual:@"recording.stop"] ? &e->recording : [op isEqual:@"stream.stop"] ? &e->streaming : [op isEqual:@"replay.stop"] ? &e->replay : nullptr;
    if(output) {
        output->cancelRequested=true;
        if(output->output && busy(*output) && !output->stopWorkerRunning) {
            if(output->stopWorker.joinable())output->stopWorker.join();
            output->stopping=true;output->stopWorkerRunning=true;
            auto *retained=obs_output_get_ref(output->output);
            bool force=output->starting || obs_output_reconnecting(retained);
            output->stopWorker=std::thread([output,retained,force]{
                // Patched RTMP backend joins its connector exactly once. The
                // join/socket timeout must not block the application's owner.
                if(force)obs_output_force_stop(retained);else obs_output_stop(retained);
                // A failure callback can race the owner's stop request before
                // obs_output_stop sees an active output. In that case no later
                // stop signal is required; clear only the already-idle state.
                if(!obs_output_active(retained) && !output->starting && !output->started)output->stopping=false;
                obs_output_release(retained);output->stopWorkerRunning=false;
            });
        }
        return true;
    }
    if([op isEqual:@"replay.save"]) {
        if(!e->replay.output || !obs_output_active(e->replay.output))return fail(e,"O replay não está ativo.");
        calldata_t cd;calldata_init(&cd);bool result=proc_handler_call(obs_output_get_proc_handler(e->replay.output),"save",&cd);calldata_free(&cd);return result;
    }
    return fail(e,"Comando desconhecido.");
}

const char *dante_engine_save(dante_engine_t *e) {
    if(!e)return "{}";obs_data_t *data=obs_data_create();auto *sources=obs_save_sources();obs_data_set_array(data,"sources",sources);obs_data_array_release(sources);
    NSMutableArray *order=[NSMutableArray array];for(auto *scene:e->scenes)[order addObject:S(obs_source_get_name(obs_scene_get_source(scene)))];
    NSMutableDictionary *project=[jsonSettings(data) mutableCopy];obs_data_release(data);
    project[@"format"]=@"DanteLive";project[@"version"]=@1;project[@"sceneOrder"]=order;
    project[@"selectedScene"]=S(obs_source_get_name(obs_scene_get_source(e->selected)));project[@"programScene"]=S(obs_source_get_name(obs_scene_get_source(e->program)));
    project[@"width"]=@(e->width);project[@"height"]=@(e->height);project[@"fps"]=@(e->fps);
    e->scratch=J(project);return e->scratch.c_str();
}
bool dante_engine_load(dante_engine_t *e,const char *json) {
    if(!e)return false;if(active(e))return fail(e,"Pare as saídas antes de abrir outro projeto.");
    id root=parse(json);if(![root isKindOfClass:NSDictionary.class] || ![root[@"sources"] isKindOfClass:NSArray.class])return fail(e,"Projeto inválido: fontes ausentes.");
    if(root[@"format"] && ![root[@"format"] isEqual:@"DanteLive"])return fail(e,"Formato de projeto não reconhecido.");
    if(root[@"version"] && (![root[@"version"] isKindOfClass:NSNumber.class] || [root[@"version"] intValue]!=1))return fail(e,"Versão de projeto não suportada.");
    for(NSString *key in @[@"width",@"height",@"fps"])if(root[key] && ![root[key] isKindOfClass:NSNumber.class])return fail(e,"Configuração de vídeo inválida no projeto.");
    uint32_t width=root[@"width"] ? [root[@"width"] unsignedIntValue] : e->width;
    uint32_t height=root[@"height"] ? [root[@"height"] unsignedIntValue] : e->height;
    uint32_t fps=root[@"fps"] ? [root[@"fps"] unsignedIntValue] : e->fps;
    if(width<16||height<16||width>8192||height>8192||width%2||height%2||fps<1||fps>120)return fail(e,"Configuração de vídeo fora dos limites.");
    bool hasScene=false;NSMutableSet *names=[NSMutableSet set],*uuids=[NSMutableSet set];
    size_t expectedScenes=0;
    if([root[@"sources"] count]>10000)return fail(e,"Projeto excede o limite de 10000 fontes.");
    for(id source in root[@"sources"]) {
        if(![source isKindOfClass:NSDictionary.class] || ![source[@"name"] isKindOfClass:NSString.class] || ![source[@"name"] length] ||
            ![source[@"id"] isKindOfClass:NSString.class] || (source[@"settings"] && ![source[@"settings"] isKindOfClass:NSDictionary.class]))
            return fail(e,"Projeto contém uma definição de fonte inválida.");
        if([names containsObject:source[@"name"]])return fail(e,"Projeto contém nomes de fontes duplicados.");[names addObject:source[@"name"]];
        if([source[@"uuid"] isKindOfClass:NSString.class]){if([uuids containsObject:source[@"uuid"]])return fail(e,"UUID de fonte duplicado.");[uuids addObject:source[@"uuid"]];}
        NSString *effective=source[@"versioned_id"] ?: source[@"id"];
        if(![effective isKindOfClass:NSString.class])return fail(e,"Versão de fonte inválida.");
        if([effective isEqual:@"scene"]){hasScene=true;expectedScenes++;}
        else if(![effective isEqual:@"group"] && !registeredType(effective,OBS_SOURCE_TYPE_INPUT))return fail(e,"Projeto usa uma fonte não disponível. Preserve o original e remova ou adapte os itens incompatíveis.");
        if(source[@"filters"] && ![source[@"filters"] isKindOfClass:NSArray.class])return fail(e,"Lista de filtros inválida.");
        for(id filter in source[@"filters"]) {
            if(![filter isKindOfClass:NSDictionary.class] || !registeredType(filter[@"versioned_id"] ?: filter[@"id"],OBS_SOURCE_TYPE_FILTER) ||
                ![filter[@"name"] isKindOfClass:NSString.class] || (filter[@"settings"] && ![filter[@"settings"] isKindOfClass:NSDictionary.class]) ||
                (filter[@"filters"] && (![filter[@"filters"] isKindOfClass:NSArray.class] || [filter[@"filters"] count])))
                return fail(e,"Filtro incompatível ou definição de filtro inválida.");
        }
    }
    if(!hasScene)return fail(e,"O projeto não contém cenas.");
    for(NSDictionary *source in root[@"sources"])if([source[@"id"] isEqual:@"scene"] || [source[@"id"] isEqual:@"group"]) {
        id items=source[@"settings"][@"items"];
        if(items && ![items isKindOfClass:NSArray.class])return fail(e,"Lista de elementos inválida.");
        for(id item in items)if(![item isKindOfClass:NSDictionary.class] ||
            !([names containsObject:item[@"name"] ?: @""] || [uuids containsObject:item[@"source_uuid"] ?: @""]))return fail(e,"Cena referencia uma fonte ausente.");
    }
    std::string backup=dante_engine_save(e);
    if(!configureVideo(e,width,height,fps))return false;
    auto *previous=e->selected;
    {std::lock_guard<std::mutex> lock(e->previewLock);e->selected=e->program=nullptr;}
    clearMeters(e);obs_transition_clear(e->transition);if(previous)obs_source_dec_showing(obs_scene_get_source(previous));
    for(auto *scene:e->scenes){obs_source_remove(obs_scene_get_source(scene));obs_scene_release(scene);}e->scenes.clear();
    // Flush deferred source destruction before loading names again.
    obs_wait_for_destroy_queue();
    obs_data_t *data=obs_data_create_from_json(json);auto *sources=obs_data_get_array(data,"sources");
    obs_load_sources(sources,[](void *ptr,obs_source_t *source){
        auto *engine=static_cast<dante_engine*>(ptr);if(obs_source_is_scene(source))engine->scenes.push_back(obs_scene_get_ref(obs_scene_from_source(source)));
    },e);
    obs_data_array_release(sources);obs_data_release(data);
    if(e->scenes.size()!=expectedScenes) {
        if(e->scenes.empty())e->scenes.push_back(obs_scene_create("Cena recuperada"));
        {std::lock_guard<std::mutex> lock(e->previewLock);e->selected=e->program=e->scenes.front();}
        obs_source_inc_showing(obs_scene_get_source(e->selected));obs_transition_set(e->transition,obs_scene_get_source(e->program));
        if(!e->recovering){e->recovering=true;bool restored=dante_engine_load(e,backup.c_str());e->recovering=false;return fail(e,restored ? "Falha ao carregar as cenas. O projeto anterior foi restaurado." : "Falha ao carregar e restaurar. Reabra o último projeto salvo.");}
        return fail(e,"Falha na recuperação do projeto anterior.");
    }
    NSArray *order=root[@"sceneOrder"];
    if([order isKindOfClass:NSArray.class])std::stable_sort(e->scenes.begin(),e->scenes.end(),[order](obs_scene_t *a,obs_scene_t *b){return [order indexOfObject:S(obs_source_get_name(obs_scene_get_source(a)))] < [order indexOfObject:S(obs_source_get_name(obs_scene_get_source(b)))];});
    auto *selected=findScene(e,root[@"selectedScene"] ?: root[@"current_scene"]);if(!selected)selected=e->scenes.front();
    auto *program=findScene(e,root[@"programScene"]);if(!program)program=selected;
    {std::lock_guard<std::mutex> lock(e->previewLock);e->selected=selected;e->program=program;}
    obs_source_inc_showing(obs_scene_get_source(e->selected));
    obs_transition_set(e->transition,obs_scene_get_source(e->program));e->error.clear();return true;
}
struct Preview { dante_engine *engine;obs_display_t *display;bool program;obs_source_t *source=nullptr; };
static void drawPreview(void *data,uint32_t width,uint32_t height) {
    auto *p=static_cast<Preview*>(data);auto *e=p->engine;
    obs_source_t *source=nullptr;
    uint32_t canvasWidth,canvasHeight;
    if(p->source){source=obs_source_get_ref(p->source);canvasWidth=obs_source_get_width(source);canvasHeight=obs_source_get_height(source);}
    else {std::lock_guard<std::mutex> lock(e->previewLock);source=obs_source_get_ref(p->program ? e->transition : e->selected ? obs_scene_get_source(e->selected) : nullptr);canvasWidth=e->width;canvasHeight=e->height;}
    if(!source || !canvasWidth || !canvasHeight){obs_source_release(source);return;}
    float scale=std::min((float)width/canvasWidth,(float)height/canvasHeight);
    int w=round(canvasWidth*scale),h=round(canvasHeight*scale);
    gs_viewport_push();gs_projection_push();gs_set_viewport((width-w)/2,(height-h)/2,w,h);gs_ortho(0,canvasWidth,0,canvasHeight,-100,100);
    obs_source_video_render(source);gs_projection_pop();gs_viewport_pop();obs_source_release(source);
}
void *dante_engine_preview_create(dante_engine_t *e,void *nsview,bool program) {
    if(!e || !nsview)return nullptr;
    NSView *view=(__bridge NSView*)nsview;NSRect bounds=[view convertRectToBacking:view.bounds];
    gs_init_data data={};data.window.view=view;data.cx=std::max(1,(int)bounds.size.width);data.cy=std::max(1,(int)bounds.size.height);data.format=GS_BGRA;data.zsformat=GS_ZS_NONE;
    auto *display=obs_display_create(&data,0x181818);if(!display){fail(e,"Não foi possível criar o preview.");return nullptr;}
    auto *p=new Preview{e,display,program};obs_display_add_draw_callback(display,drawPreview,p);return p;
}
void *dante_engine_source_preview_create(dante_engine_t *e,void *nsview,const char *name) {
    if(!e || !nsview || !name)return nullptr;
    auto *source=obs_get_source_by_name(name);if(!source){fail(e,"Fonte não encontrada para o preview.");return nullptr;}
    NSView *view=(__bridge NSView*)nsview;NSRect bounds=[view convertRectToBacking:view.bounds];
    gs_init_data data={};data.window.view=view;data.cx=std::max(1,(int)bounds.size.width);data.cy=std::max(1,(int)bounds.size.height);data.format=GS_BGRA;data.zsformat=GS_ZS_NONE;
    auto *display=obs_display_create(&data,0x181818);
    if(!display){obs_source_release(source);fail(e,"Não foi possível criar o preview da fonte.");return nullptr;}
    obs_source_inc_showing(source);auto *preview=new Preview{e,display,false,source};
    obs_display_add_draw_callback(display,drawPreview,preview);return preview;
}
void dante_engine_preview_resize(void *preview,uint32_t width,uint32_t height) {if(preview)obs_display_resize(static_cast<Preview*>(preview)->display,std::max(1u,width),std::max(1u,height));}
void dante_engine_preview_destroy(void *preview) {if(!preview)return;auto *p=static_cast<Preview*>(preview);obs_display_remove_draw_callback(p->display,drawPreview,p);obs_display_destroy(p->display);if(p->source){obs_source_dec_showing(p->source);obs_source_release(p->source);}delete p;}
