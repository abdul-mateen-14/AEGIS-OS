#include "util.h"

#include <QColor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>
#include <cmath>
#include <pwd.h>
#include <unistd.h>

// Default session config — mirrors shell/packaging/config.json.
//
// W9 ruling: the dock carries INSTALLED APPS ONLY. The six web tiles
// (Gmail/YouTube/GitHub/X/WhatsApp/ChatGPT — xdg-open shortcuts, not apps)
// are gone; a Launcher "Web" folder may revisit them later.
//
// W8 ruling: Tier B slots (separate products installed from .debs) wear
// their own marks. "resolve": true tells dockApps() to re-dress the slot
// from the installed .desktop entry (Icon= and Name=) and to drop the tile
// when the product is not installed — never a generic stand-in glyph.
// Tier A first-party slots (Files/Terminal/Settings/Trash) keep the plate-9
// squircles and are passed through untouched.
QVariantMap Util::defaultConfig() const
{
    return QVariantMap{
        {QStringLiteral("wallpaper"),
         QStringLiteral("/usr/share/wallpapers/aegis/aurora-ink.jpg")},
        {QStringLiteral("apps"), QVariantList{
            QVariantMap{{"name", "Files"}, {"icon", "aegis-files"},
                        {"cmd", "aegis-files"}},               // Tier A — first-party Files (aegis-apps)
            QVariantMap{{"name", "Terminal"}, {"icon", "aegis-terminal"},
                        {"cmd", "konsole"}},                    // Tier A
            QVariantMap{{"name", "AEGIS Browser"}, {"icon", "aegis-browser"},
                        {"cmd", "aegis-browser-stable"},
                        {"resolve", true}},                     // Tier B — entry: aegis-browser / org.aegisbrowser.Aegis
            QVariantMap{{"name", "OS"}, {"icon", "os-private-chat"},
                        {"cmd", "os-private-chat"},
                        {"resolve", true}},                     // Tier B — the messenger deb's own entry/mark
            QVariantMap{{"name", "CoreX"}, {"icon", "corex-terminal"},
                        {"cmd", "corex-terminal"},
                        {"resolve", true}},                     // Tier B — the CoreX deb's own entry/mark
            QVariantMap{{"type", "separator"}},
            QVariantMap{{"name", "Settings"}, {"icon", "aegis-settings"},
                        {"cmd", "aegis-settings"}},             // Tier A — first-party Settings (aegis-apps)
            QVariantMap{{"name", "Trash"}, {"icon", "aegis-trash"},
                        {"cmd", "aegis-files"}},               // Tier A — Files sidebar → Trash
        }},
    };
}

Util::Util(QObject *parent)
    : QObject(parent)
{
    m_config = readConfig(QStringLiteral("/usr/share/aegis/shell/config.json"));
    loadPrefs();
    loadAccent();
    if (m_wallpaper.isEmpty())
        m_wallpaper = m_config.value(QStringLiteral("wallpaper")).toString();

    // identity for the lock screen avatar ring
    if (struct passwd *pw = getpwuid(geteuid())) {
        const QString gecos = QString::fromUtf8(pw->pw_gecos)
                                  .split(QLatin1Char(',')).value(0).trimmed();
        m_userName = gecos.isEmpty() ? QString::fromUtf8(pw->pw_name) : gecos;
        const QStringList words = m_userName.split(QLatin1Char(' '),
                                                   Qt::SkipEmptyParts);
        if (words.size() >= 2)
            m_userInitials = words.first().left(1).toUpper()
                             + words.last().left(1).toUpper();
        else if (!m_userName.isEmpty())
            m_userInitials = m_userName.left(1).toUpper();
    }

    refreshBattery();
    m_batteryTimer.setInterval(30000);
    connect(&m_batteryTimer, &QTimer::timeout, this, &Util::refreshBattery);
    m_batteryTimer.start();

    refreshLinkStates();
    m_linkTimer.setInterval(10000);
    connect(&m_linkTimer, &QTimer::timeout, this, [this] {
        refreshLinkStates();
        refreshBattery();
    });
    m_linkTimer.start();
}

