#include "cef_bridge.h"

#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/cef_api_hash.h"
#include "include/internal/cef_string_types.h"
#include "include/internal/cef_types.h"
#include "include/internal/cef_types_mac.h"

#include <atomic>
#include <cstring>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <string>

static void stoa_set_utf16(cef_string_t* output, const char* input) {
    if (!output || !input) {
        return;
    }
    const size_t len = std::char_traits<char>::length(input);
    std::u16string utf16;
    utf16.reserve(len);
    for (size_t i = 0; i < len; ++i) {
        utf16.push_back(static_cast<unsigned char>(input[i]));
    }
    cef_string_utf16_set(utf16.data(), utf16.size(), output, 1);
}

static void stoa_ensure_cef_api_version(void) {
    const char* api_hash = cef_api_hash(CEF_API_VERSION, 0);
    if (!api_hash) {
        fprintf(stderr, "CEF api hash unavailable\n");
        return;
    }
    if (std::strcmp(api_hash, CEF_API_HASH_PLATFORM) != 0) {
        fprintf(stderr, "CEF api hash mismatch\n");
    }
}

struct stoa_cef_browser;
struct stoa_cef_app;

struct stoa_cef_render_handler {
    cef_render_handler_t handler;
    std::atomic<int> refct;
    stoa_cef_browser* owner;
};

struct stoa_cef_life_span_handler {
    cef_life_span_handler_t handler;
    std::atomic<int> refct;
    stoa_cef_browser* owner;
};

struct stoa_cef_client {
    cef_client_t client;
    std::atomic<int> refct;
    stoa_cef_render_handler* render_handler;
    stoa_cef_life_span_handler* life_span_handler;
};

struct stoa_cef_browser {
    int width;
    int height;
    float device_scale_factor;
    void* user_data;
    stoa_cef_paint_callback paint_cb;
    cef_browser_t* browser;
    stoa_cef_client* client;
    std::string pending_url;
};

struct stoa_cef_app {
    cef_app_t app;
    std::atomic<int> refct;
};

static void CEF_CALLBACK client_add_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_client*>(base);
    self->refct.fetch_add(1);
}

static int CEF_CALLBACK client_release(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_client*>(base);
    if (self->refct.fetch_sub(1) == 1) {
        delete self;
        return 1;
    }
    return 0;
}

static int CEF_CALLBACK client_has_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_client*>(base);
    return self->refct.load() == 1;
}

static int CEF_CALLBACK client_has_at_least_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_client*>(base);
    return self->refct.load() >= 1;
}

static void CEF_CALLBACK app_add_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_app*>(base);
    self->refct.fetch_add(1);
}

static int CEF_CALLBACK app_release(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_app*>(base);
    int refct = self->refct.fetch_sub(1) - 1;
    if (refct <= 0) {
        self->refct.store(1);
    }
    return 0;
}

static int CEF_CALLBACK app_has_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_app*>(base);
    return self->refct.load() == 1;
}

static int CEF_CALLBACK app_has_at_least_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_app*>(base);
    return self->refct.load() >= 1;
}

static void stoa_append_command_line_switch(cef_command_line_t* command_line,
                                            const char* name,
                                            const char* value) {
    if (!command_line || !name) {
        return;
    }
    cef_string_t name_str = {};
    stoa_set_utf16(&name_str, name);
    if (value && value[0] != '\0') {
        cef_string_t value_str = {};
        stoa_set_utf16(&value_str, value);
        command_line->append_switch_with_value(command_line, &name_str, &value_str);
        cef_string_utf16_clear(&value_str);
    } else {
        command_line->append_switch(command_line, &name_str);
    }
    cef_string_utf16_clear(&name_str);
}

static void CEF_CALLBACK app_on_before_command_line_processing(cef_app_t* self,
                                                               const cef_string_t* process_type,
                                                               cef_command_line_t* command_line) {
    (void)self;
    (void)process_type;
    if (!command_line) {
        return;
    }
    const char* allow_keychain = getenv("STOA_CEF_ALLOW_KEYCHAIN");
    if (!allow_keychain || std::strcmp(allow_keychain, "1") != 0) {
        stoa_append_command_line_switch(command_line, "use-mock-keychain", nullptr);
        stoa_append_command_line_switch(command_line, "password-store", "basic");
    }
}

