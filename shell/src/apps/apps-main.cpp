// aegis-apps — host process for the first-party Qt Quick app suite.
//
// argv[1] selects the app: "files" (FilesApp.qml) or "settings"
// (SettingsApp.qml). /usr/bin/aegis-files and /usr/bin/aegis-settings are
// thin wrappers that exec this binary with the right argument, so the dock
// config (util.cpp) and desktop entries can point at real binaries.
//
// Unlike aegis-shell, these are REGULAR Wayland windows (no layer shell):
// Table 18 anatomy, CSD frameless, moved/resized through the system
// interfaces (startSystemMove / startSystemResize) so KWin keeps tiling,
// snapping and the rounded-corner effect.
//
// The singletons register under the SAME module names as aegis-shell
// ("Aegis.Util", "Aegis.Governor") — the app QML consumes the shell's
// tokens and services unchanged ("the shell's tokens are the apps' tokens",
// proposal §8). Governor::start() is deliberately NOT called here: the
// shell owns the org.aegis DBus names; the apps only read state.

#include <QGuiApplication>
#include <QIcon>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QUrl>

#include "../util.h"
#include "../governor/Governor.h"
#include "filemanager.h"

namespace {

// Same provider contract as aegis-shell: Image { source: "image://icons/<name>" }
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

} // namespace

int main(int argc, char *argv[])
{
    qputenv("QT_QPA_PLATFORMTHEME", "kde");
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("aegis"));
    QGuiApplication::setApplicationName(QStringLiteral("aegis-apps"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QIcon::setThemeName(QStringLiteral("Aegis"));

    const QString which = argc > 1 ? QString::fromLocal8Bit(argv[1])
                                   : QStringLiteral("files");
    const QString qmlName = (which == QStringLiteral("settings"))
                                ? QStringLiteral("SettingsApp.qml")
                                : QStringLiteral("FilesApp.qml");

    Util util;
    Governor governor(&util, nullptr);
    FileManager files;

    QQmlEngine engine;
    engine.addImageProvider(QStringLiteral("icons"), new IconProvider());
    qmlRegisterSingletonInstance("Aegis.Util", 1, 0, "Util", &util);
    qmlRegisterSingletonInstance("Aegis.Governor", 1, 0, "Governor", &governor);
    qmlRegisterSingletonInstance("Aegis.Files", 1, 0, "Files", &files);

    // Installed QML tree first (same contract as aegis-shell main.cpp),
    // embedded resource as fallback.
    const QUrl candidates[] = {
        QUrl::fromLocalFile(QStringLiteral("/usr/share/aegis/shell/qml/") + qmlName),
        QUrl(QStringLiteral("qrc:/qml/") + qmlName),
    };
    bool loaded = false;
    for (const QUrl &src : candidates) {
        QQmlComponent component(&engine, src);
        QObject *obj = component.create();
        if (obj) {
            loaded = true;
            break;
        }
        // "Component is not ready" alone is undiagnosable in a boot test —
        // always log which URL failed and the full QML error list.
        qCritical("aegis-apps: %s not ready: %s",
                  src.toString().toUtf8().constData(),
                  component.errorString().toUtf8().constData());
    }
    if (!loaded) {
        qCritical("aegis-apps: failed to load %s", qmlName.toUtf8().constData());
        return 1;
    }

    return app.exec();
}