void Util::loadPrefs()
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR",
                                                 QStringLiteral("/tmp"));
    QFile file(runtime + QStringLiteral("/aegis/prefs.json"));
    if (file.open(QIODevice::ReadOnly)) {
        const auto doc = QJsonDocument::fromJson(file.readAll());
        m_darkMode = doc.object().value(QStringLiteral("darkMode")).toBool(true);
        m_wallpaper = doc.object().value(QStringLiteral("wallpaper")).toString();
    }
}

void Util::savePrefs() const
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR",
                                                 QStringLiteral("/tmp"));
    QDir(runtime).mkpath(QStringLiteral("aegis"));
    QFile file(runtime + QStringLiteral("/aegis/prefs.json"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        QJsonObject prefs{
            {QStringLiteral("darkMode"), m_darkMode}};
        if (!m_wallpaper.isEmpty())
            prefs.insert(QStringLiteral("wallpaper"), m_wallpaper);
        file.write(QJsonDocument(prefs).toJson(QJsonDocument::Compact));
    }
}

void Util::setDarkMode(bool dark)
{
    if (m_darkMode == dark)
        return;
    m_darkMode = dark;
    savePrefs();
    // M4 — light theme parity: the KDE-facing surfaces (Konsole, the
    // installer's widget dialogs) read the scheme from kdeglobals, so the
    // rung swap lands there too. AegisDark / AegisLight ship in
    // /usr/share/color-schemes; GTK follows via aegis-gtk-sync.
    const QString kg = QStandardPaths::writableLocation(
                           QStandardPaths::HomeLocation)
                       + QStringLiteral("/.config/kdeglobals");
    QSettings scheme(kg, QSettings::IniFormat);
    scheme.setValue(QStringLiteral("General/ColorScheme"),
                    dark ? QStringLiteral("AegisDark")
                         : QStringLiteral("AegisLight"));
    scheme.sync();
    emit darkModeChanged();
}

// ── W5 — one-token accent ────────────────────────────────────────────────
// Persisted at $XDG_CONFIG_HOME/aegis/tokens.conf (one key, per the
// instructions). App processes also forward the write to org.aegis.Shell so
// the running shell recolors live; the shell's own instance never forwards.

void Util::loadAccent()
{
    const QString base = QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation);
    if (base.isEmpty())
        return;
    const QSettings tokens(base + QStringLiteral("/aegis/tokens.conf"),
                           QSettings::IniFormat);
    const QString saved = tokens.value(QStringLiteral("accent")).toString();
    if (!saved.isEmpty()) {
        const QColor c(saved);
        if (c.isValid())
            m_accent = c.name(QColor::HexRgb);
    }
}

void Util::saveAccent() const
{
    const QString base = QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation);
    if (base.isEmpty())
        return;
    QDir(base).mkpath(QStringLiteral("aegis"));
    QSettings tokens(base + QStringLiteral("/aegis/tokens.conf"),
                     QSettings::IniFormat);
    tokens.setValue(QStringLiteral("accent"), m_accent);
    tokens.sync();
}

void Util::setAccent(const QString &accent)
{
    const QColor c(accent);
    const QString hex = c.isValid()
                            ? c.name(QColor::HexRgb)
                            : QStringLiteral("#3E8BFF");
    if (m_accent == hex)
        return;
    m_accent = hex;
    saveAccent();
    emit accentChanged();
    forwardToShell(QStringLiteral("setAccent"), hex);
}

// ── W4 — live wallpaper ────────────────────────────────────────────────

void Util::setWallpaper(const QString &path)
{
    if (path.isEmpty() || !QFile::exists(path))
        return;
    if (m_wallpaper == path)
        return;
    m_wallpaper = path;
    savePrefs();
    emit wallpaperChanged();
    forwardToShell(QStringLiteral("setWallpaper"), path);
}

void Util::forwardToShell(const QString &method, const QString &value) const
{
    // Only app processes forward: the shell owns org.aegis.Shell and is
    // already applying the change locally. Fire-and-forget — the shell may
    // be gone (dev runs); the local write already persisted.
    if (m_ownsDBus)
        return;
    const QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.aegis.Shell"),
        QStringLiteral("/org/aegis/Shell"),
        QString(), method);
    msg.setArguments({value});
    bus.asyncCall(msg);
}

void Util::setCcOpen(bool open)
{
    if (m_ccOpen == open)
        return;
    m_ccOpen = open;
    emit ccOpenChanged();
}

