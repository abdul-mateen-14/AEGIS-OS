// Aegis ID — the identity module of AEGIS OS (Aegis-original, MIT).
// Reads only what is on this device: user, hostname, os-release. No
// network, no telemetry — the privacy row in the card is a design
// contract, not decoration.
#include <QFile>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QObject>
#include <pwd.h>
#include <sys/utsname.h>
#include <unistd.h>

class DeviceInfo : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    Q_PROPERTY(QString osName READ osName CONSTANT)
public:
    explicit DeviceInfo(QObject *parent = nullptr) : QObject(parent) {}

    QString userName() const {
        struct passwd *pw = getpwuid(getuid());
        return pw ? QString::fromLocal8Bit(pw->pw_name) : QStringLiteral("aegis");
    }

    QString hostName() const {
        struct utsname u;
        return uname(&u) == 0 ? QString::fromLocal8Bit(u.nodename)
                              : QStringLiteral("aegis");
    }

    QString osName() const {
        QFile f(QStringLiteral("/etc/os-release"));
        if (f.open(QIODevice::ReadOnly)) {
            while (!f.atEnd()) {
                const QByteArray line = f.readLine();
                if (line.startsWith("PRETTY_NAME="))
                    return QString::fromUtf8(line.mid(12).trimmed());
            }
        }
        return QStringLiteral("Aegis OS");
    }
};

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Aegis OS"));
    app.setApplicationName(QStringLiteral("aegis-id"));

    DeviceInfo info;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("DeviceInfo"), &info);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;
    return app.exec();
}

#include "main.moc"
