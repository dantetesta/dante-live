#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct dante_engine dante_engine_t;
/* Main-thread/serial-owner API. One engine per process. Never uses OBS user config.
 * Returned strings are borrowed until next JSON/error call; copy immediately.
 * create returns NULL on failure; last_error(NULL) gives initialization error.
 * Destroy all previews before engine. Destroy stops this engine's own outputs.
 */
dante_engine_t *dante_engine_create(const char *app_bundle_path, uint32_t width, uint32_t height, uint32_t fps);
/* Explicit, absolute isolated module-config directory for test harnesses. NULL
 * uses this user's Application Support/Dante Live/engine, never OBS settings. */
dante_engine_t *dante_engine_create_with_config(const char *app_bundle_path, uint32_t width, uint32_t height, uint32_t fps, const char *module_config_directory);
void dante_engine_destroy(dante_engine_t *engine);
/* Ephemeral premultiplied RGBA overlay pixels; copied synchronously, never serialized. Main thread. */
bool dante_chat_frame(const char *name, const uint8_t *pixels, uint32_t width, uint32_t height, uint32_t stride, bool animate);
/* Browser-selected tab PCM. Borrowed mono float32 samples are copied by libobs.
 * Call only on the serialized engine owner (main thread). */
bool dante_browser_tab_audio_frame(const char *name, const float *samples, uint32_t frames, uint32_t sample_rate);
const char *dante_engine_last_error(dante_engine_t *engine);
const char *dante_engine_state(dante_engine_t *engine);
/* Lightweight meter snapshot for UI polling; no full scene enumeration. */
const char *dante_engine_audio_levels(dante_engine_t *engine);
const char *dante_engine_catalog(dante_engine_t *engine);
const char *dante_engine_properties(dante_engine_t *engine, const char *source_name);
const char *dante_engine_type_properties(dante_engine_t *engine, const char *source_type);
const char *dante_engine_filter_properties(dante_engine_t *engine, const char *source_name, const char *filter_name);
const char *dante_engine_type_properties_with_settings(dante_engine_t *engine, const char *source_type, const char *candidate_json);
const char *dante_engine_properties_with_settings(dante_engine_t *engine, const char *source_name, const char *candidate_json);
/* Commands and argument keys. Omitted optional keys retain existing state.
 * scene.create {name}; scene.rename {scene,name}; scene.duplicate {scene,name};
 * scene.delete {scene}; scene.select {scene,studio?:bool}; scene.take {scene?,duration?:ms,transition?:"fade"|"cut"};
 * scene.order {scene,index}; source.add {scene,type,name,settings?:object};
 * source.reuse {scene,name}; source.update {name,settings:object,autoPlace?:bool}; source.rename {name,newName};
 * source.cameraMask {name,settings:{shape:0...6,aspect?:ratio,roundness?:0...1,zoom?:1...4,panX?:-1...1,panY?:-1...1}};
 * shape 0 removes the native filter; 1 square, 2 oval, 3 circle, 4 rounded square, 5 rectangle, 6 rounded rectangle.
 * source.remove {scene,id}; item.transform {scene,id,x?,y?,scaleX?,scaleY?,rotation?,cropLeft?,cropRight?,cropTop?,cropBottom?};
 * item.fit/item.native/item.center {scene,id}; item.visible/item.locked {scene,id,value:bool}; item.order {scene,id,index};
 * audio.set {name,volume?:linear,muted?:bool,syncMS?:number,tracks?:bitmask,monitoring?:0|1|2};
 * filter.add {name,type,filter,settings?:object}; filter.update {name,filter,settings:object}; filter.remove {name,filter};
 * media.play/pause/restart/stop {name}; media.seek {name,milliseconds};
 * recording.start {path:absoluteMKVPath,encoder?:id,bitrate?:kbps,audioBitrate?:kbps}; recording.stop {};
 * stream.start {server,key,encoder?:id,bitrate?:kbps,audioBitrate?:kbps}; stream.stop {};
 * replay.start {directory,seconds?:20,encoder?:id,bitrate?:kbps,audioBitrate?:kbps}; replay.save {}; replay.stop {}.
 * audioBitrate accepts 128,160,192,256,320; defaults stream128 / recording+replay160.
 * state.outputs.<kind>.settings reads actual encoder configuration using libobs:
 * bitrate, audioBitrate (kbps), keyframeSeconds, rateControl. It is not a measured bitrate.
 * video.configure {width,height,fps}: idle only; restores old configuration if reset fails.
 * Output starts return actual obs_output_start result; asynchronous failure is in state outputs/error.
 * New visual items center at native size, downscaled only if larger than canvas.
 * item.fit scales to canvas, item.native resets crop/rotation/scale and centers;
 * item.center preserves transform and centers its visible box. Unknown dimensions
 * queue placement until state polling sees video; user transforms cancel it.
 * source.update autoPlace repairs only zero-sized items with untouched default
 * transforms; it is an explicit opt-in for configuring legacy saved captures.
 * state item pendingPlacement / awaitingVideo expose that pending state.
 * A source type exists only when its module loaded. No capture or output auto-starts.
 */
bool dante_engine_command(dante_engine_t *engine, const char *operation, const char *arguments_json);
const char *dante_engine_save(dante_engine_t *engine);
bool dante_engine_load(dante_engine_t *engine, const char *project_json);
/* nsview borrowed; caller keeps NSView alive until preview_destroy. Pixel sizes. */
void *dante_engine_preview_create(dante_engine_t *engine, void *nsview, bool program);
/* Existing source only; retains it and balances showing until preview_destroy.
 * Source fills this preview proportionally without changing any scene item. */
void *dante_engine_source_preview_create(dante_engine_t *engine, void *nsview, const char *source_name);
void dante_engine_preview_resize(void *preview, uint32_t width, uint32_t height);
void dante_engine_preview_destroy(void *preview);
#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import "DanteGuestRTC.h"
#endif