void Util::setLauncherOpen(bool open)
{
    if (m_launcherOpen == open)
        return;
    m_launcherOpen = open;
    emit launcherOpenChanged();
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
    // running dots — session-level tracking (M3: real KWin window tracking)
    if (!m_runningCmds.contains(command)) {
        m_runningCmds.append(command);
        emit runningCmdsChanged();
    }
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

void Util::lock()
{
    if (!m_locked) {
        m_locked = true;
        emit lockedChanged();
    }
}

void Util::unlock(const QString &user, const QString &password)
{
    auto *proc = new QProcess(this);
    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError) {
        proc->deleteLater();
        emit unlockResult(false);
    });
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int code, QProcess::ExitStatus status) {
        const QString out = QString::fromUtf8(proc->readAllStandardOutput()).trimmed();
        proc->deleteLater();
        const bool ok = status == QProcess::NormalExit && code == 0
                        && out == QStringLiteral("OK");
        if (ok && m_locked) {
            m_locked = false;
            emit lockedChanged();
        }
        emit unlockResult(ok);
    });
    proc->start(QStringLiteral("/usr/bin/aegis-auth"), {user});
    proc->write(password.toUtf8() + '\n');
    proc->closeWriteChannel();
}

void Util::refreshBattery()
{
    QDir powerSupply(QStringLiteral("/sys/class/power_supply"));
    int percent = -1;
    bool onBattery = false;
    bool chargingNow = false;
    int minutes = -1;

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
            else if (s == QStringLiteral("Charging"))
                chargingNow = true;
        }
        // time-to-full estimate: (energy_full − energy_now) / power_now
        const auto val = [&powerSupply, &bat](const QString &key) -> qint64 {
            QFile f(powerSupply.filePath(bat) + QLatin1Char('/') + key);
            if (f.open(QIODevice::ReadOnly))
                return f.readAll().trimmed().toLongLong();
            return 0;
        };
        const qint64 energyFull = val(QStringLiteral("energy_full"));
        const qint64 energyNow = val(QStringLiteral("energy_now"));
        const qint64 powerNow = val(QStringLiteral("power_now"));
        if (chargingNow && powerNow > 0 && energyFull > energyNow)
            minutes = int(qreal(energyFull - energyNow) / qreal(powerNow) * 60.0);
    }

    const bool wasCharging = m_charging;
    if (percent != m_batteryPercent || onBattery != m_onBattery
        || chargingNow != m_charging) {
        m_batteryPercent = percent;
        m_onBattery = onBattery;
        m_charging = chargingNow;
        m_minutesToFull = minutes;
        emit batteryChanged();
    }
    // AC event → island charging pulse (main.cpp forwards to ActivityService)
    if (chargingNow != wasCharging)
        emit chargingEvent(chargingNow, percent < 0 ? 82 : percent, minutes);
}

