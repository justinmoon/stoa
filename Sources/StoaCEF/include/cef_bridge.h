#ifndef STOA_CEF_BRIDGE_H
#define STOA_CEF_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct stoa_cef_browser stoa_cef_browser_t;

typedef void (*stoa_cef_paint_callback)(
    void* user_data,
    int width,
    int height,
    const void* buffer,
    int buffer_length
);

enum stoa_cef_key_event_type {
    STOA_CEF_KEY_RAW_DOWN = 0,
    STOA_CEF_KEY_DOWN = 1,
    STOA_CEF_KEY_UP = 2,
    STOA_CEF_KEY_CHAR = 3,
};

enum stoa_cef_mouse_button {
    STOA_CEF_MOUSE_LEFT = 0,
    STOA_CEF_MOUSE_MIDDLE = 1,
    STOA_CEF_MOUSE_RIGHT = 2,
};

bool stoa_cef_initialize(
    int argc,
    char** argv,
    const char* framework_path,
    const char* resources_path,
    const char* locales_path,
    const char* cache_path,
    int remote_debugging_port
);
int stoa_cef_execute_process(int argc, char** argv);
void stoa_cef_shutdown(void);
void stoa_cef_do_message_loop_work(void);

stoa_cef_browser_t* stoa_cef_browser_create(
    const char* url,
    int width,
    int height,
    void* parent_view,
    float device_scale_factor,
    void* user_data,
    stoa_cef_paint_callback paint_cb
);
void stoa_cef_browser_destroy(stoa_cef_browser_t* browser);
void stoa_cef_browser_resize(stoa_cef_browser_t* browser, int width, int height);
void stoa_cef_browser_load_url(stoa_cef_browser_t* browser, const char* url);
void stoa_cef_browser_set_device_scale(stoa_cef_browser_t* browser, float device_scale_factor);
void stoa_cef_browser_set_focus(stoa_cef_browser_t* browser, bool focus);

void stoa_cef_browser_send_key_event(
    stoa_cef_browser_t* browser,
    int type,
    int modifiers,
    uint32_t character,
    uint32_t unmodified_character,
    uint32_t native_key_code
);
void stoa_cef_browser_send_mouse_move(
    stoa_cef_browser_t* browser,
    int x,
    int y,
    int modifiers,
    bool mouse_leave
);
void stoa_cef_browser_send_mouse_click(
    stoa_cef_browser_t* browser,
    int x,
    int y,
    int modifiers,
    int button,
    bool mouse_up,
    int click_count
);
void stoa_cef_browser_send_mouse_wheel(
    stoa_cef_browser_t* browser,
    int x,
    int y,
    int modifiers,
    int delta_x,
    int delta_y
);

#ifdef __cplusplus
}
#endif

#endif
