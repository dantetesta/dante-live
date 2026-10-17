#include "../Sources/Bridge/DanteEngine.h"
// Test-only acoustic loop: delayed guest PCM + independent synthetic host voice.
#ifdef __cplusplus
extern "C" {
#endif
void *guest_echo_fixture_start(const char *guest, const char *scene);
void guest_echo_fixture_stop(void *fixture);
#ifdef __cplusplus
}
#endif