static stoa_cef_app* stoa_get_app() {
    static stoa_cef_app* app = nullptr;
    if (app) {
        return app;
    }
    app = new stoa_cef_app();
    std::memset(app, 0, sizeof(stoa_cef_app));
    app->refct.store(1);
    app->app.base.size = sizeof(cef_app_t);
    app->app.base.add_ref = app_add_ref;
    app->app.base.release = app_release;
    app->app.base.has_one_ref = app_has_one_ref;
    app->app.base.has_at_least_one_ref = app_has_at_least_one_ref;
    app->app.on_before_command_line_processing = app_on_before_command_line_processing;
    return app;
}

static void CEF_CALLBACK render_add_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_render_handler*>(base);
    self->refct.fetch_add(1);
}

static int CEF_CALLBACK render_release(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_render_handler*>(base);
    if (self->refct.fetch_sub(1) == 1) {
        delete self;
        return 1;
    }
    return 0;
}

static int CEF_CALLBACK render_has_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_render_handler*>(base);
    return self->refct.load() == 1;
}

static int CEF_CALLBACK render_has_at_least_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_render_handler*>(base);
    return self->refct.load() >= 1;
}

static void CEF_CALLBACK life_add_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_life_span_handler*>(base);
    self->refct.fetch_add(1);
}

static int CEF_CALLBACK life_release(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_life_span_handler*>(base);
    if (self->refct.fetch_sub(1) == 1) {
        delete self;
        return 1;
    }
    return 0;
}

static int CEF_CALLBACK life_has_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_life_span_handler*>(base);
    return self->refct.load() == 1;
}

static int CEF_CALLBACK life_has_at_least_one_ref(cef_base_ref_counted_t* base) {
    auto* self = reinterpret_cast<stoa_cef_life_span_handler*>(base);
    return self->refct.load() >= 1;
}

static cef_render_handler_t* CEF_CALLBACK client_get_render_handler(cef_client_t* self) {
    auto* client = reinterpret_cast<stoa_cef_client*>(self);
    if (!client->render_handler) {
        return nullptr;
    }
    client->render_handler->handler.base.add_ref(&client->render_handler->handler.base);
    return &client->render_handler->handler;
}

static cef_life_span_handler_t* CEF_CALLBACK client_get_life_span_handler(cef_client_t* self) {
    auto* client = reinterpret_cast<stoa_cef_client*>(self);
    if (!client->life_span_handler) {
        return nullptr;
    }
    client->life_span_handler->handler.base.add_ref(&client->life_span_handler->handler.base);
    return &client->life_span_handler->handler;
}

static void CEF_CALLBACK render_get_view_rect(cef_render_handler_t* self,
                                              cef_browser_t* browser,
                                              cef_rect_t* rect) {
    auto* handler = reinterpret_cast<stoa_cef_render_handler*>(self);
    if (!handler || !handler->owner || !rect) {
        return;
    }
    rect->x = 0;
    rect->y = 0;
    rect->width = handler->owner->width;
    rect->height = handler->owner->height;
    (void)browser;
}

static int CEF_CALLBACK render_get_screen_info(cef_render_handler_t* self,
                                               cef_browser_t* browser,
                                               cef_screen_info_t* screen_info) {
    auto* handler = reinterpret_cast<stoa_cef_render_handler*>(self);
    if (!handler || !handler->owner || !screen_info) {
        return 0;
    }
    screen_info->device_scale_factor = handler->owner->device_scale_factor;
    screen_info->rect.x = 0;
    screen_info->rect.y = 0;
    screen_info->rect.width = handler->owner->width;
    screen_info->rect.height = handler->owner->height;
    screen_info->available_rect = screen_info->rect;
    (void)browser;
    return 1;
}
static void CEF_CALLBACK render_on_paint(cef_render_handler_t* self,
                                         cef_browser_t* browser,
                                         cef_paint_element_type_t type,
                                         size_t dirtyRectsCount,
                                         const cef_rect_t* dirtyRects,
                                         const void* buffer,
                                         int width,
                                         int height) {
    auto* handler = reinterpret_cast<stoa_cef_render_handler*>(self);
    if (!handler || !handler->owner || !handler->owner->paint_cb) {
        return;
    }
    if (type != PET_VIEW) {
        return;
    }
    const int length = width * height * 4;
    handler->owner->paint_cb(handler->owner->user_data, width, height, buffer, length);
    (void)browser;
    (void)dirtyRectsCount;
    (void)dirtyRects;
}

