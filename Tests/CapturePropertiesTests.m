// Exercise the actual upstream callbacks without requesting screen permission or
// touching a running application. Only graphics entry and content discovery are stubbed.
#define obs_enter_graphics capture_test_enter
#define obs_leave_graphics capture_test_leave
#include "mac-sck-video-capture.m"
#include <assert.h>

static int restarts;
void capture_test_enter(void) { restarts++; }
void capture_test_leave(void) {}
const char *obs_module_text(const char *key) { return key; }
void screen_capture_build_content_list(struct screen_capture *sc, bool display) {}
bool build_display_list(struct screen_capture *sc, obs_properties_t *props) { return true; }
bool build_window_list(struct screen_capture *sc, obs_properties_t *props) { return true; }
bool build_application_list(struct screen_capture *sc, obs_properties_t *props) { return true; }
CGDirectDisplayID get_display_migrate_settings(obs_data_t *settings) { return 0; }
@implementation ScreenCaptureDelegate
@end

int main(void) {
    @autoreleasepool {
        struct screen_capture sc = {0};
        os_sem_init(&sc.shareable_content_available, 1);
        obs_properties_t *props = sck_video_capture_properties(&sc);
        obs_data_t *settings = obs_data_create();
        obs_data_set_bool(settings, "show_cursor", true);
        // The inspector previews a candidate before source.update and also reads
        // properties while libobs may have a deferred video-thread update.
        obs_data_set_bool(settings, "hide_obs", true);
        obs_properties_apply_settings(props, settings);
        assert(!sc.hide_obs && "Inspector must not commit the running exclusion state");
        sck_video_capture_update(&sc, settings);
        assert(sc.hide_obs && restarts == 1);
        obs_properties_apply_settings(props, settings);
        sck_video_capture_update(&sc, settings);
        assert(restarts == 1 && "An unchanged checkbox must not restart capture");
        obs_data_set_bool(settings, "hide_obs", false);
        obs_properties_apply_settings(props, settings);
        assert(sc.hide_obs);
        sck_video_capture_update(&sc, settings);
        assert(!sc.hide_obs && restarts == 2);
        obs_data_set_bool(settings, "hide_obs", true);
        obs_data_t *saved = obs_data_create_from_json(obs_data_get_json(settings));
        obs_properties_apply_settings(props, saved);
        sck_video_capture_update(&sc, saved);
        assert(sc.hide_obs && restarts == 3);
        destroy_screen_stream(&sc);
        os_sem_destroy(sc.shareable_content_available);
        [sc.application_id release];
        obs_properties_destroy(props);
        obs_data_release(settings); obs_data_release(saved);
        puts("PASS: capture inspector cannot consume hide-host changes; on/off/reload rebuild filter exactly once; no devices or screen capture opened");
    }
}
