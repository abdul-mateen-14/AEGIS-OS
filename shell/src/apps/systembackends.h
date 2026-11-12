#pragma once
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
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

// ── T14 — Store: the apt-backed app store (famous Ubuntu/Debian apps) ────
//
// One curated catalog (name, category, description, apt package set), an
// installed check per entry (dpkg-query), and install/remove through
// `sudo -n apt-get` (the live user is NOPASSWD via 0610). The runner VM's
// usermode NAT reaches the archive, so installs really work in CI; the
// output streams into ~/.local/state/aegis-shell/aegis/store/<id>.log.
class StoreBackend : public QObject {
    Q_OBJECT
    // [{id, name, category, description, pkgs, installed}]
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY catalogChanged)
    Q_PROPERTY(QString installingId READ installingId NOTIFY busyChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY busyChanged)

public:
    explicit StoreBackend(QObject *parent = nullptr) : QObject(parent)
    {
        m_stateDir = QStandardPaths::writableLocation(
                         QStandardPaths::StateLocation)
                     + QStringLiteral("/aegis/store");
        QDir().mkpath(m_stateDir);
    }

    QVariantList catalog() const { return m_catalog; }
    QString installingId() const { return m_installingId; }
    QString lastMessage() const { return m_lastMessage; }

    Q_INVOKABLE void refresh()
    {
        for (const QVariant &v : std::as_const(m_catalog)) {
            const QVariantMap m = v.toMap();
            const QStringList pkgs =
                m.value(QStringLiteral("pkgs")).toStringList();
            const bool installed = !pkgs.isEmpty()
                && pkgInstalled(pkgs.first());
            setInstalled(m.value(QStringLiteral("id")).toString(), installed);
        }
        emit catalogChanged();
    }

    Q_INVOKABLE void install(const QString &id)
    {
        if (!m_installingId.isEmpty())
            return;
        const QVariantMap m = entry(id);
        if (m.isEmpty())
            return;
        const QStringList pkgs =
            m.value(QStringLiteral("pkgs")).toStringList();
        startProcess(QStringLiteral("install"), id,
                     QStringList() << QStringLiteral("-n")
                                   << QStringLiteral("apt-get")
                                   << QStringLiteral("install") << QStringLiteral("-y")
                                   << pkgs);
    }

    Q_INVOKABLE void remove(const QString &id)
    {
        if (!m_installingId.isEmpty())
            return;
        const QVariantMap m = entry(id);
        if (m.isEmpty())
            return;
        const QStringList pkgs =
            m.value(QStringLiteral("pkgs")).toStringList();
        startProcess(QStringLiteral("remove"), id,
                     QStringList() << QStringLiteral("-n")
                                   << QStringLiteral("apt-get")
                                   << QStringLiteral("remove") << QStringLiteral("-y")
                                   << pkgs);
    }

signals:
    void catalogChanged();
    void busyChanged();
    void installFinished(const QString &id, bool ok, const QString &message);

