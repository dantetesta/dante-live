#pragma once
#include <obs.h>
#include <util/platform.h>
#include <algorithm>
#include <cmath>
#include <vector>

namespace DanteBrowserTabAudio {
inline void *create(obs_data_t *, obs_source_t *source) { return source; }
inline void destroy(void *) {}
inline void registerSource() {
    obs_source_info info = {};
    info.id = "dante_browser_tab_audio";
    info.type = OBS_SOURCE_TYPE_INPUT;
    info.output_flags = OBS_SOURCE_AUDIO | OBS_SOURCE_DO_NOT_DUPLICATE;
    info.get_name = [](void *) { return "Áudio de aba do navegador"; };
    info.create = create;
    info.destroy = destroy;
    obs_register_source(&info);
}
inline bool output(const char *name, const float *samples, uint32_t frames, uint32_t rate) {
    if (!name || !samples || !frames || frames > 8192 || rate < 16000 || rate > 96000) return false;
    obs_source_t *source = obs_get_source_by_name(name);
    if (!source) return false;
    bool valid = strcmp(obs_source_get_unversioned_id(source), "dante_browser_tab_audio") == 0;
    if (valid) {
        std::vector<float> safe(frames);
        for (uint32_t i = 0; i < frames; ++i)
            safe[i] = std::isfinite(samples[i]) ? std::clamp(samples[i], -1.f, 1.f) : 0.f;
        obs_source_audio audio = {};
        audio.data[0] = reinterpret_cast<uint8_t *>(safe.data());
        audio.frames = frames;
        audio.samples_per_sec = rate;
        audio.speakers = SPEAKERS_MONO;
        audio.format = AUDIO_FORMAT_FLOAT;
        audio.timestamp = os_gettime_ns();
        obs_source_output_audio(source, &audio);
    }
    obs_source_release(source);
    return valid;
}
}
