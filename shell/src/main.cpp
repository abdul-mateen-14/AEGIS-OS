// Aegis Shell — the liquid-glass shell of Aegis OS.
//
// One process hosts four layer-shell surfaces on KWin 6 Wayland:
//   desktopWindow  Layer::Background — wallpaper canvas (full bleed)
//   panelWindow    Layer::Top        — 28 px glass top panel (exclusive zone)
//   islandWindow   Layer::Top        — Dynamic Island capsule below the panel
//   dockWindow     Layer::Top        — floating liquid-glass dock + sliver
//
// main.cpp attaches each QML Window to the layer-shell protocol BEFORE the
// platform window is created (QML windows ship visible: false for exactly
// this reason), then shows them.

#include <QGuiApplication>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QMargins>

#include <LayerShellQt/Window>

#include "util.h"

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
    } else {
        return;
    }

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

    qmlRegisterSingletonType<Util>("Aegis.Util", 1, 0, "Util",
        [](QQmlEngine *engine, QJSEngine *) -> QObject * {
            auto *util = new Util;
            engine->setObjectOwnership(util, QQmlEngine::CppOwnership);
            return util;
        });

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
        for (QQuickWindow *win : windows)
            configureSurface(win);
    }

    return app.exec();
}
