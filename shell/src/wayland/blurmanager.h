/*
 * BlurManager — the shell's own org_kde_kwin_blur client channel.
 *
 * T21 v0.6.66. Diagnosis (TASKS.md "T21 DIAGNOSED"): KF6's
 * KWindowEffects::enableBlurBehind on Wayland renders only for calls
 * made at shell startup; every RUNTIME call is silently eaten — the
 * QPA/KF6 WindowEffects instance is re-created around the ~30 s screen
 * change and the fresh instance's lazily-initialized blur managers are
 * not yet active, so both of KF6's early-return gates fire
 * (`isActive()` for create, the empty-map `remove()` for unset). The
 * blurlog proved the shell-side lambda runs perfectly while the frames
 * stay byte-identical.
 *
 * Fix: bind the global ourselves at shell startup and drive the
 * protocol directly for the whole process lifetime — the exact request
 * sequence diag 5's WAYLAND_DEBUG trace proved rendering:
 *   manager.create(surface) → blur.set_region(wl_region) → blur.commit
 * and to clear: manager.unset(surface).
 *
 * X11 keeps the KF6 call (the kwin-x11 blur-behind property is a real
 * path there); applyShellBlur in main.cpp picks the channel.
 */
#pragma once

#include <QHash>
#include <QRegion>
#include <QWindow>

struct wl_display;
struct wl_compositor;
struct org_kde_kwin_blur;
struct org_kde_kwin_blur_manager;
struct wl_registry;
struct wl_surface;

class BlurManager
{
public:
    static BlurManager &instance();

    // Binds wl_compositor + org_kde_kwin_blur_manager from the QPA
    // wayland connection (one roundtrip). No-ops off-wayland or when
    // the compositor does not advertise the blur global.
    void init();

    bool ready() const { return m_manager && m_compositor; }

    // Direct blur apply for one window. enable=false sends unset
    // (and releases this window's blur object); enable=true sends
    // create+set_region+commit. region empty → the full window rect.
    void apply(QWindow *win, bool enable, const QRegion &region);

private:
    BlurManager() = default;
    void bindGlobal(struct wl_registry *reg, uint32_t name,
                    const char *iface, uint32_t version);

    struct wl_display *m_display = nullptr;
    struct wl_compositor *m_compositor = nullptr;
    struct org_kde_kwin_blur_manager *m_manager = nullptr;
    QHash<QWindow *, struct org_kde_kwin_blur *> m_blurs;
};
