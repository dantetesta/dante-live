/* Dante Live integration, GPL-2.0-or-later.
 * Registers only the pinned OBS custom-service implementation. No service
 * catalog updater, ingest discovery, OAuth or background network requests.
 */
#include <obs-module.h>
OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("rtmp-services", "en-US")
extern struct obs_service_info rtmp_custom_service;
MODULE_EXPORT const char *obs_module_description(void)
{
    return "Dante Live manual streaming service (no background updater)";
}
bool obs_module_load(void)
{
    obs_register_service(&rtmp_custom_service);
    return true;
}
