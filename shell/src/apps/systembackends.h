#pragma once
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <algorithm>
#include <unistd.h>

// ── W3 — Settings backends (M3 milestone, one pane each) ──────────────────
//
// Displays — kscreen-doctor (KScreen 2 CLI): parse outputs/modes/scale,
//   apply resolution + scale, night light through kwinrc + KWin reconfigure.
// Sound — wpctl (PipeWire/WirePlumber): sinks + sources, per-device volume,
//   mute, default device. No extra daemon.
// Network — NetworkManager D-Bus: devices, access points (SSID/strength),
//   known connections, AddAndActivateConnection for new networks.
// Users — AccountsService D-Bus: real name, admin flag, avatar; the current
//   user is flagged so the pane can show "you".
//
// House rule: C++ singletons hold logic, QML holds look — same as the shell.

namespace {

// "ao" replies arrive as QList<QDBusObjectPath> inside a QVariant.
QStringList dbusPaths(const QVariant &v)
{
    QStringList out;
    const QVariantList list = v.toList();
    for (const QVariant &item : list) {
        const QDBusObjectPath p = item.value<QDBusObjectPath>();
        if (!p.path().isEmpty())
            out << p.path();
    }
    return out;
}

QVariant dbusCall(const QString &service, const QString &path,
                  const QString &iface, const QString &method,
                  const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface,
                                                      method);
    msg.setArguments(args);
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    return reply.arguments().constFirst();
}

QVariant dbusGet(const QString &service, const QString &path,
                 const QString &iface, const QString &prop)
{
    return dbusCall(service, path,
                    QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("Get"),
                    QVariantList{iface, prop});
}

QVariantMap dbusGetAll(const QString &service, const QString &path,
                       const QString &iface)
{
    const QVariant v = dbusCall(service, path,
                                QStringLiteral("org.freedesktop.DBus.Properties"),
                                QStringLiteral("GetAll"),
                                QVariantList{iface});
    return v.toMap();
}

void dbusSet(const QString &service, const QString &path,
             const QString &iface, const QString &prop, const QVariant &value)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(
        service, path, QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Set"));
    msg.setArguments({iface, prop, value});
    QDBusConnection::sessionBus().asyncCall(msg);
}

void dbusAsync(const QString &service, const QString &path,
               const QString &iface, const QString &method,
               const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface,
                                                      method);
    msg.setArguments(args);
    QDBusConnection::sessionBus().asyncCall(msg);
}

} // namespace

// ── Displays ───────────────────────────────────────────────────────────────

class DisplaysBackend : public QObject {
    Q_OBJECT
    // [{name, current, scale, modes:[{mode, w, h, rate}]}]
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY changed)
    Q_PROPERTY(bool nightLight READ nightLight WRITE setNightLight NOTIFY changed)