private:
    QVariantMap entry(const QString &id) const
    {
        for (const QVariant &v : std::as_const(m_catalog)) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("id")).toString() == id)
                return m;
        }
        return {};
    }

    bool pkgInstalled(const QString &pkg) const
    {
        QProcess p;
        p.start(QStringLiteral("dpkg-query"),
                {QStringLiteral("-W"), QStringLiteral("-f=${Status}"), pkg});
        p.waitForFinished(4000);
        return QString::fromUtf8(p.readAllStandardOutput())
            .contains(QStringLiteral("install ok installed"));
    }

    void setInstalled(const QString &id, bool installed)
    {
        for (int i = 0; i < m_catalog.size(); ++i) {
            QVariantMap m = m_catalog.at(i).toMap();
            if (m.value(QStringLiteral("id")).toString() == id) {
                m.insert(QStringLiteral("installed"), installed);
                m_catalog[i] = m;
                return;
            }
        }
    }

    void startProcess(const QString &kind, const QString &id,
                      const QStringList &aptArgs)
    {
        m_installingId = id;
        m_lastMessage = QStringLiteral("Starting…");
        emit busyChanged();
        const QString logPath = m_stateDir
                                + QStringLiteral("/%1.log").arg(id);
        QFile(logPath).remove();
        QProcess *p = new QProcess(this);
        p->setProgram(QStringLiteral("sudo"));
        p->setArguments(aptArgs);
        p->setProcessChannelMode(QProcess::MergedChannels);
        // the apt output streams into the per-app log and the message line
        connect(p, &QProcess::readyReadStandardOutput, this, [this, p]() {
            const QByteArray chunk = p->readAllStandardOutput();
            m_lastMessage = QString::fromUtf8(chunk)
                .trimmed()
                .section(QLatin1Char('\n'), -1)
                .left(160);
            emit busyChanged();
            QFile log(logPath);
            if (log.open(QIODevice::WriteOnly | QIODevice::Append))
                log.write(chunk);
        });
        connect(p, &QProcess::finished, this,
                [this, p, kind, id, logPath](int code, QProcess::ExitStatus) {
                    const bool ok = code == 0;
                    QFile log(logPath);
                    if (log.open(QIODevice::WriteOnly | QIODevice::Append
                                 | QIODevice::Text)) {
                        log.write(("\n--- " + kind + " finished "
                                   + (ok ? QStringLiteral("ok")
                                         : QStringLiteral("failed")))
                                      .toUtf8());
                        log.close();
                    }
                    p->deleteLater();
                    m_installingId.clear();
                    m_lastMessage = ok
                        ? QStringLiteral("Done")
                        : QStringLiteral("Failed — see the store log");
                    refresh();
                    emit busyChanged();
                    emit installFinished(id, ok, m_lastMessage);
                });
        p->start();
    }

    QString m_stateDir;
    QVariantList m_catalog = {
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("vlc") },
          { QStringLiteral("name"), QStringLiteral("VLC") },
          { QStringLiteral("category"), QStringLiteral("Multimedia") },
          { QStringLiteral("description"),
            QStringLiteral("The universal media player — every format, "
                           "no codecs to hunt for") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("vlc")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("gimp") },
          { QStringLiteral("name"), QStringLiteral("GIMP") },
          { QStringLiteral("category"), QStringLiteral("Graphics") },
          { QStringLiteral("description"),
            QStringLiteral("The GNU Image Manipulation Program — the open "
                           "Photoshop") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("gimp")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("inkscape") },
          { QStringLiteral("name"), QStringLiteral("Inkscape") },
          { QStringLiteral("category"), QStringLiteral("Graphics") },
          { QStringLiteral("description"),
            QStringLiteral("Vector drawing, the SVG professional") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("inkscape")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("blender") },
          { QStringLiteral("name"), QStringLiteral("Blender") },
          { QStringLiteral("category"), QStringLiteral("Graphics") },
          { QStringLiteral("description"),
            QStringLiteral("3D modeling, animation, rendering, video") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("blender")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("krita") },
          { QStringLiteral("name"), QStringLiteral("Krita") },
          { QStringLiteral("category"), QStringLiteral("Graphics") },
          { QStringLiteral("description"),
            QStringLiteral("Digital painting, sketching and comics") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("krita")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("audacity") },
          { QStringLiteral("name"), QStringLiteral("Audacity") },
          { QStringLiteral("category"), QStringLiteral("Multimedia") },
          { QStringLiteral("description"),
            QStringLiteral("The audio editor and recorder") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("audacity")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("obs") },
          { QStringLiteral("name"), QStringLiteral("OBS Studio") },
          { QStringLiteral("category"), QStringLiteral("Multimedia") },
          { QStringLiteral("description"),
            QStringLiteral("Screen recording and live streaming") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("obs-studio")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("libreoffice") },
          { QStringLiteral("name"), QStringLiteral("LibreOffice") },
          { QStringLiteral("category"), QStringLiteral("Office") },
          { QStringLiteral("description"),
            QStringLiteral("Writer, Calc, Impress — the full office suite") },
          { QStringLiteral("pkgs"),
            QStringList{QStringLiteral("libreoffice"),
                        QStringLiteral("libreoffice-gtk3")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("thunderbird") },
          { QStringLiteral("name"), QStringLiteral("Thunderbird") },
          { QStringLiteral("category"), QStringLiteral("Office") },
          { QStringLiteral("description"),
            QStringLiteral("Email, calendar and chat") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("thunderbird")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("firefox") },
          { QStringLiteral("name"), QStringLiteral("Firefox") },
          { QStringLiteral("category"), QStringLiteral("Internet") },
          { QStringLiteral("description"),
            QStringLiteral("The classic open web browser") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("firefox")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("telegram") },
          { QStringLiteral("name"), QStringLiteral("Telegram Desktop") },
          { QStringLiteral("category"), QStringLiteral("Internet") },
          { QStringLiteral("description"),
            QStringLiteral("The Telegram messenger, desktop client") },
          { QStringLiteral("pkgs"),
            QStringList{QStringLiteral("telegram-desktop")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("filezilla") },
          { QStringLiteral("name"), QStringLiteral("FileZilla") },
          { QStringLiteral("category"), QStringLiteral("Internet") },
          { QStringLiteral("description"),
            QStringLiteral("FTP/SFTP client with a site manager") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("filezilla")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("transmission") },
          { QStringLiteral("name"), QStringLiteral("Transmission") },
          { QStringLiteral("category"), QStringLiteral("Internet") },
          { QStringLiteral("description"),
            QStringLiteral("The lightweight BitTorrent client") },
          { QStringLiteral("pkgs"),
            QStringList{QStringLiteral("transmission-gtk")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("keepassxc") },
          { QStringLiteral("name"), QStringLiteral("KeePassXC") },
          { QStringLiteral("category"), QStringLiteral("Utilities") },
          { QStringLiteral("description"),
            QStringLiteral("The password manager — KDBX, offline") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("keepassxc")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("flameshot") },
          { QStringLiteral("name"), QStringLiteral("Flameshot") },
          { QStringLiteral("category"), QStringLiteral("Utilities") },
          { QStringLiteral("description"),
            QStringLiteral("Annotating screenshots with a full toolbox") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("flameshot")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("gparted") },
          { QStringLiteral("name"), QStringLiteral("GParted") },
          { QStringLiteral("category"), QStringLiteral("Utilities") },
          { QStringLiteral("description"),
            QStringLiteral("The partition editor") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("gparted")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("synaptic") },
          { QStringLiteral("name"), QStringLiteral("Synaptic") },
          { QStringLiteral("category"), QStringLiteral("Utilities") },
          { QStringLiteral("description"),
            QStringLiteral("The classic full-power package manager") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("synaptic")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("htop") },
          { QStringLiteral("name"), QStringLiteral("htop") },
          { QStringLiteral("category"), QStringLiteral("Utilities") },
          { QStringLiteral("description"),
            QStringLiteral("The interactive process viewer") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("htop")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("kate") },
          { QStringLiteral("name"), QStringLiteral("Kate") },
          { QStringLiteral("category"), QStringLiteral("Development") },
          { QStringLiteral("description"),
            QStringLiteral("The KDE advanced text editor") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("kate")} } },
        QVariantMap{ { QStringLiteral("id"), QStringLiteral("git") },
          { QStringLiteral("name"), QStringLiteral("Git") },
          { QStringLiteral("category"), QStringLiteral("Development") },
          { QStringLiteral("description"),
            QStringLiteral("Distributed version control (also the CLI)") },
          { QStringLiteral("pkgs"), QStringList{QStringLiteral("git")} } },
    };
    QString m_installingId;
    QString m_lastMessage;
};
