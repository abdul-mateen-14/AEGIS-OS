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

    // D21 (W30.1/W33.4) — presentation mode: one toggle that (a) holds an
    // org.freedesktop.ScreenSaver inhibit for as long as it is on (sleep
    // and screen-off stay away — the portal routes into the compositor's
    // idle inhibition) and (b) records the state to
    // ~/.local/state/aegis-shell/aegis/presentation so the boot harness
    // has a file-based verdict. Brightness rides Util from the pane (max
    // while presenting, restored after).
    Q_PROPERTY(bool presentation READ presentation WRITE setPresentation
               NOTIFY presentationChanged)
    bool presentation() const { return m_presentation; }

    Q_INVOKABLE void setPresentation(bool on)
    {
        if (on == m_presentation)
            return;
        if (on) {
            QDBusMessage msg = QDBusMessage::createMethodCall(
                QStringLiteral("org.freedesktop.ScreenSaver"),
                QStringLiteral("/org/freedesktop/ScreenSaver"),
                QStringLiteral("org.freedesktop.ScreenSaver"),
                QStringLiteral("Inhibit"));
            msg.setArguments({QStringLiteral("aegis-shell"),
                              QStringLiteral("presentation mode")});
            QDBusReply<uint> reply = QDBusConnection::sessionBus().call(msg);
            m_inhibitCookie = reply.isValid() ? reply.value() : 0u;
        } else if (m_inhibitCookie != 0) {
            dbusAsync(QStringLiteral("org.freedesktop.ScreenSaver"),
                      QStringLiteral("/org/freedesktop/ScreenSaver"),
                      QStringLiteral("org.freedesktop.ScreenSaver"),
                      QStringLiteral("UnInhibit"),
                      {QVariant::fromValue(m_inhibitCookie)});
            m_inhibitCookie = 0;
        }
        m_presentation = on;
        const QString path =
            QStandardPaths::writableLocation(
                QStandardPaths::GenericStateLocation)
            + QStringLiteral("/aegis-shell/aegis/presentation");
        QDir().mkpath(path.section(QLatin1Char('/'), 0, -2));
        QFile f(path);
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate
                   | QIODevice::Text)) {
            const QByteArray body = QStringLiteral(
                "presentation=%1\ncookie=%2\n")
                .arg(on ? QStringLiteral("on") : QStringLiteral("off"))
                .arg(m_inhibitCookie).toUtf8();
            f.write(body);
        }
        emit presentationChanged();
    }

signals:
    void changed();
    void presentationChanged();

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
    // D21 — presentation mode state (session-scoped: an inhibit dies with
    // the process, so the toggle always starts off on a fresh session)
    bool m_presentation = false;
    uint m_inhibitCookie = 0;
};

// ── Sound ────────────────────────────────────────────────────────────────

class SoundBackend : public QObject {
    Q_OBJECT
    // [{id, name, volume, muted, isDefault}]
    Q_PROPERTY(QVariantList sinks READ sinks NOTIFY changed)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY changed)
    // W30 — honest empty states: wpctl missing, PipeWire running with no
    // output device, and a live sink are three different facts; the pane
    // must not render one placeholder line for all of them.
    Q_PROPERTY(QString state READ state NOTIFY changed)
public:
    explicit SoundBackend(QObject *parent = nullptr) : QObject(parent)
    {
        refresh();
    }

    QVariantList sinks() const { return m_sinks; }
    QVariantList sources() const { return m_sources; }
    QString state() const { return m_state; }

    Q_INVOKABLE void refresh()
    {
        m_sinks.clear();
        m_sources.clear();
        m_state = QStringLiteral("nowpctl");
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
            // W30 — wpctl ran: PipeWire is answering, devices may still be
            // absent (a VM with no audio backend exposes no sinks).
            m_state = m_sinks.isEmpty()
                          ? QStringLiteral("nodevice")
                          : QStringLiteral("pipewire");
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
    QString m_state;
};

// ── Network ──────────────────────────────────────────────────────────────

