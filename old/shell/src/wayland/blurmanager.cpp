#include "blurmanager.h"

#include <QByteArray>
#include <QGuiApplication>
#include <QRect>
#include <QtGui/qpa/qplatformnativeinterface.h>
#include <wayland-client.h>

#include "blur-client-protocol.h"

BlurManager &BlurManager::instance()
{
    static BlurManager self;
    return self;
}

void BlurManager::init()
{
    if (QGuiApplication::platformName() != QLatin1String("wayland"))
        return;
    QPlatformNativeInterface *native =
        QGuiApplication::platformNativeInterface();
    if (!native) {
        qWarning("aegis-blur: no platform native interface");
        return;
    }
    m_display = static_cast<struct wl_display *>(
        native->nativeResourceForIntegration(
            QByteArrayLiteral("display")));
    if (!m_display) {
        qWarning("aegis-blur: no wayland display from the QPA");
        return;
    }
    wl_registry *reg = wl_display_get_registry(m_display);
    if (!reg)
        return;
    // Stateless lambdas convert to the C callbacks; data carries this.
    static const wl_registry_listener listener = {
        [](void *data, wl_registry *reg, uint32_t name,
           const char *iface, uint32_t version) {
            static_cast<BlurManager *>(data)->bindGlobal(
                reg, name, iface, version);
        },
        [](void *, wl_registry *, uint32_t) {},
    };
    wl_registry_add_listener(reg, &listener, this);
    wl_display_roundtrip(m_display); // the globals arrive synchronously
    wl_registry_destroy(reg);
    if (!ready())
        qWarning("aegis-blur: compositor has no org_kde_kwin_blur "
                 "global — blur stays off (wayland)");
    else
        qInfo("aegis-blur: direct org_kde_kwin_blur channel bound "
              "(v1)");
}

void BlurManager::bindGlobal(wl_registry *reg, uint32_t name,
                             const char *iface, uint32_t version)
{
    if (qstrcmp(iface, "org_kde_kwin_blur_manager") == 0
        && !m_manager) {
        m_manager = static_cast<struct org_kde_kwin_blur_manager *>(
            wl_registry_bind(reg, name,
                             &org_kde_kwin_blur_manager_interface, 1));
    } else if (qstrcmp(iface, "wl_compositor") == 0
               && !m_compositor) {
        m_compositor = static_cast<struct wl_compositor *>(
            wl_registry_bind(reg, name, &wl_compositor_interface,
                             qMin(version, 5u)));
    }
}

void BlurManager::apply(QWindow *win, bool enable, const QRegion &region)
{
    if (!ready() || !win)
        return;
    QPlatformNativeInterface *native =
        QGuiApplication::platformNativeInterface();
    auto *surface = static_cast<struct wl_surface *>(
        native->nativeResourceForWindow(
            QByteArrayLiteral("surface"), win));
    if (!surface) {
        qWarning("aegis-blur: no wl_surface for window %p", (void *)win);
        return;
    }
    // One blur object per window: release the old proxy before
    // replacing (its destruction also detaches the surface server-side).
    if (auto *old = m_blurs.take(win))
        org_kde_kwin_blur_release(old);
    if (!enable) {
        org_kde_kwin_blur_manager_unset(m_manager, surface);
        return;
    }
    const QRegion r = region.isEmpty()
        ? QRegion(QRect(0, 0, win->width(), win->height()))
        : region;
    wl_region *wlreg = wl_compositor_create_region(m_compositor);
    for (const QRect &rect : r)
        wl_region_add(wlreg, rect.x(), rect.y(), rect.width(),
                      rect.height());
    auto *blur = org_kde_kwin_blur_manager_create(m_manager, surface);
    if (blur) {
        org_kde_kwin_blur_set_region(blur, wlreg);
        org_kde_kwin_blur_commit(blur);
        m_blurs.insert(win, blur);
    } else {
        qWarning("aegis-blur: manager.create returned NULL");
    }
    wl_region_destroy(wlreg); // the server copied the rects
}