void Util::refreshLinkStates()
{
    // Wi-Fi — NetworkManager radio state
    const QString nmcli = QStandardPaths::findExecutable(QStringLiteral("nmcli"));
    if (!nmcli.isEmpty()) {
        QProcess p;
        p.start(nmcli, {QStringLiteral("radio"), QStringLiteral("wifi")});
        p.waitForFinished(1500);
        const QString out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
        m_wifiEnabled = out.contains(QStringLiteral("enabled"),
                                     Qt::CaseInsensitive);
    } else {
        m_wifiEnabled = false;
    }

    // Bluetooth — first rfkill "bluetooth" device, soft/hard blocked?
    m_bluetoothEnabled = false;
    QDir rfkill(QStringLiteral("/sys/class/rfkill"));
    const auto devs = rfkill.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &dev : devs) {
        QFile type(rfkill.filePath(dev) + QStringLiteral("/type"));
        if (!type.open(QIODevice::ReadOnly))
            continue;
        if (QString::fromUtf8(type.readAll()).trimmed()
                != QStringLiteral("bluetooth"))
            continue;
        QFile state(rfkill.filePath(dev) + QStringLiteral("/state"));
        if (state.open(QIODevice::ReadOnly))
            m_bluetoothEnabled = QString::fromUtf8(state.readAll()).trimmed()
                                 == QStringLiteral("1");
        break;
    }

    // Volume — PipeWire / WirePlumber
    const QString wpctl = QStandardPaths::findExecutable(QStringLiteral("wpctl"));
    if (!wpctl.isEmpty()) {
        QProcess p;
        p.start(wpctl, {QStringLiteral("get-volume"),
                        QStringLiteral("@DEFAULT_AUDIO_SINK@")});
        p.waitForFinished(1500);
        const QString out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
        // "Volume: 0.65" optionally + " [MUTED]"
        m_muted = out.contains(QStringLiteral("MUTED"));
        const int colon = out.indexOf(QLatin1Char(':'));
        if (colon >= 0) {
            bool ok = false;
            const qreal v = out.mid(colon + 1).remove(QStringLiteral("[MUTED]"))
                                .trimmed().toDouble(&ok);
            if (ok)
                m_volume = qBound(0.0, v, 1.5);
        }
    }

    // Brightness — sysfs backlight (ratio 0..1)
    const QString dev = backlightDevice();
    if (!dev.isEmpty()) {
        QFile maxFile(dev + QStringLiteral("/max_brightness"));
        QFile curFile(dev + QStringLiteral("/brightness"));
        if (maxFile.open(QIODevice::ReadOnly) && curFile.open(QIODevice::ReadOnly)) {
            const qreal maxV = maxFile.readAll().trimmed().toDouble();
            const qreal curV = curFile.readAll().trimmed().toDouble();
            if (maxV > 0.0)
                m_brightness = qBound(0.05, curV / maxV, 1.0);
        }
    }

    emit linkStatesChanged();
}

QString Util::backlightDevice() const
{
    QDir bl(QStringLiteral("/sys/class/backlight"));
    const auto devs = bl.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    return devs.isEmpty() ? QString() : bl.filePath(devs.first());
}

void Util::setWifiEnabled(bool on)
{
    QProcess::startDetached(QStringLiteral("nmcli"),
                            {QStringLiteral("radio"), QStringLiteral("wifi"),
                             on ? QStringLiteral("on") : QStringLiteral("off")});
    QTimer::singleShot(1200, this, &Util::refreshLinkStates);
}

void Util::setBluetoothEnabled(bool on)
{
    const QString bt = QStandardPaths::findExecutable(QStringLiteral("bluetoothctl"));
    if (!bt.isEmpty())
        QProcess::startDetached(bt, {QStringLiteral("power"),
                                     on ? QStringLiteral("on")
                                        : QStringLiteral("off")});
    QTimer::singleShot(1200, this, &Util::refreshLinkStates);
}

void Util::setMuted(bool on)
{
    QProcess::startDetached(QStringLiteral("wpctl"),
                            {QStringLiteral("set-mute"),
                             QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                             on ? QStringLiteral("1") : QStringLiteral("0")});
    QTimer::singleShot(300, this, &Util::refreshLinkStates);
}

void Util::setVolume(qreal v)
{
    v = qBound(0.0, v, 1.5);
    QProcess::startDetached(QStringLiteral("wpctl"),
                            {QStringLiteral("set-volume"),
                             QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                             QString::number(v, 'f', 2)});
    m_volume = v;
    emit linkStatesChanged();
}

void Util::setBrightness(qreal v)
{
    v = qBound(0.05, v, 1.0);
    const QString dev = backlightDevice();
    bool written = false;
    if (!dev.isEmpty()) {
        QFile maxFile(dev + QStringLiteral("/max_brightness"));
        if (maxFile.open(QIODevice::ReadOnly)) {
            const qreal maxV = maxFile.readAll().trimmed().toDouble();
            if (maxV > 0.0) {
                QFile cur(dev + QStringLiteral("/brightness"));
                if (cur.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                    cur.write(QString::number(qRound(v * maxV)).toUtf8());
                    written = true;
                }
            }
        }
    }
    if (!written) {
        // sysfs denied (no video group) — fall back to brightnessctl
        const QString bctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (!bctl.isEmpty())
            QProcess::startDetached(bctl, {QStringLiteral("set"),
                                           QString::number(qRound(v * 100))
                                               + QStringLiteral("%")});
    }
    m_brightness = v;
    emit linkStatesChanged();
}

