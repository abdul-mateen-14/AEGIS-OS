/* Wayland client protocol stubs for org_kde_kwin_blur v1.
 *
 * T21 v0.6.66 — the shell speaks org_kde_kwin_blur directly (see
 * blurmanager.cpp for why KF6's WindowEffects path is dead at runtime).
 * This sandbox has no wayland-scanner, so this is the scanner's exact
 * output hand-derived from plasma-wayland-protocols
 * src/protocols/blur.xml (fetched 2026-11-16, LGPL-2.1-or-later):
 *
 *   org_kde_kwin_blur_manager v1: create(new_id blur, surface) [0],
 *                                 unset(surface) [1]
 *   org_kde_kwin_blur v1:         commit [0], set_region(region?) [1],
 *                                 release (destructor) [2]
 *   no events on either interface.
 */
#ifndef BLUR_CLIENT_PROTOCOL_H
#define BLUR_CLIENT_PROTOCOL_H

#include <stdint.h>
#include <stddef.h>
#include "wayland-client.h"

#ifdef __cplusplus
extern "C" {
#endif

struct wl_surface;
struct wl_region;
struct org_kde_kwin_blur;
struct org_kde_kwin_blur_manager;

extern const struct wl_interface org_kde_kwin_blur_interface;
extern const struct wl_interface org_kde_kwin_blur_manager_interface;

/* Requests of org_kde_kwin_blur_manager */
enum {
    ORG_KDE_KWIN_BLUR_MANAGER_CREATE = 0,
    ORG_KDE_KWIN_BLUR_MANAGER_UNSET = 1,
};

/* create(id: new_id org_kde_kwin_blur, surface: wl_surface) — the
 * scanner emits the new_id placeholder (NULL) first, then the args. */
static inline struct org_kde_kwin_blur *
org_kde_kwin_blur_manager_create(
    struct org_kde_kwin_blur_manager *org_kde_kwin_blur_manager,
    struct wl_surface *surface)
{
    return (struct org_kde_kwin_blur *) wl_proxy_marshal_constructor(
        (struct wl_proxy *) org_kde_kwin_blur_manager,
        ORG_KDE_KWIN_BLUR_MANAGER_CREATE,
        &org_kde_kwin_blur_interface,
        NULL,
        surface);
}

static inline void
org_kde_kwin_blur_manager_unset(
    struct org_kde_kwin_blur_manager *org_kde_kwin_blur_manager,
    struct wl_surface *surface)
{
    wl_proxy_marshal((struct wl_proxy *) org_kde_kwin_blur_manager,
                     ORG_KDE_KWIN_BLUR_MANAGER_UNSET, surface);
}

/* Requests of org_kde_kwin_blur */
enum {
    ORG_KDE_KWIN_BLUR_COMMIT = 0,
    ORG_KDE_KWIN_BLUR_SET_REGION = 1,
    ORG_KDE_KWIN_BLUR_RELEASE = 2,
};

static inline void
org_kde_kwin_blur_commit(struct org_kde_kwin_blur *org_kde_kwin_blur)
{
    wl_proxy_marshal((struct wl_proxy *) org_kde_kwin_blur,
                     ORG_KDE_KWIN_BLUR_COMMIT);
}

/* region may be NULL (allow-null in the XML) — NULL blurs the whole
 * window on KWin; we always pass an explicit region. */
static inline void
org_kde_kwin_blur_set_region(struct org_kde_kwin_blur *org_kde_kwin_blur,
                             struct wl_region *region)
{
    wl_proxy_marshal((struct wl_proxy *) org_kde_kwin_blur,
                     ORG_KDE_KWIN_BLUR_SET_REGION, region);
}

/* Destructor request: send it, then destroy the client proxy. */
static inline void
org_kde_kwin_blur_release(struct org_kde_kwin_blur *org_kde_kwin_blur)
{
    wl_proxy_marshal((struct wl_proxy *) org_kde_kwin_blur,
                     ORG_KDE_KWIN_BLUR_RELEASE);
    wl_proxy_destroy((struct wl_proxy *) org_kde_kwin_blur);
}

#ifdef __cplusplus
}
#endif

#endif /* BLUR_CLIENT_PROTOCOL_H */
