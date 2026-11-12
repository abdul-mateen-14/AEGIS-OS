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
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QColor>

#include "../util.h"
#include "../governor/Governor.h"
#include "filemanager.h"
#include "systembackends.h"
#include "aegisid.h"
#include "monitorbackend.h"

namespace {

// Same provider contract as aegis-shell: Image { source: "image://icons/<name>" }
class IconProvider : public QQuickImageProvider {
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override
    {
        const QSize px = requestedSize.isEmpty() ? QSize(96, 96) : requestedSize;
        // W16 — "image://icons/<name>?tint=%23RRGGBB": the tint query makes
        // the provider recolor the glyph at request time (template recolor:
        // keep alpha, swap RGB) so document kinds render in their §8.1
        // kind tint. Pre-colored glyphs (folder, image, audio, video) are
        // requested without the query and stay untouched.
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
    // M3 — the four new first-party apps ride the same host: one binary,
    // thin wrapper scripts (aegis-music / aegis-calculator / aegis-editor /
    // aegis-monitor), each QML file in the shared installed tree.
    QString qmlName;
    if (which == QStringLiteral("settings")) qmlName = QStringLiteral("SettingsApp.qml");
    else if (which == QStringLiteral("music")) qmlName = QStringLiteral("MusicApp.qml");
    else if (which == QStringLiteral("calculator")) qmlName = QStringLiteral("CalculatorApp.qml");
    else if (which == QStringLiteral("editor")) qmlName = QStringLiteral("EditorApp.qml");
    else if (which == QStringLiteral("monitor")) qmlName = QStringLiteral("MonitorApp.qml");
    else if (which == QStringLiteral("store")) qmlName = QStringLiteral("StoreApp.qml");
    else qmlName = QStringLiteral("FilesApp.qml");
    // W20 — pin the Wayland app_id to the product name: without it every
    // Aegis app reports resourceClass "aegis-apps" (the host binary) and
    // the aegis-windowwatch KWin script could not tell Files from Music,
    // so the dock running dots and the island predicate would read the
    // wrong app. The ids must match the dock cmds (aegis-files, ...).
    QGuiApplication::setDesktopFileName(QStringLiteral("aegis-%1").arg(which));
    // optional initial pane for Settings ("aegis-settings 8" opens the Aegis
    // ID pane directly — boot-capture uses this for the pane screenshots)
    int initialPane = -1;
    if (which == QStringLiteral("settings") && argc > 2)
        initialPane = QString::fromLocal8Bit(argv[2]).toInt();

    Util util;
    Governor governor(&util, nullptr);
    FileManager files;
    DisplaysBackend displays;
    SoundBackend sound;
    NetworkBackend network;
    UsersBackend users;
    StoreBackend store;
    AegisId aegisId;
    // M3 — Monitor + Editor backends
    MonitorBackend monitor;
    TextFileBackend textFile;

    // Aegis ID pulled a setting — route it: desktop.* through Util (persists
    // AND reaches the running shell over DBus), files.prefs into Files.
    QObject::connect(&aegisId, &AegisId::syncApplied, &util,
                     [&util, &files](const QString &key, const QString &json) {
        const QJsonObject obj = QJsonDocument::fromJson(json.toUtf8()).object();
        if (key == QStringLiteral("desktop.accent"))
            util.setAccent(obj.value(QStringLiteral("accent")).toString());
        else if (key == QStringLiteral("desktop.wallpaper"))
            util.setWallpaper(obj.value(QStringLiteral("wallpaper")).toString());
        else if (key == QStringLiteral("files.prefs"))
            files.saveViewPrefs(json);
    });

    QQmlEngine engine;
    engine.addImageProvider(QStringLiteral("icons"), new IconProvider());
    if (initialPane >= 0)
        engine.rootContext()->setContextProperty(QStringLiteral("aegisInitialPane"),
                                                 initialPane);
    // W26 — "aegis-files --path trash:///" opens Files AT that location
    // (the dock Trash slot); absent, the window stays on Home.
    for (int i = 2; i + 1 < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == QStringLiteral("--path")) {
            engine.rootContext()->setContextProperty(
                QStringLiteral("aegisInitialPath"),
                QString::fromLocal8Bit(argv[i + 1]));
            break;
        }
    }
    qmlRegisterSingletonInstance("Aegis.Util", 1, 0, "Util", &util);
    qmlRegisterSingletonInstance("Aegis.Governor", 1, 0, "Governor", &governor);
    qmlRegisterSingletonInstance("Aegis.Files", 1, 0, "Files", &files);
    // W3 backends + W6 account client
    qmlRegisterSingletonInstance("Aegis.Display", 1, 0, "Displays", &displays);
    qmlRegisterSingletonInstance("Aegis.Sound", 1, 0, "Sound", &sound);
    qmlRegisterSingletonInstance("Aegis.Network", 1, 0, "Network", &network);
    qmlRegisterSingletonInstance("Aegis.Users", 1, 0, "Users", &users);
    qmlRegisterSingletonInstance("Aegis.Store", 1, 0, "Store", &store);
    qmlRegisterSingletonInstance("Aegis.Id", 1, 0, "AegisId", &aegisId);
    // M3 — Monitor + Editor
    qmlRegisterSingletonInstance("Aegis.Monitor", 1, 0, "Monitor", &monitor);
    qmlRegisterSingletonInstance("Aegis.TextFile", 1, 0, "TextFile", &textFile);

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