public:
    explicit DisplaysBackend(QObject *parent = nullptr) : QObject(parent)
    {
        refresh();
    }

    QVariantList outputs() const { return m_outputs; }

    bool nightLight() const
    {
        QSettings kwinrc(QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation)
                             + QStringLiteral("/kwinrc"),
                         QSettings::IniFormat);
        return kwinrc.value(QStringLiteral("NightColor/Active"), false).toBool();
    }

    Q_INVOKABLE void refresh()
    {
        m_outputs.clear();
        const QString doctor = QStandardPaths::findExecutable(
            QStringLiteral("kscreen-doctor"), {QStringLiteral("/usr/bin")});
        if (!doctor.isEmpty()) {
            QProcess p;
            p.start(doctor, {QStringLiteral("-o")});
            p.waitForFinished(2500);
            const QString out = QString::fromUtf8(p.readAllStandardOutput());

            QVariantMap current;
            const QStringList lines = out.split(QLatin1Char('\n'));
            for (const QString &raw : lines) {
                const QString line = raw.trimmed();
                // "Output: 1 eDP-1 enabled connected priority 1 panel"
                if (line.startsWith(QLatin1String("Output:"))) {
                    if (!current.isEmpty())
                        m_outputs.append(current);
                    const QStringList parts =
                        line.split(QLatin1Char(' '),
                                   Qt::SkipEmptyParts);
                    current = QVariantMap{
                        {QStringLiteral("name"),
                         parts.value(2, QStringLiteral("output"))},
                        {QStringLiteral("modes"), QVariantList{}},
                        {QStringLiteral("current"), QString()},
                        {QStringLiteral("scale"), 1.0},
                    };
                    continue;
                }
                if (current.isEmpty())
                    continue;
                if (line.startsWith(QLatin1String("Modes:"))
                    || line.startsWith(QLatin1String("Mode:"))) {
                    // Modes: "1920x1080@60.03" 1920x1080 60.03 "1920x1080@59.94" …
                    const QRegularExpression re(
                        QStringLiteral("\"(\\d+x\\d+)@([\\d.]+)\""));
                    auto it = re.globalMatch(line);
                    QVariantList modes = current.value(QStringLiteral("modes"))
                                             .toList();
                    while (it.hasNext()) {
                        const auto m = it.next();
                        modes.append(QVariantMap{
                            {QStringLiteral("mode"),
                             m.captured(1) + QLatin1Char('@') + m.captured(2)},
                            {QStringLiteral("w"),
                             m.captured(1).section(QLatin1Char('x'), 0, 0)
                                 .toInt()},
                            {QStringLiteral("h"),
                             m.captured(1).section(QLatin1Char('x'), 1, 1)
                                 .toInt()},
                            {QStringLiteral("rate"), m.captured(2)},
                        });
                    }
                    if (line.startsWith(QLatin1String("Mode:")) && !modes.isEmpty())
                        current.insert(QStringLiteral("current"),
                                       modes.last().toMap().value(
                                           QStringLiteral("mode")));
                    current.insert(QStringLiteral("modes"), modes);
                    continue;
                }
                if (line.startsWith(QLatin1String("Scale:"))) {
                    bool ok = false;
                    const qreal s =
                        line.section(QLatin1Char(' '), 1, 1).toDouble(&ok);
                    if (ok)
                        current.insert(QStringLiteral("scale"), s);
                    continue;
                }
            }
            if (!current.isEmpty())
                m_outputs.append(current);
        }
        emit changed();
    }

    Q_INVOKABLE void setResolution(const QString &output, const QString &mode)
    {
        runKscreen(QStringLiteral("output.") + output
                   + QStringLiteral(".mode.") + mode);
    }

    Q_INVOKABLE void setScale(const QString &output, qreal scale)
    {
        runKscreen(QStringLiteral("output.") + output
                   + QStringLiteral(".scale.")
                   + QString::number(scale, 'f', 2));
    }

    // Night light: write the KWin NightColor block, reconfigure KWin live.
    Q_INVOKABLE void setNightLight(bool on)
    {
        const QString kwriteconfig = QStandardPaths::findExecutable(
            QStringLiteral("kwriteconfig6"), {QStringLiteral("/usr/bin")});
        if (!kwriteconfig.isEmpty()) {
            const auto set = [&kwriteconfig](const QString &key,
                                             const QString &value) {
                QProcess::startDetached(kwriteconfig,
                                        {QStringLiteral("--file"),
                                         QStringLiteral("kwinrc"),
                                         QStringLiteral("--group"),
                                         QStringLiteral("NightColor"),
                                         QStringLiteral("--key"), key, value});
            };
            set(QStringLiteral("Active"),
                on ? QStringLiteral("true") : QStringLiteral("false"));
            if (on) {
                // A working default when the user only flips the switch.
                set(QStringLiteral("Mode"), QStringLiteral("TimingsFixed"));
                set(QStringLiteral("EveningBeginFixed"), QStringLiteral("2000"));
                set(QStringLiteral("MorningBeginFixed"), QStringLiteral("0600"));
                set(QStringLiteral("Temperature"), QStringLiteral("3800"));
            }
        }
        // KWin picks config changes up live.
        dbusAsync(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                  QStringLiteral("org.kde.KWin"),
                  QStringLiteral("reconfigure"));
        QTimer::singleShot(300, this, &DisplaysBackend::changed);
    }

signals:
    void changed();

private:
    void runKscreen(const QString &arg)
    {
        QProcess::startDetached(
            QStandardPaths::findExecutable(QStringLiteral("kscreen-doctor"),
                                           {QStringLiteral("/usr/bin")}),
            {arg});
        // outputs re-read after KScreen applies
        QTimer::singleShot(1200, this, &DisplaysBackend::refresh);
    }

    QVariantList m_outputs;
};

// ── Sound ────────────────────────────────────────────────────────────────

class SoundBackend : public QObject {
    Q_OBJECT
    // [{id, name, volume, muted, isDefault}]
    Q_PROPERTY(QVariantList sinks READ sinks NOTIFY changed)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY changed)
