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
#include <QIcon>
#include <QDBusConnection>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlEngine>
#include <QMargins>
#include <QUrlQuery>
#include <QColor>

#include <KWindowEffects>

#include <LayerShellQt/Window>

#include "util.h"
#include "governor/Governor.h"
#include "activity/ActivityService.h"
// W36.1 — Desktop.qml resolves Aegis.Files for the New Folder action
#include "apps/filemanager.h"

namespace {

// Freedesktop icon theme provider: Image { source: "image://icons/<name>" }
class IconProvider : public QQuickImageProvider {
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override
    {
        const QSize px = requestedSize.isEmpty() ? QSize(96, 96) : requestedSize;
        // W16 — same tint query as the apps host: "?tint=%23RRGGBB"
        // template-recolors the glyph (keep alpha, swap RGB).
        QString name = id;
        QColor tint;
        const int q = id.indexOf(QLatin1Char('?'));
        if (q >= 0) {
            name = id.left(q);
            const QUrlQuery query(id.mid(q + 1));
            const QString t = query.queryItemValue(QStringLiteral("tint"));
            if (!t.isEmpty()) tint = QColor(t);
        }
        QIcon icon = name.startsWith(QLatin1Char('/'))
            ? QIcon(name)   // W22 — web shortcuts store absolute icon paths
            : QIcon::fromTheme(name,
                  QIcon::fromTheme(QStringLiteral("application-x-executable")));
        QImage image = icon.pixmap(px).toImage();
        if (tint.isValid() && !image.isNull()) {
            image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
            for (int y = 0; y < image.height(); ++y) {
                QRgb *row = reinterpret_cast<QRgb *>(image.scanLine(y));
                for (int x = 0; x < image.width(); ++x) {
                    const int a = qAlpha(row[x]);
                    if (a == 0) continue;
                    row[x] = qPremultiply(qRgba(tint.red(), tint.green(),
                                                tint.blue(), a));
                }
            }
        }
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

// W52 — macOS dock semantics: normal and maximized windows stop ABOVE
// the dock; only fullscreen covers it. The reserve is the tray's resting
// height (Tokens.iconSize 48 + trayPadding 6·2 + dotGap 4 = 64) + the
// dock window's 10 px bottom margin + a 2 px cushion so a maximized
// window edge sits 2 px clear of the tray hairline (the W52 probe
// asserts window bottom ≤ dockTop − 2). The sliver/hidden states lower
// the zone live from QML through SurfaceCtl (Dock.qml).
constexpr int DOCK_TRAY_H = 64;        // iconSize + trayPadding*2 + dotGap
constexpr int DOCK_BOTTOM_MARGIN = 10; // dockWindow QMargins bottom
constexpr int DOCK_CUSHION = 2;
constexpr int DOCK_RESERVE = DOCK_TRAY_H + DOCK_BOTTOM_MARGIN + DOCK_CUSHION;

// W52 — QML drives the dock's exclusive zone with the tray state
// (expanded DOCK_RESERVE / sliver sliverHeight+12 / hidden 0); layer-shell
// applies a zone change live and KWin re-lays-out the maximized area.
class SurfaceCtl : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE void setDockExclusiveZone(int px)
    {
        if (s_dockLayer)
            s_dockLayer->setExclusiveZone(px);
    }
    static LayerShellQt::Window *s_dockLayer;
};
LayerShellQt::Window *SurfaceCtl::s_dockLayer = nullptr;

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
#ifdef AEGIS_HAS_DESIRED_SIZE
        layer->setDesiredSize(QSize(0, 28)); // older layer-shell-qt builds omit this API
#endif
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-panel"));
    } else if (name == QStringLiteral("islandWindow")) {
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::AnchorTop);
        // §2.4 — the capsule HANGS from the panel. This surface respects the
        // panel's 28 px exclusive zone, so its y already starts below the panel;
        // the margin here is only the 2 px hairline gap. Margin 30 double-counted
        // the panel (y = 28 + 30 = 58) and left the island floating in mid-air.
        layer->setMargins(QMargins(0, 2, 0, 0));
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-island"));
    } else if (name == QStringLiteral("dockWindow")) {
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::AnchorBottom);
        layer->setMargins(QMargins(0, 0, 0, DOCK_BOTTOM_MARGIN)); // Table 4: 10 px above bottom edge
        // W52 — the resting dock owns its strip: maximized windows stop
        // 2 px above the tray (the W52 probe asserts it). The sliver and
        // hidden states lower the zone live via SurfaceCtl (Dock.qml).
        layer->setExclusiveZone(DOCK_RESERVE);
        SurfaceCtl::s_dockLayer = layer;
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
    } else if (name == QStringLiteral("calendarWindow")) {
        // T15-D10 (W47) — the glass calendar popover: click the panel
        // clock. Same architecture as the CC sheet (top-right, below the
        // panel's exclusive zone) but narrower and shifted left so it
        // hangs under the clock, not under the CC glyph.
        auto *layer = attach(win);
        layer->setLayer(LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::Anchors{
            LayerShellQt::Window::AnchorTop,
            LayerShellQt::Window::AnchorRight});
        layer->setMargins(QMargins(0, 40, 84, 0));
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScope(QStringLiteral("aegis-calendar"));
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

    // W50 — the blur candidates are the shell's live glass surfaces.
    // desktop, notifications and lock are NOT blurred (full-bleed /
    // fullscreen canvases). The actual KWindowEffects request is applied
    // in main() and re-applied on every Governor tier change (W57) —
    // blur follows window alpha, so the GlassPanel tint stays as-is.
    if (name == QStringLiteral("panelWindow")
        || name == QStringLiteral("dockWindow")
        || name == QStringLiteral("islandWindow"))
        win->setProperty("aegisGlassRung", QStringLiteral("panel"));
    else if (name == QStringLiteral("ccWindow")
             || name == QStringLiteral("calendarWindow")
             || name == QStringLiteral("launcherWindow"))
        win->setProperty("aegisGlassRung", QStringLiteral("sheet"));

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
    // app_id for the whole process — the aegis-windowwatch tracker and
    // the dock TileMap both key windows by resourceClass
    QGuiApplication::setDesktopFileName(QStringLiteral("aegis-shell"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // Dock/panel icon lookups must be deterministic: the live image ships
    // the Aegis squircle theme (proposal plate 09) + Breeze + hicolor, and
    // QPA on a bare Wayland session picks none by default, leaving every
    // image://icons/<name> provider request empty.
    QIcon::setThemeName(QStringLiteral("Aegis"));
    QIcon::setFallbackThemeName(QStringLiteral("hicolor"));

    // Singletons — Util first (Governor reads battery through it).
    static Util util;
    static ActivityService activity;
    static Governor governor(&util);
    // v0.6.48 run — Desktop.qml imports Aegis.Files and the shell's engine
    // only registered Util/Activity/Governor: the import failed, the
    // Desktop component died, and the session aborted at startup
    // (sddm-helper exit 134 — the boot gate red, correctly).
    static FileManager files;
    // this process owns org.aegis.Shell on the bus: its accent/wallpaper
    // writes apply locally and must NOT be re-forwarded over DBus
    util.setOwnsDBus(true);

    qmlRegisterSingletonInstance("Aegis.Util", 1, 0, "Util", &util);
    qmlRegisterSingletonInstance("Aegis.Activity", 1, 0, "Activity", &activity);
    qmlRegisterSingletonInstance("Aegis.Governor", 1, 0, "Governor", &governor);
    qmlRegisterSingletonInstance("Aegis.Files", 1, 0, "Files", &files);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icons"), new IconProvider);

    // W52 — QML → C++ surface control (the dock exclusive zone follows
    // the tray state; see SurfaceCtl / Dock.qml publishReserve()).
    static SurfaceCtl surfaces;
    engine.rootContext()->setContextProperty(QStringLiteral("AegisSurfaces"),
                                             &surfaces);

    // Main.qml comes from the installed QML tree first, the embedded
    // resource second. The resource was historically unreliable across
    // toolchains (Qt 6.10 + LTO builds registered the qrc tree but the
    // engine could not resolve qrc:/qml/Main.qml), so the filesystem is
    // the primary source and the qrc is the fallback.
    const QUrl qmlCandidates[] = {
        QUrl::fromLocalFile(QStringLiteral("/usr/share/aegis/shell/qml/Main.qml")),
        QUrl(QStringLiteral("qrc:/qml/Main.qml")),
    };
    for (const QUrl &src : qmlCandidates) {
        engine.load(src);
        if (!engine.rootObjects().isEmpty()) {
            break;
        }
    }

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

    // W50/W57 — the real blur channel: KWindowEffects::enableBlurBehind
    // issues org_kde_kwin_blur on the surface (the KDE-supported client
    // path on Wayland under KWin; stock KWin 6 has NO window-rule
    // force-blur — the old kwinrulesrc story in the comments was
    // fiction, TASKS T16-W50). blur follows window alpha, so the
    // GlassPanel tint stays; the compositor does the rest. blurLive
    // (Governor) gates the shell surfaces; re-applied on every tier /
    // override change so the Settings Desktop-Effects rows have a REAL
    // consumer.
    const auto applyShellBlur = [&governor, &roots]() {
        const bool live = governor.effects()
                              .value(QStringLiteral("blurLive"))
                              .toBool();
        for (QObject *root : roots)
            for (QQuickWindow *win :
                 root->findChildren<QQuickWindow *>()) {
                if (win->property("aegisGlassRung").toString().isEmpty())
                    continue;
                KWindowEffects::enableBlurBehind(win, live);
            }
    };
    applyShellBlur();
    QObject::connect(&governor, &Governor::tierChanged, &governor,
                     applyShellBlur);

    // ── DBus: the session API ────────────────────────────────────────
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        // org.aegis.Shell — lock / toggleLauncher / toggleControlCenter
        // (aegis-lock CLI and keyboard wiring land here)
        bus.registerService(QStringLiteral("org.aegis.Shell"));
        bus.registerObject(QStringLiteral("/org/aegis/Shell"), &util,
                           QDBusConnection::ExportAllInvokables);

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

// W52 — SurfaceCtl carries Q_OBJECT inside this translation unit; AUTOMOC
// requires the generated moc to be pulled in here (the Shell CI red on
// the v0.6.60 first build: "contains a Q_OBJECT macro, but does not
// include main.moc").
#include "main.moc"
