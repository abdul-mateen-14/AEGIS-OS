// Aegis Shell — the liquid-glass shell of Aegis OS.
//
// One process hosts eight layer-shell surfaces on KWin 6 Wayland:
//   desktopWindow       Layer::Background — wallpaper canvas (full bleed)
//   panelWindow         Layer::Top        — 28 px glass top panel (exclusive zone)
//   islandWindow        Layer::Top        — Dynamic Island capsule below the panel
//   dockWindow          Layer::Top        — floating liquid-glass dock + sliver
//   ccWindow            Layer::Top        — Control Center sheet (top-right)
//   launcherWindow      Layer::Overlay    — full-screen glass sheet
//   notificationsWindow Layer::Top        — banner stack (top-right)
//   lockWindow          Layer::Overlay    — lock screen (full bleed)
//
// main.cpp attaches each QML Window to the layer-shell protocol BEFORE the
// platform window is created (QML windows ship visible: false for exactly
// this reason), then shows the persistent four. The M2 overlays create
// their surface on first show — QML drives their visibility off Util
// state, which is also what the org.aegis.Shell DBus interface toggles.
//
// M2 also wires three singletons: Util (config, hardware, launch), the
// adaptive effects Governor (Listing 2) and the ActivityService (Live
// Activity API + org.freedesktop.Notifications).

#include <QGuiApplication>
#include <QDBusConnection>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlEngine>
#include <QMargins>

#include <LayerShellQt/Window>

#include "util.h"
#include "governor/Governor.h"
#include "activity/ActivityService.h"

namespace {

// Freedesktop icon theme provider: Image { source: "image://icons/<name>" }
class IconProvider : public QQuickImageProvider {
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override
    {
        const QSize px = requestedSize.isEmpty() ? QSize(96, 96) : requestedSize;
        QIcon icon = QIcon::fromTheme(id,
            QIcon::fromTheme(QStringLiteral("application-x-executable")));
        QImage image = icon.pixmap(px).toImage();
        if (size) *size = image.size();
        return image;
    }
};

LayerShellQt::Window *attach(QQuickWindow *win)
{
    // layer-shell-qt 6.6 renamed attach() to get(): the Window is an attached
    // object of the QWindow, owned by it ("ownership is not transferred").
    return LayerShellQt::Window::get(win);
}

// Persistent surfaces are shown once at startup; overlay surfaces are
// driven by QML visibility (Util.ccOpen / launcherOpen / locked /
// Activity.bannersVisible) and surface-ify on first show.
bool isPersistent(const QString &name)
{
    return name == QStringLiteral("desktopWindow")
           || name == QStringLiteral("panelWindow")
           || name == QStringLiteral("islandWindow")
           || name == QStringLiteral("dockWindow");
}

void configureSurface(QQuickWindow *win)
{
    const QString name = win->objectName();

    if (name == QStringLiteral("desktopWindow")) {
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerBackground);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorBottom,
            LayerShellQt::Window::AnchorLeft,
            LayerShellQt::Window::AnchorRight});
        layer->setExclusiveZone(-1); // ignore every exclusive zone
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        layer->setScope(QStringLiteral("aegis-desktop"));
    } else if (name == QStringLiteral("panelWindow")) {
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorLeft,
            LayerShellQt::Window::AnchorRight});
        layer->setExclusiveZone(28); // Table 3 — 28 px of global panel
        layer->setDesiredSize(QSize(0, 28));
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-panel"));
    } else if (name == QStringLiteral("islandWindow")) {
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::AnchorTop);
        layer->setMargins(QMargins(0, 30, 0, 0)); // hangs flush below the panel
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-island"));
    } else if (name == QStringLiteral("dockWindow")) {
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::AnchorBottom);
        layer->setMargins(QMargins(0, 0, 0, 10)); // Table 4: 10 px above bottom edge
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-dock"));
    } else if (name == QStringLiteral("ccWindow")) {
        // Control Center — 348 px sheet, top-right, 12 px below the panel
        // (Table 17: margins 28 panel + 12 = 40 top, 10 right).
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorRight});
        layer->setMargins(QMargins(0, 40, 10, 0));
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-cc"));
    } else if (name == QStringLiteral("launcherWindow")) {
        // Launcher — full-screen sheet glass over the blurred desktop.
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerOverlay);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorBottom,
            LayerShellQt::Window::AnchorLeft,
            LayerShellQt::Window::AnchorRight});
        layer->setExclusiveZone(-1);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
        layer->setScope(QStringLiteral("aegis-launcher"));
    } else if (name == QStringLiteral("notificationsWindow")) {
        // Banners — 356 px stack, top-right below the panel (Table 17).
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorRight});
        layer->setMargins(QMargins(0, 40, 10, 0));
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        layer->setScope(QStringLiteral("aegis-notifications"));
    } else if (name == QStringLiteral("lockWindow")) {
        // Lock screen — full-bleed Overlay surface; chrome dies behind it.
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerOverlay);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorBottom,
            LayerShellQt::Window::AnchorLeft,
            LayerShellQt::Window::AnchorRight});
        layer->setExclusiveZone(-1);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
        layer->setScope(QStringLiteral("aegis-lock"));
    } else {
        return;
    }

    if (isPersistent(name))
        win->show();
}

} // namespace

int main(int argc, char *argv[])
{
    qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
    if (!qEnvironmentVariableIsSet("QT_QUICK_CONTROLS_STYLE"))
        qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("aegis-shell"));
    // app_id for the whole process — KWin window rules (kwinrulesrc) match it
    QGuiApplication::setDesktopFileName(QStringLiteral("aegis-shell"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // Singletons — Util first (Governor reads battery through it).
    static Util util;
    static ActivityService activity;
    static Governor governor(&util);

    qmlRegisterSingletonInstance("Aegis.Util", 1, 0, "Util", &util);
    qmlRegisterSingletonInstance("Aegis.Activity", 1, 0, "Activity", &activity);
    qmlRegisterSingletonInstance("Aegis.Governor", 1, 0, "Governor", &governor);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icons"), new IconProvider);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    if (engine.rootObjects().isEmpty()) {
        qCritical("aegis-shell: failed to load Main.qml");
        return 1;
    }

    const auto roots = engine.rootObjects();
    for (QObject *root : roots) {
        const auto windows = root->findChildren<QQuickWindow *>();
        for (QQuickWindow *win : windows) {
            configureSurface(win);
            governor.watchWindow(win); // frame-time feed (Listing 2)
        }
    }

    // ── DBus: the session API ────────────────────────────────────────
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        // org.aegis.Shell — lock / toggleLauncher / toggleControlCenter
        // (aegis-lock CLI and keyboard wiring land here)
        bus.registerService(QStringLiteral("org.aegis.Shell"));
        bus.registerObject(QStringLiteral("/org/aegis/Shell"), &util,
                           QDBusConnection::ExportInvokables);

        // Live Activity API + the standard notifications daemon name
        activity.start();
        governor.start();
    }

    // AC transition → island charging pulse
    QObject::connect(&util, &Util::chargingEvent, &activity,
                     [&activity](bool charging, int percent, int minutes) {
                         if (charging)
                             activity.publishCharging(percent, minutes);
                         else
                             activity.endActivity(QStringLiteral("charging"));
                     });

    // Governor battery demotion → Calm Mode toast
    QObject::connect(&governor, &Governor::toast, &activity,
                     [&activity](const QString &title, const QString &body) {
                         activity.showBanner(QStringLiteral("Aegis OS"),
                                             QStringLiteral("preferences-system"),
                                             title, body);
                     });

    return app.exec();
}