class NetworkBackend : public QObject {
    Q_OBJECT
    // [{ssid, strength, secure, known, inUse}]
    Q_PROPERTY(QVariantList networks READ networks NOTIFY changed)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)
    // W30/W32 — ethernet devices: VMs (and most desktops) are wired-first;
    // the pane must never be a dead wifi list.
    // [{iface, plugged, active}]
    Q_PROPERTY(QVariantList wired READ wired NOTIFY changed)
    // W32 — a Wi-Fi device exists at all (the runner VM has none: say so
    // instead of "scanning...").
    Q_PROPERTY(bool hasWifi READ hasWifi NOTIFY changed)
public:
    explicit NetworkBackend(QObject *parent = nullptr) : QObject(parent) {}

    QVariantList networks() const { return m_networks; }
    QVariantList wired() const { return m_wired; }
    bool hasWifi() const { return m_hasWifi; }

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

        // the Wi-Fi device (DeviceType 2) and its access points; the
        // W30/W32 wired pass collects every ethernet device (type 1)
        QString wifiDevice;
        m_wired.clear();
        const QVariant devs = dbusGet(nm, nmPath, nm,
                                      QStringLiteral("Devices"));
        for (const QString &p : dbusPaths(devs)) {
            const QVariantMap dm = dbusGetAll(nm, p,
                QStringLiteral("org.freedesktop.NetworkManager.Device"));
            const uint devType = dm.value(QStringLiteral("DeviceType")).toUInt();
            if (devType == 2u && wifiDevice.isEmpty()) {
                wifiDevice = p;
                continue;
            }
            if (devType == 1u) {
                // NM device states: 100 activated, 30 disconnected,
                // 20 unavailable (no carrier), 10 unmanaged.
                const uint st = dm.value(QStringLiteral("State")).toUInt();
                const QVariantMap wm = dbusGetAll(nm, p,
                    QStringLiteral("org.freedesktop.NetworkManager.Device.Wired"));
                m_wired.append(QVariantMap{
                    {QStringLiteral("iface"),
                     dm.value(QStringLiteral("Interface")).toString()},
                    {QStringLiteral("plugged"),
                     wm.value(QStringLiteral("Carrier")).toBool()},
                    {QStringLiteral("active"), st == 100u},
                });
            }
        }
        m_hasWifi = !wifiDevice.isEmpty();
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

    // W32.1 — join a WPA network: the secret rides the settings map of the
    // agent-less AddAndActivateConnection call (the review: a password
    // sheet is the missing half of the pane). Open networks keep
    // connectTo — the sheet only opens for secure ones.
    Q_INVOKABLE void connectWithSecret(const QString &ssid,
                                       const QString &secret)
    {
        const QString ap = apFor(ssid);
        const QString dev = wifiDevicePath();
        if (ap.isEmpty() || dev.isEmpty())
            return;
        const QVariantMap settings{
            {QStringLiteral("802-11-wireless"),
             QVariantMap{{QStringLiteral("ssid"), ssid.toUtf8()}}},
            {QStringLiteral("802-11-wireless-security"),
             QVariantMap{{QStringLiteral("key-mgmt"),
                          QStringLiteral("wpa-psk")},
                         {QStringLiteral("psk"), secret}}},
        };
        dbusAsync(QStringLiteral("org.freedesktop.NetworkManager"),
                  QStringLiteral("/org/freedesktop/NetworkManager"),
                  QStringLiteral("org.freedesktop.NetworkManager"),
                  QStringLiteral("AddAndActivateConnection"),
                  QVariantList{settings, QDBusObjectPath(dev),
                               QDBusObjectPath(ap)});
        QTimer::singleShot(2500, this, &NetworkBackend::refresh);
        QTimer::singleShot(6000, this, &NetworkBackend::refresh);
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
    // W30/W32 — the wired-first pane
    QVariantList m_wired;
    bool m_hasWifi = false;
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
        connect(p, &QProcess::readyReadStandardOutput, this,
                [this, p, logPath]() {
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

// ── Bluetooth (T13 D22 / W32.3) ──────────────────────────────────────────
//
// bluetoothctl is the backend (bluez is in the ISO): show for the adapter
// state, devices Paired + info per device for the list, one-shot
// connect/disconnect/pair/trust/remove commands, scan on/off for
// discovery. A VM with no Bluetooth adapter reads "noadapter" — the pane
// says so instead of rendering an empty list.

class BluetoothBackend : public QObject {
    Q_OBJECT
    // [{mac, name, connected, trusted}]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY changed)
    // "noctl" (bluetoothctl missing) | "noadapter" | "off" | "idle"
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(bool scanning READ scanning NOTIFY changed)
public:
    explicit BluetoothBackend(QObject *parent = nullptr) : QObject(parent)
    {
        connect(&m_scanProc, &QProcess::readyReadStandardOutput, this,
                &BluetoothBackend::readScanOutput);
        refresh();
    }

    ~BluetoothBackend() override
    {
        if (m_scanProc.state() != QProcess::NotRunning)
            m_scanProc.kill();
    }

    QVariantList devices() const { return m_devices; }
    QString state() const { return m_state; }
    bool scanning() const { return m_scanning; }

    Q_INVOKABLE void refresh()
    {
        m_devices.clear();
        const QString bt = QStandardPaths::findExecutable(
            QStringLiteral("bluetoothctl"));
        if (bt.isEmpty()) {
            m_state = QStringLiteral("noctl");
            emit changed();
            return;
        }
        QProcess show;
        show.start(bt, {QStringLiteral("show")});
        show.waitForFinished(2500);
        const QString out = QString::fromUtf8(show.readAllStandardOutput());
        if (out.contains(QStringLiteral("No default controller"))) {
            m_state = QStringLiteral("noadapter");
            emit changed();
            return;
        }
        if (!out.contains(QStringLiteral("Powered: yes"))) {
            m_state = QStringLiteral("off");
            emit changed();
            return;
        }
        QProcess list;
        list.start(bt, {QStringLiteral("devices"), QStringLiteral("Paired")});
        list.waitForFinished(2500);
        const QStringList lines = QString::fromUtf8(
            list.readAllStandardOutput()).split(QLatin1Char('\n'));
        for (const QString &raw : lines) {
            const QString line = raw.trimmed();
            if (!line.startsWith(QStringLiteral("Device ")))
                continue;
            // "Device 5C:EB:A6:AA:BB:CC Sony WH-1000XM4"
            const QString mac = line.section(QLatin1Char(' '), 1, 1);
            QVariantMap dev{
                {QStringLiteral("mac"), mac},
                {QStringLiteral("name"), line.section(QLatin1Char(' '), 2)},
                {QStringLiteral("connected"), false},
                {QStringLiteral("trusted"), false},
            };
            QProcess info;
            info.start(bt, {QStringLiteral("info"), mac});
            info.waitForFinished(2500);
            const QString iout = QString::fromUtf8(
                info.readAllStandardOutput());
            dev[QStringLiteral("connected")] =
                iout.contains(QStringLiteral("Connected: yes"));
            dev[QStringLiteral("trusted")] =
                iout.contains(QStringLiteral("Trusted: yes"));
            m_devices.append(dev);
        }
        m_state = QStringLiteral("idle");
        emit changed();
    }

    Q_INVOKABLE void startScan()
    {
        if (m_scanning)
            return;
        const QString bt = QStandardPaths::findExecutable(
            QStringLiteral("bluetoothctl"));
        if (bt.isEmpty() || m_scanProc.state() != QProcess::NotRunning)
            return;
        m_scanProc.start(bt, {QStringLiteral("scan"),
                              QStringLiteral("on")});
        m_scanning = true;
        emit changed();
        // eight seconds of discovery, then stop and re-read the list —
        // the found devices ride the paired list (new devices appear
        // untrusted) and the scan process is killed.
        QTimer::singleShot(8000, this, [this, bt]() {
            if (m_scanProc.state() != QProcess::NotRunning)
                m_scanProc.kill();
            QProcess::startDetached(bt, {QStringLiteral("scan"),
                                         QStringLiteral("off")});
            m_scanning = false;
            refresh();
        });
    }

    Q_INVOKABLE void connectDevice(const QString &mac)
    {
        runBt({QStringLiteral("connect"), mac});
        QTimer::singleShot(2500, this, &BluetoothBackend::refresh);
    }

    Q_INVOKABLE void disconnectDevice(const QString &mac)
    {
        runBt({QStringLiteral("disconnect"), mac});
        QTimer::singleShot(1500, this, &BluetoothBackend::refresh);
    }

    Q_INVOKABLE void pairDevice(const QString &mac)
    {
        runBt({QStringLiteral("pair"), mac});
        runBt({QStringLiteral("trust"), mac});
        QTimer::singleShot(2500, this, &BluetoothBackend::refresh);
    }

    Q_INVOKABLE void forgetDevice(const QString &mac)
    {
        runBt({QStringLiteral("remove"), mac});
        QTimer::singleShot(1500, this, &BluetoothBackend::refresh);
    }

signals:
    void changed();

private:
    void runBt(const QStringList &args)
    {
        const QString bt = QStandardPaths::findExecutable(
            QStringLiteral("bluetoothctl"));
        if (!bt.isEmpty())
            QProcess::startDetached(bt, args);
    }

    void readScanOutput()
    {
        // "NEW    Device 5C:EB:A6:AA:BB:CC Sony WH-1000XM4" — append any
        // device the scan discovers that is not listed yet.
        const QString chunk = QString::fromUtf8(
            m_scanProc.readAllStandardOutput());
        const QStringList lines = chunk.split(QLatin1Char('\n'));
        for (const QString &raw : lines) {
            const QString line = raw.trimmed();
            if (!line.startsWith(QStringLiteral("NEW"))
                    && !line.startsWith(QStringLiteral("CHG")))
                continue;
            if (!line.contains(QStringLiteral("Device ")))
                continue;
            const QString after =
                line.section(QStringLiteral("Device "), 1);
            const QString mac = after.section(QLatin1Char(' '), 0, 0);
            const QString name = after.section(QLatin1Char(' '), 1);
            bool known = false;
            for (const QVariant &v : m_devices) {
                if (v.toMap().value(QStringLiteral("mac")) == mac) {
                    known = true;
                    break;
                }
            }
            if (known || mac.isEmpty())
                continue;
            m_devices.append(QVariantMap{
                {QStringLiteral("mac"), mac},
                {QStringLiteral("name"),
                 name.isEmpty() ? mac : name},
                {QStringLiteral("connected"), false},
                {QStringLiteral("trusted"), false},
            });
            emit changed();
        }
    }

    QVariantList m_devices;
    QString m_state = QStringLiteral("noctl");
    bool m_scanning = false;
    QProcess m_scanProc;
};

// ── Drivers & Firmware (T13 D23 / W33) ───────────────────────────────────
//
// The real inventory behind the pane that used to be the static
// BUILT-IN placeholder list (the W37 poster child): lspci -k with the
// "Kernel driver in use" line per device, lsusb, lsblk, lpstat print
// queues, simple-scan presence, fwupdmgr updates (best-effort, 4 s cap,
// async). Power & charging rides Util (it already reads
// /sys/class/power_supply); the pane renders "AC power" honestly on VMs
// without a battery.

class DriversBackend : public QObject {
    Q_OBJECT
    // [{name, driver, category}] — category ∈ Graphics/Network/Audio/
    // Storage/USB/Other
    Q_PROPERTY(QVariantList pciDevices READ pciDevices NOTIFY changed)
    Q_PROPERTY(QVariantList usbDevices READ usbDevices NOTIFY changed)
    // [{name, size}]
    Q_PROPERTY(QVariantList storageDevices READ storageDevices NOTIFY changed)
    // [{name, state}]
    Q_PROPERTY(QVariantList printers READ printers NOTIFY changed)
    // "ready" (simple-scan installed) | "missing"
    Q_PROPERTY(QString scanState READ scanState NOTIFY changed)
    // "checking" | "uptodate" | "N updates" | "unavailable"
    Q_PROPERTY(QString firmwareState READ firmwareState NOTIFY changed)
public:
    explicit DriversBackend(QObject *parent = nullptr) : QObject(parent)
    {
        refresh();
        refreshFirmware();
    }

    QVariantList pciDevices() const { return m_pci; }
    QVariantList usbDevices() const { return m_usb; }
    QVariantList storageDevices() const { return m_storage; }
    QVariantList printers() const { return m_printers; }
    QString scanState() const { return m_scanState; }
    QString firmwareState() const { return m_firmware; }

    Q_INVOKABLE void refresh()
    {
        m_pci.clear();
        m_usb.clear();
        m_storage.clear();
        m_printers.clear();

        // lspci -k — device lines start at column 0, the per-device
        // "Kernel driver in use:" line is tab-indented.
        const QString lspci = QStandardPaths::findExecutable(
            QStringLiteral("lspci"));
        if (!lspci.isEmpty()) {
            QProcess p;
            p.start(lspci, {QStringLiteral("-k")});
            p.waitForFinished(3000);
            QString name;
            QString category = QStringLiteral("Other");
            QString driver;
            const auto flush = [&]() {
                if (!name.isEmpty()) {
                    m_pci.append(QVariantMap{
                        {QStringLiteral("name"), name},
                        {QStringLiteral("driver"), driver},
                        {QStringLiteral("category"), category}});
                }
                name.clear();
                driver.clear();
            };
            const QStringList lines = QString::fromUtf8(
                p.readAllStandardOutput()).split(QLatin1Char('\n'));
            for (const QString &raw : lines) {
                const QString line = raw.trimmed();
                if (line.isEmpty())
                    continue;
                if (!raw.startsWith(QLatin1Char('\t'))) {
                    flush();
                    name = line.section(QStringLiteral(": "), 1);
                    const QString cls = line.section(QLatin1Char(' '), 1)
                                             .section(QStringLiteral(": "),
                                                      0, 0);
                    if (cls.contains(QStringLiteral("VGA"))
                            || cls.contains(QStringLiteral("3D"))
                            || cls.contains(QStringLiteral("Display")))
                        category = QStringLiteral("Graphics");
                    else if (cls.contains(QStringLiteral("Network"))
                             || cls.contains(QStringLiteral("Ethernet"))
                             || cls.contains(QStringLiteral("Wireless")))
                        category = QStringLiteral("Network");
                    else if (cls.contains(QStringLiteral("Audio")))
                        category = QStringLiteral("Audio");
                    else if (cls.contains(QStringLiteral("SATA"))
                             || cls.contains(QStringLiteral("NVMe"))
                             || cls.contains(QStringLiteral("Storage"))
                             || cls.contains(QStringLiteral("IDE")))
                        category = QStringLiteral("Storage");
                    else if (cls.contains(QStringLiteral("USB")))
                        category = QStringLiteral("USB");
                    else
                        category = QStringLiteral("Other");
                } else if (line.startsWith(
                               QStringLiteral("Kernel driver in use:"))) {
                    driver = line.section(QStringLiteral(": "), 1);
                }
            }
            flush();
        }

        const QString lsusb = QStandardPaths::findExecutable(
            QStringLiteral("lsusb"));
        if (!lsusb.isEmpty()) {
            QProcess p;
            p.start(lsusb, {});
            p.waitForFinished(3000);
            const QStringList lines = QString::fromUtf8(
                p.readAllStandardOutput()).split(QLatin1Char('\n'));
            int count = 0;
            for (const QString &line : lines) {
                if (!line.contains(QStringLiteral(" ID ")))
                    continue;
                if (count++ >= 8)
                    break;
                const QString rest =
                    line.section(QStringLiteral(" ID "), 1);
                m_usb.append(QVariantMap{
                    {QStringLiteral("name"),
                     rest.section(QLatin1Char(' '), 1).isEmpty()
                         ? rest : rest.section(QLatin1Char(' '), 1)},
                });
            }
        }

        const QString lsblk = QStandardPaths::findExecutable(
            QStringLiteral("lsblk"));
        if (!lsblk.isEmpty()) {
            QProcess p;
            p.start(lsblk, {QStringLiteral("-d"), QStringLiteral("-n"),
                            QStringLiteral("-o"),
                            QStringLiteral("NAME,SIZE,TYPE")});
            p.waitForFinished(3000);
            const QStringList lines = QString::fromUtf8(
                p.readAllStandardOutput()).split(QLatin1Char('\n'));
            for (const QString &line : lines) {
                const QStringList cols =
                    line.trimmed().split(QRegularExpression(QStringLiteral(
                        "\\s+")), Qt::SkipEmptyParts);
                if (cols.size() < 3 || cols[2] != QStringLiteral("disk"))
                    continue;
                m_storage.append(QVariantMap{
                    {QStringLiteral("name"), cols[0]},
                    {QStringLiteral("size"), cols[1]},
                });
            }
        }

        const QString lpstat = QStandardPaths::findExecutable(
            QStringLiteral("lpstat"));
        if (!lpstat.isEmpty()) {
            QProcess p;
            p.start(lpstat, {QStringLiteral("-p")});
            p.waitForFinished(3000);
            const QStringList lines = QString::fromUtf8(
                p.readAllStandardOutput()).split(QLatin1Char('\n'));
            for (const QString &line : lines) {
                if (!line.startsWith(QStringLiteral("printer ")))
                    continue;
                // "printer Foo is idle.  enabled since …"
                m_printers.append(QVariantMap{
                    {QStringLiteral("name"),
                     line.section(QLatin1Char(' '), 1, 1)},
                    {QStringLiteral("state"),
                     line.section(QLatin1Char(' '), 3, -1)
                         .section(QLatin1Char('.'), 0, 0).trimmed()},
                });
            }
        }

        m_scanState = QStandardPaths::findExecutable(
                          QStringLiteral("simple-scan")).isEmpty()
                          ? QStringLiteral("missing")
                          : QStringLiteral("ready");
        emit changed();
    }

    // Best-effort and offline-safe: a runner VM with no network still
    // renders the section ("No updates available" or "unavailable").
    Q_INVOKABLE void refreshFirmware()
    {
        const QString fwupdmgr = QStandardPaths::findExecutable(
            QStringLiteral("fwupdmgr"));
        if (fwupdmgr.isEmpty()) {
            m_firmware = QStringLiteral("unavailable");
            emit changed();
            return;
        }
        m_firmware = QStringLiteral("checking");
        emit changed();
        QProcess *p = new QProcess(this);
        p->setProcessChannelMode(QProcess::MergedChannels);
        connect(p, &QProcess::finished, this,
                [this, p](int, QProcess::ExitStatus) {
            const QString out = QString::fromUtf8(p->readAll());
            p->deleteLater();
            if (out.contains(QStringLiteral("No updates available"))
                    || out.contains(QStringLiteral("No devices with updates")))
                m_firmware = QStringLiteral("uptodate");
            else if (out.contains(QStringLiteral("update available"))
                     || out.contains(QStringLiteral("Updates available"))) {
                const int n = out.count(QStringLiteral("update available"))
                              + out.count(QStringLiteral("Updates available"));
                m_firmware = QStringLiteral("%1 updates")
                                 .arg(qMax(n, 1));
            } else
                m_firmware = QStringLiteral("unavailable");
            emit changed();
        });
        p->start(fwupdmgr, {QStringLiteral("get-updates")});
        QTimer::singleShot(4000, p, [p]() {
            if (p->state() == QProcess::Running)
                p->kill();
        });
    }

    // W33.2 — test page through CUPS (cups itself is in the ISO; the
    // cups-pdf Print-to-PDF printer waits for an archive reintroduction
    // — recorded in TASKS.md D16).
    Q_INVOKABLE void printTestPage(const QString &queue)
    {
        const QString lp = QStandardPaths::findExecutable(
            QStringLiteral("lp"));
        const QString page = QStringLiteral(
            "/usr/share/cups/data/default-testpage.pdf");
        if (!lp.isEmpty() && QFile::exists(page))
            QProcess::startDetached(lp, {QStringLiteral("-d"), queue,
                                         page});
    }

    Q_INVOKABLE void openCups()
    {
        QProcess::startDetached(QStringLiteral("xdg-open"),
                                {QStringLiteral("http://localhost:631")});
    }

    Q_INVOKABLE void launchScanner()
    {
        QProcess::startDetached(QStringLiteral("simple-scan"), {});
    }

signals:
    void changed();

private:
    QVariantList m_pci;
    QVariantList m_usb;
    QVariantList m_storage;
    QVariantList m_printers;
    QString m_scanState = QStringLiteral("missing");
    QString m_firmware = QStringLiteral("unavailable");
};