public:
    explicit SoundBackend(QObject *parent = nullptr) : QObject(parent)
    {
        refresh();
    }

    QVariantList sinks() const { return m_sinks; }
    QVariantList sources() const { return m_sources; }

    Q_INVOKABLE void refresh()
    {
        m_sinks.clear();
        m_sources.clear();
        const QString wpctl = QStandardPaths::findExecutable(
            QStringLiteral("wpctl"), {QStringLiteral("/usr/bin")});
        if (!wpctl.isEmpty()) {
            QProcess p;
            p.start(wpctl, {QStringLiteral("status")});
            p.waitForFinished(2500);
            const QString out = QString::fromUtf8(p.readAllStandardOutput());

            enum Section { None, Sinks, Sources } section = None;
            // " * 63. Built-in Audio Analog Stereo [vol: 0.65]"
            const QRegularExpression re(
                QStringLiteral("^\\s*(\\*?)\\s*(\\d+)\\.\\s+(.*?)\\s*(\\[vol:\\s+([\\d.]+)([^\\]]*)\\])?\\s*$"));
            for (const QString &line : out.split(QLatin1Char('\n'))) {
                if (line.contains(QLatin1String("Sinks:")))
                    section = Sinks;
                else if (line.contains(QLatin1String("Sources:")))
                    section = Sources;
                else if (line.contains(QLatin1String("Clients:"))
                         || line.contains(QLatin1String("Filters:"))
                         || line.contains(QLatin1String("Video:")))
                    section = None;
                const auto m = re.match(line);
                if (!m.hasMatch())
                    continue;
                QVariantMap entry{
                    {QStringLiteral("id"), m.captured(2).toInt()},
                    {QStringLiteral("name"), m.captured(3).trimmed()},
                    {QStringLiteral("volume"),
                     m.captured(5).isEmpty()
                         ? 0.5
                         : qBound(0.0, m.captured(5).toDouble(), 1.5)},
                    {QStringLiteral("muted"),
                     m.captured(6).contains(QLatin1String("MUTED"))},
                    {QStringLiteral("isDefault"), !m.captured(1).isEmpty()},
                };
                if (section == Sinks)
                    m_sinks.append(entry);
                else if (section == Sources)
                    m_sources.append(entry);
            }
        }
        emit changed();
    }

    Q_INVOKABLE void setVolume(int id, qreal v)
    {
        run({QStringLiteral("set-volume"), QString::number(id),
             QString::number(qBound(0.0, v, 1.5), 'f', 2)});
    }

    Q_INVOKABLE void setMuted(int id, bool muted)
    {
        run({QStringLiteral("set-mute"), QString::number(id),
             muted ? QStringLiteral("1") : QStringLiteral("0")});
    }

    Q_INVOKABLE void setDefault(int id)
    {
        run({QStringLiteral("set-default"), QString::number(id)});
    }

signals:
    void changed();

private:
    void run(const QStringList &args)
    {
        QProcess::startDetached(
            QStandardPaths::findExecutable(QStringLiteral("wpctl"),
                                           {QStringLiteral("/usr/bin")}),
            args);
        QTimer::singleShot(400, this, &SoundBackend::refresh);
    }

    QVariantList m_sinks;
    QVariantList m_sources;
};

// ── Network ──────────────────────────────────────────────────────────────

class NetworkBackend : public QObject {
    Q_OBJECT
    // [{ssid, strength, secure, known, inUse}]
    Q_PROPERTY(QVariantList networks READ networks NOTIFY changed)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)
