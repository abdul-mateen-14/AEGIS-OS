#include "util.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>

// Default session config — mirrors shell/packaging/config.json.
static QVariantMap defaultConfig()
{
    return QVariantMap{
        {QStringLiteral("wallpaper"),
         QStringLiteral("/usr/share/wallpapers/aegis/aurora-ink.jpg")},
        {QStringLiteral("apps"), QVariantList{
            QVariantMap{{"name", "Files"}, {"icon", "system-file-manager"},
                        {"cmd", "dolphin"}},
            QVariantMap{{"name", "Terminal"}, {"icon", "utilities-terminal"},
                        {"cmd", "konsole"}},
            QVariantMap{{"name", "AEGIS Browser"}, {"icon", "web-browser"},
                        {"cmd", "aegis-browser"}},            // .deb slot — see docs/APP-SLOTS.md
            QVariantMap{{"name", "OS Cloud"}, {"icon", "web-browser"},
                        {"cmd", "xdg-open https://os-cloudflare.pages.dev"}},
            QVariantMap{{"name", "CoreX"}, {"icon", "applications-internet"},
                        {"cmd", "xdg-open https://corex.site.je"}},
            QVariantMap{{"name", "Settings"}, {"icon", "preferences-system"},
                        {"cmd", "systemsettings"}},
            QVariantMap{{"type", "separator"}},
            QVariantMap{{"name", "Trash"}, {"icon", "user-trash"},
                        {"cmd", "dolphin trash:/"}},
        }},
    };
}

Util::Util(QObject *parent)
    : QObject(parent)
{
    m_config = readConfig(QStringLiteral("/usr/share/aegis/shell/config.json"));
    refreshBattery();
    m_batteryTimer.setInterval(30000);
    connect(&m_batteryTimer, &QTimer::timeout, this, &Util::refreshBattery);
    m_batteryTimer.start();
}

QVariantMap Util::readConfig(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return defaultConfig();

    QJsonParseError error{};
    const auto doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return defaultConfig();

    QVariantMap map = doc.object().toVariantMap();
    if (!map.contains(QStringLiteral("apps")))
        map.insert(QStringLiteral("apps"), defaultConfig().value(QStringLiteral("apps")));
    return map;
}

void Util::launch(const QString &command)
{
    if (command.isEmpty())
        return;
    QProcess::startDetached(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command});
}

void Util::powerAction(const QString &action)
{
    QString systemctlAction;
    if (action == QStringLiteral("suspend"))
        systemctlAction = QStringLiteral("suspend");
    else if (action == QStringLiteral("reboot"))
        systemctlAction = QStringLiteral("reboot");
    else if (action == QStringLiteral("shutdown"))
        systemctlAction = QStringLiteral("poweroff");
    else
        return;
    QProcess::startDetached(QStringLiteral("systemctl"), {systemctlAction});
}

void Util::refreshBattery()
{
    QDir powerSupply(QStringLiteral("/sys/class/power_supply"));
    int percent = -1;
    bool onBattery = false;

    const auto bats = powerSupply.entryList(
        {QStringLiteral("BAT*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &bat : bats) {
        QFile capacity(powerSupply.filePath(bat) + QStringLiteral("/capacity"));
        if (capacity.open(QIODevice::ReadOnly)) {
            bool ok = false;
            const int value = capacity.readAll().trimmed().toInt(&ok);
            if (ok && percent < 0)
                percent = value;
        }
        QFile status(powerSupply.filePath(bat) + QStringLiteral("/status"));
        if (status.open(QIODevice::ReadOnly)) {
            const QString s = QString::fromUtf8(status.readAll().trimmed());
            if (s == QStringLiteral("Discharging"))
                onBattery = true;
        }
    }

    if (percent != m_batteryPercent || onBattery != m_onBattery) {
        m_batteryPercent = percent;
        m_onBattery = onBattery;
        emit batteryChanged();
    }
}