static void CEF_CALLBACK life_on_after_created(cef_life_span_handler_t* self,
                                               cef_browser_t* browser) {
    auto* handler = reinterpret_cast<stoa_cef_life_span_handler*>(self);
    if (!handler || !handler->owner || !browser) {
        return;
    }
    if (!handler->owner->browser) {
        handler->owner->browser = browser;
        browser->base.add_ref(&browser->base);
    }
    cef_browser_host_t* host = browser->get_host(browser);
    if (host) {
        host->set_focus(host, 1);
        host->was_resized(host);
        host->invalidate(host, PET_VIEW);
        host->base.release(&host->base);
    }
    if (!handler->owner->pending_url.empty()) {
        cef_string_t url = {};
        stoa_set_utf16(&url, handler->owner->pending_url.c_str());
        browser->get_main_frame(browser)->load_url(browser->get_main_frame(browser), &url);
        cef_string_utf16_clear(&url);
        handler->owner->pending_url.clear();
    }
}

static stoa_cef_render_handler* stoa_create_render_handler(stoa_cef_browser* owner) {
    auto* handler = new stoa_cef_render_handler();
    std::memset(handler, 0, sizeof(stoa_cef_render_handler));
    handler->refct.store(1);
    handler->owner = owner;
    handler->handler.base.size = sizeof(cef_render_handler_t);
    handler->handler.base.add_ref = render_add_ref;
    handler->handler.base.release = render_release;
    handler->handler.base.has_one_ref = render_has_one_ref;
    handler->handler.base.has_at_least_one_ref = render_has_at_least_one_ref;
    handler->handler.get_view_rect = render_get_view_rect;
    handler->handler.get_screen_info = render_get_screen_info;
    handler->handler.on_paint = render_on_paint;
    return handler;
}

static stoa_cef_life_span_handler* stoa_create_life_span_handler(stoa_cef_browser* owner) {
    auto* handler = new stoa_cef_life_span_handler();
    std::memset(handler, 0, sizeof(stoa_cef_life_span_handler));
    handler->refct.store(1);
    handler->owner = owner;
    handler->handler.base.size = sizeof(cef_life_span_handler_t);
    handler->handler.base.add_ref = life_add_ref;
    handler->handler.base.release = life_release;
    handler->handler.base.has_one_ref = life_has_one_ref;
    handler->handler.base.has_at_least_one_ref = life_has_at_least_one_ref;
    handler->handler.on_after_created = life_on_after_created;
    return handler;
}

static stoa_cef_client* stoa_create_client(stoa_cef_browser* owner) {
    auto* client = new stoa_cef_client();
    std::memset(client, 0, sizeof(stoa_cef_client));
    client->refct.store(1);
    client->render_handler = stoa_create_render_handler(owner);
    client->life_span_handler = stoa_create_life_span_handler(owner);
    client->client.base.size = sizeof(cef_client_t);
    client->client.base.add_ref = client_add_ref;
    client->client.base.release = client_release;
    client->client.base.has_one_ref = client_has_one_ref;
    client->client.base.has_at_least_one_ref = client_has_at_least_one_ref;
    client->client.get_render_handler = client_get_render_handler;
    client->client.get_life_span_handler = client_get_life_span_handler;
    return client;
}

static std::atomic<bool> g_initialized{false};

bool stoa_cef_initialize(
    int argc,
    char** argv,
    const char* framework_path,
    const char* resources_path,
    const char* locales_path,
    const char* cache_path,
    int remote_debugging_port
) {
    if (g_initialized.load()) {
        return true;
    }

    stoa_ensure_cef_api_version();
    stoa_cef_app* app = stoa_get_app();

    cef_main_args_t main_args = {};
    main_args.argc = argc;
    main_args.argv = argv;

    cef_settings_t settings = {};
    settings.size = sizeof(settings);
    settings.no_sandbox = 1;
    settings.windowless_rendering_enabled = 1;
    settings.external_message_pump = 1;
    settings.remote_debugging_port = remote_debugging_port;

    if (framework_path) {
        stoa_set_utf16(&settings.framework_dir_path, framework_path);
    }
    if (argc > 0 && argv && argv[0]) {
        char resolved_path[PATH_MAX] = {0};
        if (realpath(argv[0], resolved_path)) {
            stoa_set_utf16(&settings.browser_subprocess_path, resolved_path);
        }
    }
    if (resources_path) {
        stoa_set_utf16(&settings.resources_dir_path, resources_path);
    }
    if (locales_path) {
        stoa_set_utf16(&settings.locales_dir_path, locales_path);
    }
    if (cache_path) {
        stoa_set_utf16(&settings.cache_path, cache_path);
    }

    const char* log_path = getenv("STOA_CEF_LOG_PATH");
    if (log_path) {
        stoa_set_utf16(&settings.log_file, log_path);
        settings.log_severity = LOGSEVERITY_INFO;
    }

    const int ok = cef_initialize(&main_args, &settings, &app->app, nullptr);
    if (!ok) {
        fprintf(stderr, "CEF initialize failed\\n");
    }
    g_initialized.store(ok != 0);
    return ok != 0;
}