// ── Launcher inventory ────────────────────────────────────────────────

static QVariantMap parseDesktopFile(const QString &path);

// W8 — resolve a dock slot against the INSTALLED .desktop entries. Walks the
// same XDG precedence as allApps() (user → local → system) and matches the
// slot's command head against Exec's first token (basename — Exec may point
// into /opt with a path, and wrappers like %f/%u follow later) and TryExec.
// First non-hidden Application entry wins; {} when the product is absent.
static QVariantMap findInstalledEntry(const QString &cmdHead)
{
    if (cmdHead.isEmpty())
        return {};
    const QString home = qEnvironmentVariable("HOME");
    QStringList dirs;
    if (!home.isEmpty())
        dirs << (home + QStringLiteral("/.local/share/applications"));
    dirs << QStringLiteral("/usr/local/share/applications")
         << QStringLiteral("/usr/share/applications");

    for (const QString &dirPath : dirs) {
        const auto files = QDir(dirPath).entryList({QStringLiteral("*.desktop")},
                                                   QDir::Files);
        for (const QString &f : files) {
            const QVariantMap entry = parseDesktopFile(dirPath + QLatin1Char('/') + f);
            if (entry.isEmpty()
                || entry.value(QStringLiteral("type")).toString()
                       != QLatin1String("Application"))
                continue;
            if (entry.value(QStringLiteral("nodisplay")).toBool()
                || entry.value(QStringLiteral("hidden")).toBool())
                continue;
            const QString execHead = QFileInfo(
                entry.value(QStringLiteral("cmd")).toString()
                    .section(QLatin1Char(' '), 0, 0)).fileName();
            const QString tryExec = entry.value(QStringLiteral("tryExec")).toString();
            if (execHead == cmdHead || tryExec == cmdHead)
                return QVariantMap{
                    {QStringLiteral("icon"),
                     entry.value(QStringLiteral("icon")).toString()},
                    {QStringLiteral("name"),
                     entry.value(QStringLiteral("name")).toString()},
                };
        }
    }
    return {};
}

QVariantList Util::dockApps() const
{
    QVariantList out;
    const auto pinned = m_config.value(QStringLiteral("apps")).toList();
    for (const QVariant &v : pinned) {
        QVariantMap slot = v.toMap();
        if (slot.value(QStringLiteral("type")).toString()
            == QLatin1String("separator")) {
            out.append(v);
            continue;
        }
        if (!slot.value(QStringLiteral("resolve")).toBool()) {
            out.append(slot);                     // Tier A — untouched
            continue;
        }
        // Tier B — the installed entry is the source of truth (W8): its
        // Icon= and Name= dress the tile, same resolution the launcher and
        // KWin's alt-tab use. The config values are only the designer's
        // fallback when the deb's entry is missing or blank.
        const QString cmd = slot.value(QStringLiteral("cmd")).toString();
        const QString head = QFileInfo(cmd.section(QLatin1Char(' '), 0, 0))
                                 .fileName();
        const QVariantMap entry = findInstalledEntry(head);
        if (!entry.isEmpty()) {
            const QString icon = entry.value(QStringLiteral("icon")).toString();
            const QString name = entry.value(QStringLiteral("name")).toString();
            if (!icon.isEmpty())
                slot.insert(QStringLiteral("icon"), icon);
            if (!name.isEmpty())
                slot.insert(QStringLiteral("name"), name);
            out.append(slot);
            continue;
        }
        // No entry — installed only if the binary is on PATH (W9: nothing on
        // the shelf that isn't installed).
        if (!QStandardPaths::findExecutable(head).isEmpty())
            out.append(slot);
    }
    return out;
}

