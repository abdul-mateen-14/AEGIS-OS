/* Private-code counterpart of blur-client-protocol.h — the wl_interface
 * definitions libwayland needs for wl_registry_bind and
 * wl_proxy_marshal_constructor. Derived from plasma-wayland-protocols
 * src/protocols/blur.xml (LGPL-2.1-or-later); see the header. */
#include <stdint.h>
#include <stddef.h>
#include "wayland-client.h"
#include "blur-client-protocol.h"

/* Compiled as C — no extern "C" (the header guards handle linkage). */

/* Arg-type pool: [0]=NULL, [1]=org_kde_kwin_blur, [2]=wl_surface,
 * [3]=wl_region. Only referenced by the request tables below. */
static const struct wl_interface *blur_types[] = {
    NULL,
    &org_kde_kwin_blur_interface,
    &wl_surface_interface,
    &wl_region_interface,
};

static const struct wl_message org_kde_kwin_blur_manager_requests[] = {
    /* create: [id: new_id org_kde_kwin_blur, surface: wl_surface] */
    { "create", "no", blur_types + 1 },
    /* unset: [surface: wl_surface] */
    { "unset", "o", blur_types + 2 },
};

static const struct wl_message org_kde_kwin_blur_requests[] = {
    { "commit", "", blur_types + 0 },
    /* set_region: [region: wl_region (nullable)] */
    { "set_region", "o", blur_types + 3 },
    { "release", "", blur_types + 0 },
};

const struct wl_interface org_kde_kwin_blur_manager_interface = {
    "org_kde_kwin_blur_manager", 1,
    2, org_kde_kwin_blur_manager_requests,
    0, NULL,
};

const struct wl_interface org_kde_kwin_blur_interface = {
    "org_kde_kwin_blur", 1,
    3, org_kde_kwin_blur_requests,
    0, NULL,
};