int stoa_cef_execute_process(int argc, char** argv) {
    stoa_ensure_cef_api_version();
    stoa_cef_app* app = stoa_get_app();

    cef_main_args_t main_args = {};
    main_args.argc = argc;
    main_args.argv = argv;
    return cef_execute_process(&main_args, &app->app, nullptr);
}

void stoa_cef_shutdown(void) {
    if (!g_initialized.load()) {
        return;
    }
    cef_shutdown();
    g_initialized.store(false);
}

void stoa_cef_do_message_loop_work(void) {
    if (!g_initialized.load()) {
        return;
    }
    cef_do_message_loop_work();
}

stoa_cef_browser_t* stoa_cef_browser_create(
    const char* url,
    int width,
    int height,
    void* parent_view,
    float device_scale_factor,
    void* user_data,
    stoa_cef_paint_callback paint_cb
) {
    if (!g_initialized.load()) {
        return nullptr;
    }

    auto* browser = new stoa_cef_browser();
    browser->width = width > 0 ? width : 1;
    browser->height = height > 0 ? height : 1;
    browser->device_scale_factor = device_scale_factor > 0.0f ? device_scale_factor : 1.0f;
    browser->user_data = user_data;
    browser->paint_cb = paint_cb;
    browser->browser = nullptr;
    if (url) {
        browser->pending_url = url;
    }

    browser->client = stoa_create_client(browser);

    cef_window_info_t window_info = {};
    window_info.size = sizeof(window_info);
    window_info.windowless_rendering_enabled = 1;
    window_info.shared_texture_enabled = 0;
    window_info.external_begin_frame_enabled = 0;
    window_info.bounds.x = 0;
    window_info.bounds.y = 0;
    window_info.bounds.width = browser->width;
    window_info.bounds.height = browser->height;
    window_info.parent_view = parent_view;

    cef_browser_settings_t browser_settings = {};
    browser_settings.size = sizeof(browser_settings);
    browser_settings.windowless_frame_rate = 60;
    browser_settings.background_color = CefColorSetARGB(255, 255, 255, 255);

    cef_string_t url_str = {};
    if (url) {
        stoa_set_utf16(&url_str, url);
    }

    browser->browser = cef_browser_host_create_browser_sync(
        &window_info,
        &browser->client->client,
        url ? &url_str : nullptr,
        &browser_settings,
        nullptr,
        nullptr
    );
    if (!browser->browser) {
        fprintf(stderr, "CEF create_browser_sync returned null\n");
    }

    if (url) {
        cef_string_utf16_clear(&url_str);
    }

    return browser;
}

void stoa_cef_browser_destroy(stoa_cef_browser_t* browser) {
    if (!browser) {
        return;
    }

    if (browser->browser) {
        cef_browser_host_t* host = browser->browser->get_host(browser->browser);
        if (host) {
            host->close_browser(host, 1);
            host->base.release(&host->base);
        }
        browser->browser->base.release(&browser->browser->base);
        browser->browser = nullptr;
    }

    if (browser->client) {
        if (browser->client->render_handler) {
            browser->client->render_handler->handler.base.release(&browser->client->render_handler->handler.base);
            browser->client->render_handler = nullptr;
        }
        if (browser->client->life_span_handler) {
            browser->client->life_span_handler->handler.base.release(&browser->client->life_span_handler->handler.base);
            browser->client->life_span_handler = nullptr;
        }
        browser->client->client.base.release(&browser->client->client.base);
        browser->client = nullptr;
    }

    delete browser;
}

void stoa_cef_browser_set_device_scale(stoa_cef_browser_t* browser, float device_scale_factor) {
    if (!browser) {
        return;
    }
    if (device_scale_factor <= 0.0f) {
        device_scale_factor = 1.0f;
    }
    if (browser->device_scale_factor == device_scale_factor) {
        return;
    }
    browser->device_scale_factor = device_scale_factor;
    if (browser->browser) {
        cef_browser_host_t* host = browser->browser->get_host(browser->browser);
        if (host) {
            host->notify_screen_info_changed(host);
            host->invalidate(host, PET_VIEW);
            host->base.release(&host->base);
        }
    }
}

