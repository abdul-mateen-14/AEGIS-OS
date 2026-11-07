// aegis-updates — the Software Update app of Aegis OS.
// A plain (non-layer-shell) Qt Quick window: it lives in the app world,
// launched from the Launcher, the Control Center tile or the dock —
// not from the shell compositor process.

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "updatemanager.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("Aegis OS Project"));
    QGuiApplication::setApplicationName(QStringLiteral("Software Update"));
    QGuiApplication::setApplicationVersion(QStringLiteral("1.4.1"));
    app.setWindowIcon(QIcon(QStringLiteral(":/updates/aegis-mark.png")));

    UpdateManager updates;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("Updates"), &updates);
    engine.load(QUrl(QStringLiteral("qrc:/updates/Updates.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}