static QVariantMap parseDesktopFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QVariantMap app;
    QString line;
    bool inEntry = false;
    QTextStream stream(&file);
    while (stream.readLineInto(&line)) {
        const QString t = line.trimmed();
        if (t.isEmpty() || t.startsWith(QLatin1Char('#')))
            continue;
        if (t.startsWith(QLatin1Char('['))) {
            if (inEntry) // left the first group — stop
                break;
            inEntry = t.compare(QStringLiteral("[Desktop Entry]"),
                                Qt::CaseInsensitive) == 0;
            continue;
        }
        if (!inEntry || !t.contains(QLatin1Char('=')))
            continue;
        const int eq = t.indexOf(QLatin1Char('='));
        QString key = t.left(eq).trimmed();
        // skip locale keys (Name[xx]) — we surface the default Name
        if (key.contains(QLatin1Char('[')))
            continue;
        const QString value = t.mid(eq + 1).trimmed();
        if (key == QLatin1String("Type"))
            app.insert(QStringLiteral("type"), value);
        else if (key == QLatin1String("Name"))
            app.insert(QStringLiteral("name"), value);
        else if (key == QLatin1String("Exec"))
            app.insert(QStringLiteral("cmd"), value);
        else if (key == QLatin1String("Icon"))
            app.insert(QStringLiteral("icon"), value);
        else if (key == QLatin1String("TryExec"))
            app.insert(QStringLiteral("tryExec"), value);
        else if (key == QLatin1String("NoDisplay"))
            app.insert(QStringLiteral("nodisplay"), value == QLatin1String("true"));
        else if (key == QLatin1String("Hidden"))
            app.insert(QStringLiteral("hidden"), value == QLatin1String("true"));
    }
    return app;
}

QVariantList Util::allApps() const
{
    QVariantList out;
    QStringList seenExecs;

    // 1. pinned config apps (dock order, first-party slots) — first.
    // dockApps() (not the raw config) so the Launcher wears the same W8
    // entry-resolved marks as the dock.
    const auto pinned = dockApps();
    for (const QVariant &v : pinned) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("type")).toString() == QLatin1String("separator"))
            continue;
        const QString cmd = m.value(QStringLiteral("cmd")).toString();
        const QString head = cmd.section(QLatin1Char(' '), 0, 0);
        seenExecs << head;
        out.append(QVariantMap{
            {QStringLiteral("name"), m.value(QStringLiteral("name")).toString()},
            {QStringLiteral("icon"), m.value(QStringLiteral("icon")).toString()},
            {QStringLiteral("cmd"), cmd},
        });
    }

    // 2. installed applications — .desktop scan, alphabetical.
    // XDG data-home precedence: the user's own entries win, then
    // /usr/local/share (distro overrides — e.g. the rebranded "Install
    // Aegis OS" calamares entry), then /usr/share. An entry hidden or
    // removed in a higher-precedence dir also hides its lower-precedence
    // twin (that's why hidden execs are recorded too).
    const QString home = qEnvironmentVariable("HOME");
    QStringList dirs;
    if (!home.isEmpty())
        dirs << (home + QStringLiteral("/.local/share/applications"));
    dirs << QStringLiteral("/usr/local/share/applications")
         << QStringLiteral("/usr/share/applications");

    QList<QVariantMap> discovered;
    for (const QString &dirPath : dirs) {
        QDir dir(dirPath);
        const auto files = dir.entryList({QStringLiteral("*.desktop")},
                                         QDir::Files);
        for (const QString &f : files) {
            QVariantMap app = parseDesktopFile(dir.filePath(f));
            if (app.isEmpty())
                continue;
            if (app.value(QStringLiteral("type")).toString() != QLatin1String("Application"))
                continue;
            const QString cmd = app.value(QStringLiteral("cmd")).toString();
            const QString head = cmd.section(QLatin1Char(' '), 0, 0);
            if (head.isEmpty() || seenExecs.contains(head))
                continue;
            // record the exec even for hidden entries so a NoDisplay
            // override wins over the stock file (see dir order above)
            seenExecs << head;
            if (app.value(QStringLiteral("nodisplay")).toBool()
                || app.value(QStringLiteral("hidden")).toBool())
                continue;
            discovered.append(QVariantMap{
                {QStringLiteral("name"), app.value(QStringLiteral("name")).toString()},
                {QStringLiteral("icon"), app.value(QStringLiteral("icon")).toString()},
                {QStringLiteral("cmd"), cmd},
            });
        }
    }
    std::sort(discovered.begin(), discovered.end(),
              [](const QVariantMap &a, const QVariantMap &b) {
                  return a.value(QStringLiteral("name")).toString().compare(
                             b.value(QStringLiteral("name")).toString(),
                             Qt::CaseInsensitive)
                     < 0;
              });
    for (const QVariantMap &m : discovered)
        out.append(m);
    return out;
}