void stoa_cef_browser_set_focus(stoa_cef_browser_t* browser, bool focus) {
    if (!browser || !browser->browser) {
        return;
    }
    cef_browser_host_t* host = browser->browser->get_host(browser->browser);
    if (host) {
        host->set_focus(host, focus ? 1 : 0);
        host->base.release(&host->base);
    }
}

void stoa_cef_browser_resize(stoa_cef_browser_t* browser, int width, int height) {
    if (!browser) {
        return;
    }
    browser->width = width > 0 ? width : 1;
    browser->height = height > 0 ? height : 1;

    if (browser->browser) {
        cef_browser_host_t* host = browser->browser->get_host(browser->browser);
        if (host) {
            host->was_resized(host);
            host->invalidate(host, PET_VIEW);
            host->base.release(&host->base);
        }
    }
}

void stoa_cef_browser_load_url(stoa_cef_browser_t* browser, const char* url) {
    if (!browser || !url) {
        return;
    }
    if (!browser->browser) {
        browser->pending_url = url;
        return;
    }

    cef_string_t url_str = {};
    stoa_set_utf16(&url_str, url);
    cef_frame_t* frame = browser->browser->get_main_frame(browser->browser);
    if (frame) {
        frame->load_url(frame, &url_str);
        frame->base.release(&frame->base);
    }
    cef_string_utf16_clear(&url_str);
}

void stoa_cef_browser_send_key_event(
    stoa_cef_browser_t* browser,
    int type,
    int modifiers,
    uint32_t character,
    uint32_t unmodified_character,
    uint32_t native_key_code
) {
    if (!browser || !browser->browser) {
        return;
    }

    cef_browser_host_t* host = browser->browser->get_host(browser->browser);
    if (!host) {
        return;
    }

    cef_key_event_t event = {};
    event.size = sizeof(event);
    event.type = static_cast<cef_key_event_type_t>(type);
    event.modifiers = static_cast<uint32_t>(modifiers);
    event.character = static_cast<char16_t>(character);
    event.unmodified_character = static_cast<char16_t>(unmodified_character);
    event.native_key_code = static_cast<int>(native_key_code);
    if (type == KEYEVENT_CHAR && character != 0) {
        event.windows_key_code = static_cast<int>(character);
    } else if (unmodified_character != 0) {
        event.windows_key_code = static_cast<int>(unmodified_character);
    } else {
        event.windows_key_code = static_cast<int>(native_key_code);
    }
    event.is_system_key = 0;
    event.focus_on_editable_field = 0;

    host->send_key_event(host, &event);
    host->base.release(&host->base);
}

void stoa_cef_browser_send_mouse_move(
    stoa_cef_browser_t* browser,
    int x,
    int y,
    int modifiers,
    bool mouse_leave
) {
    if (!browser || !browser->browser) {
        return;
    }

    cef_browser_host_t* host = browser->browser->get_host(browser->browser);
    if (!host) {
        return;
    }

    cef_mouse_event_t event = {};
    event.x = x;
    event.y = y;
    event.modifiers = static_cast<uint32_t>(modifiers);

    host->send_mouse_move_event(host, &event, mouse_leave ? 1 : 0);
    host->base.release(&host->base);
}

void stoa_cef_browser_send_mouse_click(
    stoa_cef_browser_t* browser,
    int x,
    int y,
    int modifiers,
    int button,
    bool mouse_up,
    int click_count
) {
    if (!browser || !browser->browser) {
        return;
    }

    cef_browser_host_t* host = browser->browser->get_host(browser->browser);
    if (!host) {
        return;
    }

    cef_mouse_event_t event = {};
    event.x = x;
    event.y = y;
    event.modifiers = static_cast<uint32_t>(modifiers);

    host->set_focus(host, 1);
    host->send_mouse_click_event(
        host,
        &event,
        static_cast<cef_mouse_button_type_t>(button),
        mouse_up ? 1 : 0,
        click_count
    );
    host->base.release(&host->base);
}

void stoa_cef_browser_send_mouse_wheel(
    stoa_cef_browser_t* browser,
    int x,
    int y,
    int modifiers,
    int delta_x,
    int delta_y
) {
    if (!browser || !browser->browser) {
        return;
    }

    cef_browser_host_t* host = browser->browser->get_host(browser->browser);
    if (!host) {
        return;
    }

    cef_mouse_event_t event = {};
    event.x = x;
    event.y = y;
    event.modifiers = static_cast<uint32_t>(modifiers);

    host->send_mouse_wheel_event(host, &event, delta_x, delta_y);
    host->base.release(&host->base);
}