public:
    explicit NetworkBackend(QObject *parent = nullptr) : QObject(parent) {}

    QVariantList networks() const { return m_networks; }

    bool wifiEnabled() const
    {
        const QVariant v = dbusGet(
            QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("/org/freedesktop/NetworkManager"),
            QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("WirelessEnabled"));
        return v.isValid() && v.toBool();
    }

    Q_INVOKABLE void refresh()
    {
        loadKnown();
        m_networks.clear();
        const QString nm = QStringLiteral("org.freedesktop.NetworkManager");
        const QString nmPath = QStringLiteral("/org/freedesktop/NetworkManager");

        // active connections → the SSIDs currently in use
        QStringList activeSsids;
        const QVariant active = dbusGet(nm, nmPath, nm,
                                        QStringLiteral("ActiveConnections"));
        for (const QString &p : dbusPaths(active)) {
            const QVariantMap am = dbusGetAll(nm, p,
                QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"));
            const QDBusObjectPath conn = am.value(
                QStringLiteral("Connection")).value<QDBusObjectPath>();
            if (conn.path().isEmpty())
                continue;
            const QVariantMap settings = dbusCall(nm, conn.path(),
                QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"),
                QStringLiteral("GetSettings")).toMap();
            if (settings.contains(QStringLiteral("802-11-wireless"))) {
                const QByteArray ssid = settings
                    .value(QStringLiteral("802-11-wireless")).toMap()
                    .value(QStringLiteral("ssid")).toByteArray();
                if (!ssid.isEmpty())
                    activeSsids << QString::fromUtf8(ssid);
            }
        }

        // the Wi-Fi device (DeviceType 2) and its access points
        QString wifiDevice;
        const QVariant devs = dbusGet(nm, nmPath, nm,
                                      QStringLiteral("Devices"));
        for (const QString &p : dbusPaths(devs)) {
            const QVariantMap dm = dbusGetAll(nm, p,
                QStringLiteral("org.freedesktop.NetworkManager.Device"));
            if (dm.value(QStringLiteral("DeviceType")).toUInt() == 2u) {
                wifiDevice = p;
                break;
            }
        }
        if (!wifiDevice.isEmpty()) {
            const QVariant aps = dbusCall(nm, wifiDevice,
                QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless"),
                QStringLiteral("GetAccessPoints"));
            for (const QString &ap : dbusPaths(aps)) {
                const QVariantMap pm = dbusGetAll(nm, ap,
                    QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"));
                const QString ssid = QString::fromUtf8(
                    pm.value(QStringLiteral("Ssid")).toByteArray());
                if (ssid.isEmpty())
                    continue;
                m_networks.append(QVariantMap{
                    {QStringLiteral("ssid"), ssid},
                    {QStringLiteral("strength"),
                     pm.value(QStringLiteral("Strength")).toUInt()},
                    {QStringLiteral("secure"),
                     pm.value(QStringLiteral("WpaFlags")).toUInt() != 0u},
                    {QStringLiteral("known"), m_knownSsids.contains(ssid)},
                    {QStringLiteral("inUse"), activeSsids.contains(ssid)},
                });
            }
        }
        // strongest first
        std::sort(m_networks.begin(), m_networks.end(),
                  [](const QVariant &a, const QVariant &b) {
                      return a.toMap().value(QStringLiteral("strength")).toUInt()
                             > b.toMap().value(QStringLiteral("strength")).toUInt();
                  });
        emit changed();
    }

    Q_INVOKABLE void setWifiEnabled(bool on)
    {
        dbusAsync(QStringLiteral("org.freedesktop.NetworkManager"),
                  QStringLiteral("/org/freedesktop/NetworkManager"),
                  QStringLiteral("org.freedesktop.NetworkManager"),
                  QStringLiteral("EnableWireless"), QVariantList{on});
        QTimer::singleShot(1500, this, &NetworkBackend::refresh);
        QTimer::singleShot(3500, this, &NetworkBackend::refresh);
    }

    // Connect to a visible network: NM picks the stored secret (known) or
    // asks through the agent (none yet — WPA networks then fail visibly).
    Q_INVOKABLE void connectTo(const QString &ssid)
    {
        const QString ap = apFor(ssid);
        const QString dev = wifiDevicePath();
        if (ap.isEmpty() || dev.isEmpty())
            return;
        dbusAsync(QStringLiteral("org.freedesktop.NetworkManager"),
                  QStringLiteral("/org/freedesktop/NetworkManager"),
                  QStringLiteral("org.freedesktop.NetworkManager"),
                  QStringLiteral("AddAndActivateConnection"),
                  QVariantList{QVariantMap{}, QDBusObjectPath(dev),
                               QDBusObjectPath(ap)});
        QTimer::singleShot(2500, this, &NetworkBackend::refresh);
    }

    // Load the known-connection SSID set (Settings.ListConnections).
    Q_INVOKABLE void loadKnown()
    {
        m_knownSsids.clear();
        const QVariant conns = dbusCall(
            QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("/org/freedesktop/NetworkManager/Settings"),
            QStringLiteral("org.freedesktop.NetworkManager.Settings"),
            QStringLiteral("ListConnections"));
        for (const QString &p : dbusPaths(conns)) {
            const QVariantMap settings = dbusCall(
                QStringLiteral("org.freedesktop.NetworkManager"), p,
                QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"),
                QStringLiteral("GetSettings")).toMap();
            if (!settings.contains(QStringLiteral("802-11-wireless")))
                continue;
            const QByteArray ssid = settings
                .value(QStringLiteral("802-11-wireless")).toMap()
                .value(QStringLiteral("ssid")).toByteArray();
            if (!ssid.isEmpty())
                m_knownSsids << QString::fromUtf8(ssid);
        }
    }

signals:
    void changed();

private:
    QString wifiDevicePath()
    {
        const QVariant devs = dbusGet(
            QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("/org/freedesktop/NetworkManager"),
            QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("Devices"));
        for (const QString &p : dbusPaths(devs)) {
            const QVariantMap dm = dbusGetAll(
                QStringLiteral("org.freedesktop.NetworkManager"), p,
                QStringLiteral("org.freedesktop.NetworkManager.Device"));
            if (dm.value(QStringLiteral("DeviceType")).toUInt() == 2u)
                return p;
        }
        return {};
    }

    QString apFor(const QString &ssid)
    {
        const QString dev = wifiDevicePath();
        if (dev.isEmpty())
            return {};
        const QVariant aps = dbusCall(
            QStringLiteral("org.freedesktop.NetworkManager"), dev,
            QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless"),
            QStringLiteral("GetAccessPoints"));
        QString best;
        uint bestStrength = 0;
        for (const QString &ap : dbusPaths(aps)) {
            const QVariantMap pm = dbusGetAll(
                QStringLiteral("org.freedesktop.NetworkManager"), ap,
                QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"));
            if (QString::fromUtf8(
                    pm.value(QStringLiteral("Ssid")).toByteArray()) != ssid)
                continue;
            const uint s = pm.value(QStringLiteral("Strength")).toUInt();
            if (s >= bestStrength) {
                bestStrength = s;
                best = ap;
            }
        }
        return best;
    }

    QVariantList m_networks;
    QStringList m_knownSsids;
};

// ── Users (AccountsService) ──────────────────────────────────────────────

class UsersBackend : public QObject {
    Q_OBJECT
    // [{path, userName, realName, email, admin, isYou, icon}]
    Q_PROPERTY(QVariantList users READ users NOTIFY changed)
public:
    explicit UsersBackend(QObject *parent = nullptr) : QObject(parent) {}

    QVariantList users() const { return m_users; }

    Q_INVOKABLE void refresh()
    {
        m_users.clear();
        const QVariant users = dbusCall(
            QStringLiteral("org.freedesktop.Accounts"),
            QStringLiteral("/org/freedesktop/Accounts"),
            QStringLiteral("org.freedesktop.Accounts"),
            QStringLiteral("ListCachedUsers"));
        for (const QString &p : dbusPaths(users)) {
            const QVariantMap pm = dbusGetAll(
                QStringLiteral("org.freedesktop.Accounts"), p,
                QStringLiteral("org.freedesktop.Accounts.User"));
            if (pm.isEmpty())
                continue;
            m_users.append(QVariantMap{
                {QStringLiteral("path"), p},
                {QStringLiteral("userName"),
                 pm.value(QStringLiteral("UserName")).toString()},
                {QStringLiteral("realName"),
                 pm.value(QStringLiteral("RealName")).toString()},
                {QStringLiteral("email"),
                 pm.value(QStringLiteral("Email")).toString()},
                {QStringLiteral("admin"),
                 pm.value(QStringLiteral("AccountType")).toUInt() == 1u},
                {QStringLiteral("isYou"),
                 p.endsWith(QStringLiteral("/User")
                            + QString::number(getuid()))},
                {QStringLiteral("icon"),
                 pm.value(QStringLiteral("IconFile")).toString()},
            });
        }
        emit changed();
    }

    Q_INVOKABLE void setRealName(const QString &userPath, const QString &name)
    {
        dbusSet(QStringLiteral("org.freedesktop.Accounts"), userPath,
                QStringLiteral("org.freedesktop.Accounts.User"),
                QStringLiteral("RealName"), name);
        QTimer::singleShot(500, this, &UsersBackend::refresh);
    }

    Q_INVOKABLE void setAdmin(const QString &userPath, bool admin)
    {
        dbusAsync(QStringLiteral("org.freedesktop.Accounts"), userPath,
                  QStringLiteral("org.freedesktop.Accounts.User"),
                  QStringLiteral("SetAccountType"),
                  QVariantList{admin ? 1 : 0});
        QTimer::singleShot(500, this, &UsersBackend::refresh);
    }

    Q_INVOKABLE void setAvatar(const QString &userPath, const QString &path)
    {
        dbusAsync(QStringLiteral("org.freedesktop.Accounts"), userPath,
                  QStringLiteral("org.freedesktop.Accounts.User"),
                  QStringLiteral("SetIconFile"), QVariantList{path});
        QTimer::singleShot(500, this, &UsersBackend::refresh);
    }

signals:
    void changed();

private:
    QVariantList m_users;
};
