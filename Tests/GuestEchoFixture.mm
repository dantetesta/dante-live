#include "GuestHarnessBridge.h"
#include <obs.h>
#include <util/platform.h>
#include <dispatch/dispatch.h>
#include <array>
#include <mutex>
#include <cmath>

// No real microphone, speakers, system capture, or output stream. Recreates the
// guest -> host speaker -> host microphone path which a direct mix-minus test
// misses. Only linked into GuestHarness, never the application.
struct GuestEchoFixture {
    obs_source_t *guest=nullptr, *host=nullptr;
    obs_sceneitem_t *item=nullptr;
    dispatch_queue_t queue;
    dispatch_source_t timer;
    std::mutex mutex;
    std::array<float, 48000> samples{};
    uint64_t read=0, written=7680, frame=0; // 160 ms acoustic/monitor delay.
};
static void captureEcho(void *raw, obs_source_t *, const audio_data *data, bool muted) {
    auto *f=static_cast<GuestEchoFixture *>(raw);
    const float *left=reinterpret_cast<const float *>(data->data[0]);
    std::lock_guard<std::mutex> lock(f->mutex);
    if(f->written-f->read+data->frames>f->samples.size())return;
    for(uint32_t i=0;i<data->frames;i++)f->samples[(f->written++)%f->samples.size()]=muted?0:left[i]*.45f;
}
void *guest_echo_fixture_start(const char *guest, const char *scene) {
    auto *f=new GuestEchoFixture;
    f->guest=obs_get_source_by_name(guest);
    auto *s=obs_get_source_by_name(scene);
    auto *target=s?obs_scene_from_source(s):nullptr;
    if(!f->guest||!target){if(s)obs_source_release(s);obs_source_release(f->guest);delete f;return nullptr;}
    f->host=obs_source_create("dante_guest_audio","Synthetic host echo QA",nullptr,nullptr);
    if(!f->host){obs_source_release(s);obs_source_release(f->guest);delete f;return nullptr;}
    obs_source_set_audio_mixers(f->host,63);
    f->item=obs_scene_add(target,f->host);obs_source_release(s);
    obs_source_add_audio_capture_callback(f->guest,captureEcho,f);
    f->queue=dispatch_queue_create("com.dantetesta.qa.echo",DISPATCH_QUEUE_SERIAL);
    f->timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,f->queue);
    dispatch_source_set_timer(f->timer,dispatch_time(DISPATCH_TIME_NOW,0),10*NSEC_PER_MSEC,NSEC_PER_MSEC);
    dispatch_source_set_event_handler(f->timer,^{
        float samples[480];
        {
            std::lock_guard<std::mutex> lock(f->mutex);
            for(auto &sample:samples){
                sample=f->read<f->written?f->samples[(f->read++)%f->samples.size()]:0;
                sample+=.08f*std::sin(2*M_PI*1320*(f->frame++)/48000.0);
            }
        }
        obs_source_audio audio={};audio.data[0]=reinterpret_cast<uint8_t *>(samples);
        audio.frames=480;audio.samples_per_sec=48000;audio.speakers=SPEAKERS_MONO;
        audio.format=AUDIO_FORMAT_FLOAT;audio.timestamp=os_gettime_ns();
        obs_source_output_audio(f->host,&audio);
    });
    dispatch_resume(f->timer);return f;
}
void guest_echo_fixture_stop(void *raw) {
    if(!raw)return;auto *f=static_cast<GuestEchoFixture *>(raw);
    obs_source_remove_audio_capture_callback(f->guest,captureEcho,f);
    dispatch_source_cancel(f->timer);dispatch_sync(f->queue,^{});
    obs_sceneitem_remove(f->item);obs_source_release(f->host);obs_source_release(f->guest);delete f;
}
