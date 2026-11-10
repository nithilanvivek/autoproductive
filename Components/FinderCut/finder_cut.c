#include <stdint.h>

// No input text is retained. The marker contains only the pasteboard change
// count for the last Finder cut, matching the existing in-memory behavior.
static int64_t cut_change_count = -1;

int32_t autoproductive_tool_api_version(void) { return 1; }
const char *autoproductive_tool_feature_id(void) { return "tool.finderCut"; }
void autoproductive_finder_cut_reset(void) { cut_change_count = -1; }
int32_t autoproductive_finder_cut_pending(void) { return cut_change_count >= 0; }
int32_t autoproductive_finder_cut_matches(int64_t count) { return cut_change_count >= 0 && cut_change_count == count; }
void autoproductive_finder_cut_mark(int64_t count, int32_t has_files) {
    cut_change_count = has_files ? count : -1;
}
// 0 passes input through; 1 performs Finder copy; 2 performs Finder move.
int32_t autoproductive_finder_cut_decide(int32_t key, int64_t count, int32_t has_files) {
    if (key == 7) { cut_change_count = -1; return 1; }
    if (key == 9 && cut_change_count >= 0 && cut_change_count == count && has_files) {
        cut_change_count = -1;
        return 2;
    }
    if (key == 8) cut_change_count = -1;
    return 0;
}
