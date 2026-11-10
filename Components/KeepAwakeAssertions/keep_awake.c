#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

static IOPMAssertionID system_assertion = 0;
static IOPMAssertionID display_assertion = 0;
int32_t autoproductive_tool_api_version(void) { return 1; }
const char *autoproductive_tool_feature_id(void) { return "tool.keepAwake"; }
void autoproductive_keep_awake_stop(void) {
    if (system_assertion) IOPMAssertionRelease(system_assertion);
    if (display_assertion) IOPMAssertionRelease(display_assertion);
    system_assertion = 0;
    display_assertion = 0;
}
int32_t autoproductive_keep_awake_start(int32_t display_may_sleep, int32_t *system_error, int32_t *display_error) {
    autoproductive_keep_awake_stop();
    if (system_error) *system_error = 0;
    if (display_error) *display_error = 0;
    IOReturn result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn, CFSTR("AutoProductive Keep Awake"), &system_assertion);
    if (result != kIOReturnSuccess) {
        system_assertion = 0;
        if (system_error) *system_error = result;
        return 0;
    }
    if (!display_may_sleep) {
        result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionLevelOn, CFSTR("AutoProductive Keep Display Awake"), &display_assertion);
        if (result != kIOReturnSuccess) {
            if (display_error) *display_error = result;
            autoproductive_keep_awake_stop();
            return 0;
        }
    }
    return 1;
}
uint32_t autoproductive_keep_awake_system_assertion(void) { return system_assertion; }
uint32_t autoproductive_keep_awake_display_assertion(void) { return display_assertion; }
