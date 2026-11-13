#include "util.h"

#include <QColor>
#include <QDebug>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPainter>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
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
            QVariantMap{{"name", "Music"}, {"icon", "aegis-music"},
                        {"cmd", "aegis-music"}},               // Tier A — first-party Music (M3)
            QVariantMap{{"name", "Calculator"}, {"icon", "aegis-calculator"},
                        {"cmd", "aegis-calculator"}},          // Tier A — first-party Calculator (M3)
            QVariantMap{{"name", "Editor"}, {"icon", "aegis-editor"},
                        {"cmd", "aegis-editor"}},              // Tier A — first-party Editor (M3)
            QVariantMap{{"name", "Monitor"}, {"icon", "aegis-monitor"},
                        {"cmd", "aegis-monitor"}},             // Tier A — first-party Monitor (M3)
            QVariantMap{{"name", "Store"}, {"icon", "aegis-store"},
                        {"cmd", "aegis-store"}},               // Tier A — the apt-backed store (T14)
            QVariantMap{{"name", "Settings"}, {"icon", "aegis-settings"},
                        {"cmd", "aegis-settings"}},             // Tier A — first-party Settings (aegis-apps)
            QVariantMap{{"name", "Trash"}, {"icon", "aegis-trash"},
                        // W26 — Files gained --path: the Trash tile opens
                        // the trash view, not Home
                        {"cmd", "aegis-files --path trash:///"}},  // Tier A
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
    //
    // T13 D29 — the QSettings write did not land in the v0.6.52 boot run
    // (the shell state flipped — the CC sheet re-rendered light — but
    // ~/.config/kdeglobals still read AegisDark 2.5 s after the click).
    // The precise QSettings failure mode is unproven (no local Qt to
    // repro); the replacement is a deterministic QSaveFile rewrite that
    // touches ONLY the ColorScheme line inside [General] and preserves
    // everything else byte-for-byte (the W18 comment pins ride along).
    // The theme state file gives the boot harness the same file-based
    // verdict pattern the presentation toggle already uses.
    const QString home = QStandardPaths::writableLocation(
                             QStandardPaths::HomeLocation);
    const QString kg = home + QStringLiteral("/.config/kdeglobals");
    QDir(home).mkpath(QStringLiteral(".config"));
    const QString schemeLine = QStringLiteral("ColorScheme=")
        + (dark ? QStringLiteral("AegisDark")
                : QStringLiteral("AegisLight"));
    QFile in(kg);
    QString body;
    if (in.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream ts(&in);
        body = ts.readAll();
        in.close();
    }
    if (body.isEmpty())
        body = QStringLiteral("[General]\n");
    if (body.contains(QRegularExpression(
            QStringLiteral("^ColorScheme=.*$"), QRegularExpression::MultilineOption))) {
        body.replace(QRegularExpression(
            QStringLiteral("^ColorScheme=.*$"), QRegularExpression::MultilineOption),
            schemeLine);
    } else if (body.contains(QRegularExpression(
            QStringLiteral("^\\[General\\]\\s*$"), QRegularExpression::MultilineOption))) {
        body.replace(QRegularExpression(
            QStringLiteral("^\\[General\\]\\s*$"), QRegularExpression::MultilineOption),
            QStringLiteral("[General]\n") + schemeLine);
    } else {
        body += QStringLiteral("\n[General]\n") + schemeLine + QStringLiteral("\n");
    }
    QSaveFile out(kg);
    if (out.open(QIODevice::WriteOnly | QIODevice::Text)) {
        out.write(body.toUtf8());
        if (!out.commit())
            qWarning() << "setDarkMode: kdeglobals commit failed:" << out.errorString();
    } else {
        qWarning() << "setDarkMode: kdeglobals open failed:" << out.errorString();
    }
    // file-based verdict for the boot gate (and honest diagnostics when
    // the config write fails — the state file separates "shell applied"
    // from "kdeglobals written" in the artifacts)
    const QString stateDir = QStandardPaths::writableLocation(
                                 QStandardPaths::GenericStateLocation)
                             + QStringLiteral("/aegis-shell/aegis");
    QDir().mkpath(stateDir);
    QSaveFile st(stateDir + QStringLiteral("/theme"));
    if (st.open(QIODevice::WriteOnly | QIODevice::Text)) {
        st.write((dark ? QStringLiteral("dark\n") : QStringLiteral("light\n"))
                     .toUtf8());
        st.commit();
    }
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
    // running dots — session-level tracking (W20: the real backing store
    // is the aegis-windowwatch KWin script; this launch-recorded list
    // stays as the instant-feedback path until the window maps)
    if (!m_runningCmds.contains(command)) {
        m_runningCmds.append(command);
        emit runningCmdsChanged();
    }
    // W24 — every launch is diagnosable: the process output goes to
    // ~/.local/state/aegis/launch/<head>.log (rotated to the last 50
    // lines) with a timestamped line per launch. A VM failure is then
    // one file the user can send (the v0.6.36 review's §3 ask).
    const QString head = QFileInfo(command.section(QLatin1Char(' '), 0, 0))
                             .fileName();
    const QString stateDir = QStandardPaths::writableLocation(
                                 QStandardPaths::StateLocation)
                             + QStringLiteral("/aegis/launch");
    QDir().mkpath(stateDir);
    const QString logPath = stateDir + QStringLiteral("/%1.log").arg(head);
    QFile logFile(logPath);
    if (logFile.size() > 8192) {
        QStringList keep;
        if (logFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QStringList lines =
                QString::fromUtf8(logFile.readAll())
                    .split(QLatin1Char('\n'));
            keep = lines.mid(lines.size() > 50 ? lines.size() - 50 : 0);
            logFile.close();
        }
        if (logFile.open(QIODevice::WriteOnly | QIODevice::Truncate
                         | QIODevice::Text)) {
            logFile.write(keep.join(QLatin1Char('\n')).toUtf8());
            logFile.close();
        }
    }
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Append
                     | QIODevice::Text)) {
        logFile.write((QStringLiteral("--- ")
                       + QDateTime::currentDateTime().toString(Qt::ISODate)
                       + QLatin1Char('\n') + command + QLatin1Char('\n'))
                          .toUtf8());
        logFile.close();
    }
    QProcess::startDetached(QStringLiteral("/bin/sh"),
                            {QStringLiteral("-c"),
                             command + QStringLiteral(" >> ") + logPath
                                 + QStringLiteral(" 2>&1")});
}

void Util::windowListChanged(const QString &json)
{
    // W20 — the aegis-windowwatch KWin script is the source of truth for
    // the active-workspace window state. ONE JSON STRING argument: KWin's
    // callDBus marshals JS numbers as DBus DOUBLE and an int slot param
    // never matched (the v0.6.37 run shipped exactly that silent break —
    // the script pushed, the island never hid). m_windowIds feeds the
    // dock running-dot reads (isRunning); the count/flag feed the
    // island's auto-hide predicate. runningCmdsChanged fires alongside
    // windowTrackingChanged because every isRunning() binding just
    // potentially changed with the new ids.
    // T13 D20 (W27) — the payload grew allIds (managed windows incl.
    // MINIMIZED — the dock dots and activateOrLaunch must see them) and
    // active (the active window's resourceClass). m_windowIds switches
    // to allIds; a pre-D20 script payload falls back to the visible ids.
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) {
        m_lastJson = json;   // T13 D5 — even a bad payload is evidence
        emit windowTrackingChanged();
        emit runningCmdsChanged();
        return;
    }
    const QJsonObject o = doc.object();
    m_workspaceWindows = o.value(QStringLiteral("count")).toInt();
    m_anyWindowFull = o.value(QStringLiteral("anyFull")).toBool();
    m_activeClass = o.value(QStringLiteral("active")).toString();
    m_windowIds.clear();
    QJsonArray all = o.value(QStringLiteral("allIds")).toArray();
    if (all.isEmpty())
        all = o.value(QStringLiteral("ids")).toArray();
    for (const QJsonValue &v : all)
        m_windowIds.append(v.toString());
    // T13 D5 — keep the raw payload for the harness dump
    m_lastJson = json;
    emit windowTrackingChanged();
    emit runningCmdsChanged();
}

void Util::activateOrLaunch(const QString &cmd, const QString &resolved)
{
    // W27 — the reviewer's ruling: "if a window with that app-id exists
    // -> workspace.activeWindow = win / unminimize via the KWin script;
    // else launch". The shell CANNOT call into a script (no inbound
    // DBus, no configChanged for scripts on 6.6 — verified against
    // scripting.cpp), so when the head is a tracked class the request
    // rides kwinrc [Script-aegis-windowwatch] and nudgeKWinConfig()
    // makes KWin reparse it (QSettings alone is INVISIBLE to
    // KConfigWatcher — D30), and the script's 150 ms poll unminimizes +
    // activates. The seq makes a repeated request re-fire even when the
    // class is unchanged.
    // ARGUMENTED commands NEVER activate: Trash's cmd is
    // "aegis-files --path trash:///" — head-matching it would focus the
    // plain Files window instead of opening the trash. Only a bare cmd
    // (head == cmd) is a re-focus candidate.
    const QString head = cmd.section(QLatin1Char(' '), 0, 0);
    if (!head.isEmpty() && head == cmd.trimmed()
            && m_windowIds.contains(head)) {
        QSettings kwinRc(QStandardPaths::writableLocation(
                             QStandardPaths::ConfigLocation)
                             + QStringLiteral("/kwinrc"),
                         QSettings::IniFormat);
        kwinRc.beginGroup(QStringLiteral("Script-aegis-windowwatch"));
        const int seq = kwinRc.value(QStringLiteral("ActivateSeq"), 0)
                            .toInt() + 1;
        kwinRc.setValue(QStringLiteral("ActivateSeq"), seq);
        kwinRc.setValue(QStringLiteral("ActivateRequest"), head);
        kwinRc.endGroup();
        kwinRc.sync();
        nudgeKWinConfig();
        return;
    }
    // the resolved-Exec parameter MUST NOT be named launch: it would
    // shadow Util::launch and the call would compile as a call on a
    // QString (the exact error the v0.6.51 Shell CI caught).
    launch(resolved.isEmpty() ? cmd : resolved);
}

void Util::quitApp(const QString &head)
{
    // W36.2 — the dock tile menu's Quit. pkill -f on the head is coarse
    // but real: it matches the binary path of the /opt debs and the
    // bare-name Tier A apps alike; the windowwatch recount lands the
    // state change within a poll tick.
    if (head.isEmpty())
        return;
    QProcess::startDetached(QStringLiteral("pkill"),
                            {QStringLiteral("-f"), head});
    QTimer::singleShot(1200, this, [this]() {
        emit runningCmdsChanged();
        emit windowTrackingChanged();
    });
}

void Util::emptyTrash()
{
    // W36.2 — the freedesktop Trash under the home; empty both halves
    // (files + info). No confirm sheet in this pass: the menu item
    // itself is the user's explicit intent.
    const QString home = QStandardPaths::writableLocation(
        QStandardPaths::HomeLocation);
    const QString base = home + QStringLiteral("/.local/share/Trash/");
    for (const QString &sub :
         {QStringLiteral("files"), QStringLiteral("info")}) {
        QDir trash(base + sub);
        const QFileInfoList entries = trash.entryInfoList(
            QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot);
        for (const QFileInfo &fi : entries) {
            if (fi.isDir())
                QDir(fi.absoluteFilePath()).removeRecursively();
            else
                QFile::remove(fi.absoluteFilePath());
        }
    }
}

void Util::publishDockTileMap(const QString &tileMap)
{
    // W21 — the transport into the aegis-dockzoom effect: it cannot
    // callDBus, so the tile centers ride kwinrc. KConfigWatcher fires
    // the effect's configChanged on this write; the map is read from
    // the effect's own group (Effect-<plugin id>). D25 — the value is
    // the quote-free head=cx,cy list; JSON quotes would be escaped to
    // \" by QSettings IniFormat and KConfig flags every one of them as
    // an invalid escape (twice per session in the guest journal).
    QSettings kwinRc(QStandardPaths::writableLocation(
                         QStandardPaths::ConfigLocation)
                         + QStringLiteral("/kwinrc"),
                     QSettings::IniFormat);
    kwinRc.beginGroup(QStringLiteral("Effect-aegis-dockzoom"));
    kwinRc.setValue(QStringLiteral("TileMap"), tileMap);
    kwinRc.endGroup();
    kwinRc.sync();
    nudgeKWinConfig();
}

void Util::nudgeKWinConfig()
{
    // T13 D30 — KConfigWatcher is NOT a filesystem watcher: it subscribes
    // to the org.kde.kconfig.notify ConfigChanged DBus signal (verified
    // against kconfigwatcher.cpp, v6.13.0) which ONLY KConfig-based
    // writers emit (kconfig.cpp:506 — the signal rides KConfig::sync).
    // QSettings never sends it, so every QSettings write to kwinrc was
    // invisible to KWin: the windowwatch script's 150 ms poll kept
    // reading the load-time ActivateSeq (the v0.6.53 run disproved the
    // transport live: the shell wrote the request, the script stayed at
    // 0) and the dockzoom effect never re-read TileMap either. KWin
    // exposes the reparse directly: org.kde.KWin.reloadConfig on the
    // session bus runs Workspace::slotReconfigure -> kwinApp()->config()
    // ->reparseConfiguration() (dbusinterface.cpp:48, workspace.cpp:979
    // and 996, verified against the 6.6.0 tag) — exactly the shared
    // config Script::config() and effect readConfig read. Fire-and-
    // forget async: a missed call costs nothing, the next write nudges
    // again. NOTE: the reparse does NOT emit the effects' notify-based
    // configChanged — the dockzoom effect re-reads its map per
    // animation (readMap() in growFromTile/shrinkIntoTile).
    QDBusMessage call = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.kde.KWin"), QStringLiteral("reloadConfig"));
    QDBusConnection::sessionBus().asyncCall(call);
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
            // D10/v0.6.46 run — the desktop Exec may QUOTE the path (CoreX:
            // Exec="/opt/CoreX Terminal/corex-terminal" %U). The v0.6.49
            // run proved the v0.6.47 strip was STILL broken: taking
            // section(' ',0,0) first splits INSIDE the quoted segment
            // (`"/opt/CoreX`), the closing quote lies beyond the token,
            // and the basename read `"CoreX` — the entry stayed
            // unmatched, the tile lost the W24 launch field again, and
            // the bare head FATALed twice more. The quoted parse must
            // run on the FULL Exec value: from the opening quote to the
            // closing quote, spaces inside included.
            const QString execRaw =
                entry.value(QStringLiteral("cmd")).toString();
            QString execToken;
            if (execRaw.startsWith(QLatin1Char('"'))) {
                const int close = execRaw.indexOf(QLatin1Char('"'), 1);
                execToken = (close > 0) ? execRaw.mid(1, close - 1)
                                        : execRaw.mid(1);
            } else {
                execToken = execRaw.section(QLatin1Char(' '), 0, 0);
                if (execToken.contains(QLatin1Char('\\')))
                    execToken.remove(QLatin1Char('\\'));
            }
            const QString quotedHead =
                QFileInfo(execToken).fileName();
            const QString tryExec = entry.value(QStringLiteral("tryExec")).toString();
            if (quotedHead == cmdHead || execHead == cmdHead
                || tryExec == cmdHead) {
                // W24/D10 — the launch line: prefer the bare head when it
                // resolves on PATH. All three Tier B debs install a
                // /usr/bin symlink (CoreX via update-alternatives), and
                // the PATH binary is the canonical entry point — no
                // quoting or desktop field codes to re-parse. The entry
                // Exec stays the fallback when nothing is on PATH — the
                // W24 rule (the entry is the source of truth) is intact.
                const QString onPath = QStandardPaths::findExecutable(cmdHead);
                return QVariantMap{
                    {QStringLiteral("icon"),
                     entry.value(QStringLiteral("icon")).toString()},
                    {QStringLiteral("name"),
                     entry.value(QStringLiteral("name")).toString()},
                    {QStringLiteral("exec"),
                     onPath.isEmpty()
                         ? entry.value(QStringLiteral("cmd")).toString()
                         : cmdHead},
                };
            }
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
            // W24 — the dock launches the entry's FULL Exec= (the bare
            // head is not on PATH for the /opt debs), but the slot's cmd
            // stays the bare head: isRunning/the tile tracking match by
            // the head and the window resourceClass, not by the launch
            // line.
            const QString exec = entry.value(QStringLiteral("exec")).toString();
            if (!exec.isEmpty()) {
                // W25 — ALL Tier B deb apps ride the launch guard. The
                // chrome-sandbox file check cannot detect electron from
                // the resolved binary: the debs ship a /usr/bin wrapper
                // SCRIPT whose chrome-sandbox lives in the /opt app dir
                // (v0.6.42 proved the check never engaged). The guard is
                // a transparent exec outside VM mode; in a VM it adds
                // --disable-gpu --no-sandbox (the sandbox FATAL).
                slot.insert(QStringLiteral("launch"),
                            QStringLiteral("aegis-electron-launch ") + exec);
            }
            out.append(slot);
            continue;
        }
        // No entry — installed only if the binary is on PATH (W9: nothing on
        // the shelf that isn't installed).
        if (!QStandardPaths::findExecutable(head).isEmpty())
            out.append(slot);
    }
    // W22 — user-added web shortcuts append after the last first-party
    // slot, BEFORE Trash (the review's order). Nothing is ever added
    // unless the user explicitly asked for it (the default dock carries
    // zero web entries — W9 holds).
    const QVariantList web = webShortcuts();
    if (!web.isEmpty()) {
        int trashIdx = -1;
        for (int i = 0; i < out.size(); ++i) {
            const QVariantMap m = out.at(i).toMap();
            if (m.value(QStringLiteral("name")).toString()
                == QLatin1String("Trash")) {
                trashIdx = i;
                break;
            }
        }
        for (int i = web.size() - 1; i >= 0; --i)
            out.insert(trashIdx < 0 ? out.size() : trashIdx, web.at(i));
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
        else if (key == QLatin1String("StartupWMClass"))
            app.insert(QStringLiteral("wmclass"), value);
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
    QStringList seenWmClasses;
    for (const QString &dirPath : dirs) {
        QDir dir(dirPath);
        const auto files = dir.entryList({QStringLiteral("*.desktop")},
                                         QDir::Files);
        for (const QString &f : files) {
            // W22 — user web shortcuts already ride the pinned section
            // (dockApps appends them before Trash); never double them here.
            if (f.startsWith(QLatin1String("aegis-web-")))
                continue;
            QVariantMap app = parseDesktopFile(dir.filePath(f));
            if (app.isEmpty())
                continue;
            if (app.value(QStringLiteral("type")).toString() != QLatin1String("Application"))
                continue;
            const QString cmd = app.value(QStringLiteral("cmd")).toString();
            const QString head = cmd.section(QLatin1Char(' '), 0, 0);
            const QString wm = app.value(QStringLiteral("wmclass")).toString();
            // W22 — dedupe by Exec basename AND StartupWMClass: the
            // aegis-browser deb ships two identical entries
            // (aegis-browser.desktop + org.aegisbrowser.Aegis.desktop);
            // same-exec twins were already caught by seenExecs, but two
            // entries whose Exec spellings differ (an /opt path vs the
            // wrapper) must also collapse to one tile.
            const bool wmSeen = !wm.isEmpty() && seenWmClasses.contains(wm);
            if (head.isEmpty() || seenExecs.contains(head) || wmSeen)
                continue;
            // record the exec even for hidden entries so a NoDisplay
            // override wins over the stock file (see dir order above)
            seenExecs << head;
            if (!wm.isEmpty())
                seenWmClasses << wm;
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

// ── W22 — web shortcuts (strictly opt-in dock entries) ────────────────

static QString webShortcutId(const QString &normalizedUrl)
{
    return QString::fromLatin1(QCryptographicHash::hash(
                                   normalizedUrl.toUtf8(),
                                   QCryptographicHash::Md5)
                                   .toHex()
                                   .left(12));
}

static QString webIconDir()
{
    const QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    const QString base = dataHome.isEmpty()
        ? (qEnvironmentVariable("HOME") + QStringLiteral("/.local/share"))
        : dataHome;
    return base + QStringLiteral("/aegis/webicons");
}

// The fallback tile: rounded square in the site's theme color (or a
// stable hash hue), white site initial in Montserrat. A network failure
// must still land a working, good-looking shortcut.
static QImage makeLetterTile(const QString &letter, const QColor &color)
{
    QImage img(96, 96, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);
    p.setBrush(color.isValid() ? color : QColor(0x3E, 0x8B, 0xFF));
    p.drawRoundedRect(4, 4, 88, 88, 22, 22);
    QFont f;
    f.setFamily(QStringLiteral("Montserrat"));
    f.setPixelSize(44);
    f.setWeight(QFont::DemiBold);
    p.setFont(f);
    p.setPen(QColor(255, 255, 255, 235));
    p.drawText(img.rect(), Qt::AlignCenter, letter.toUpper());
    p.end();
    return img;
}

QVariantList Util::webShortcuts() const
{
    QVariantList out;
    const QString appsDir = webIconDir().section(QLatin1Char('/'), 0, -2)
                                + QStringLiteral("/../applications");
    QDir dir(QDir::cleanPath(appsDir));
    const auto files = dir.entryList({QStringLiteral("aegis-web-*.desktop")},
                                     QDir::Files, QDir::Name);
    for (const QString &f : files) {
        const QVariantMap entry =
            parseDesktopFile(dir.filePath(f));
        if (entry.isEmpty()
            || entry.value(QStringLiteral("type")).toString()
                   != QLatin1String("Application"))
            continue;
        // id from the file name: aegis-web-<id>.desktop
        const QString id = f.mid(10, f.size() - 10
                                       - QStringLiteral(".desktop").size());
        out.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("name"),
             entry.value(QStringLiteral("name")).toString()},
            {QStringLiteral("icon"),
             entry.value(QStringLiteral("icon")).toString()},
            {QStringLiteral("cmd"),
             entry.value(QStringLiteral("cmd")).toString()},
            {QStringLiteral("web"), true},
        });
    }
    return out;
}

void Util::removeWebShortcut(const QString &id)
{
    if (id.isEmpty() || id.contains(QLatin1Char('/')))
        return;   // ids are hex — never trust a path component
    QFile::remove(webIconDir() + QStringLiteral("/%1.png").arg(id));
    const QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    const QString base = dataHome.isEmpty()
        ? (qEnvironmentVariable("HOME") + QStringLiteral("/.local/share"))
        : dataHome;
    QFile::remove(base + QStringLiteral("/applications/aegis-web-%1.desktop")
                          .arg(id));
    emit dockAppsChanged();
}

void Util::addWebShortcut(const QString &rawUrl)
{
    QString url = rawUrl.trimmed();
    if (url.isEmpty()) {
        emit webShortcutAdded(false, QString());
        return;
    }
    if (!url.contains(QLatin1String("://")))
        url = QStringLiteral("https://") + url;
    const QUrl u(url);
    if (!u.isValid() || u.host().isEmpty()) {
        emit webShortcutAdded(false, QString());
        return;
    }
    const QString normalized = u.toString();
    const QString id = webShortcutId(normalized);
    const QString host = u.host();

    if (!m_nam)
        m_nam = new QNetworkAccessManager(this);
    QNetworkRequest req(u);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setTransferTimeout(10000);
    QNetworkReply *pageReply = m_nam->get(req);
    connect(pageReply, &QNetworkReply::finished, this,
            [this, pageReply, normalized, id, host]() {
                pageReply->deleteLater();
                QString title = host;
                QString iconUrl;
                QColor themeColor;
                const QByteArray body =
                    pageReply->error() == QNetworkReply::NoError
                        ? pageReply->readAll()
                        : QByteArray();
                if (!body.isEmpty()) {
                    const QString html =
                        QString::fromUtf8(body.left(300 * 1024));
                    QRegularExpression titleRe(
                        QStringLiteral("<title[^>]*>([^<]{1,120})"),
                        QRegularExpression::CaseInsensitiveOption);
                    const auto tm = titleRe.match(html);
                    if (tm.hasMatch())
                        title = tm.captured(1).simplified();
                    // theme-color for the fallback tile
                    QRegularExpression colorRe(
                        QStringLiteral("name=[\"']theme-color[\"'][^>]*"
                                       "content=[\"']([^\"']+)[\"']"),
                        QRegularExpression::CaseInsensitiveOption);
                    const auto cm = colorRe.match(html);
                    if (cm.hasMatch())
                        themeColor = QColor(cm.captured(1).trimmed());
                    // icon links — apple-touch-icon first, then any icon
                    QRegularExpression linkRe(
                        QStringLiteral("<link[^>]+>"),
                        QRegularExpression::CaseInsensitiveOption);
                    QString fallbackIcon;
                    auto it = linkRe.globalMatch(html);
                    while (it.hasNext()) {
                        const QString tag = it.next().captured(0);
                        QRegularExpression relRe(
                            QStringLiteral("rel=[\"']([^\"']*)[\"']"),
                            QRegularExpression::CaseInsensitiveOption);
                        QRegularExpression hrefRe(
                            QStringLiteral("href=[\"']([^\"']+)[\"']"),
                            QRegularExpression::CaseInsensitiveOption);
                        const auto rel = relRe.match(tag);
                        const auto href = hrefRe.match(tag);
                        if (!rel.hasMatch() || !href.hasMatch())
                            continue;
                        const QString r =
                            rel.captured(1).toLower();
                        if (r.contains(QLatin1String("apple-touch-icon"))) {
                            iconUrl = href.captured(1);
                            break;
                        }
                        if (r.contains(QLatin1String("icon"))
                            && fallbackIcon.isEmpty())
                            fallbackIcon = href.captured(1);
                    }
                    if (iconUrl.isEmpty())
                        iconUrl = fallbackIcon;
                }
                if (title.isEmpty())
                    title = host;

                const QString iconPath =
                    webIconDir() + QStringLiteral("/%1.png").arg(id);
                QDir().mkpath(webIconDir());
                bool iconDone = false;
                if (!iconUrl.isEmpty()) {
                    const QUrl resolved =
                        QUrl(iconUrl).isRelative()
                            ? QUrl(normalized).resolved(QUrl(iconUrl))
                            : QUrl(iconUrl);
                    if (resolved.isValid()) {
                        QNetworkRequest ireq(resolved);
                        ireq.setAttribute(
                            QNetworkRequest::RedirectPolicyAttribute,
                            QNetworkRequest::NoLessSafeRedirectPolicy);
                        ireq.setTransferTimeout(10000);
                        QNetworkReply *iconReply = m_nam->get(ireq);
                        connect(iconReply, &QNetworkReply::finished, this,
                                [this, iconReply, iconPath, title,
                                 normalized, id, host, themeColor]() {
                                    iconReply->deleteLater();
                                    QImage icon;
                                    if (iconReply->error()
                                        == QNetworkReply::NoError) {
                                        const QByteArray data =
                                            iconReply->readAll();
                                        icon.loadFromData(data);
                                    }
                                    if (icon.isNull()) {
                                        // favicon.ico missing or
                                        // undecodable — the letter tile
                                        // keeps the entry presentable
                                        icon = makeLetterTile(
                                            host.left(1), themeColor);
                                    }
                                    icon.save(iconPath, "PNG");
                                    writeWebDesktop(normalized, id, title,
                                                    iconPath);
                                });
                        iconDone = true;
                    }
                }
                if (!iconDone) {
                    makeLetterTile(host.left(1), themeColor)
                        .save(iconPath, "PNG");
                    writeWebDesktop(normalized, id, title, iconPath);
                }
            });
}

void Util::writeWebDesktop(const QString &url, const QString &id,
                           const QString &title, const QString &iconPath)
{
    const QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    const QString base = dataHome.isEmpty()
        ? (qEnvironmentVariable("HOME") + QStringLiteral("/.local/share"))
        : dataHome;
    QDir().mkpath(base + QStringLiteral("/applications"));
    QFile f(base + QStringLiteral("/applications/aegis-web-%1.desktop")
                .arg(id));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit webShortcutAdded(false, title);
        return;
    }
    // multi-arg form: the title can legitimately contain percent signs
    const QString desktop = QStringLiteral(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=%1\n"
        "Exec=xdg-open %2\n"
        "Icon=%3\n"
        "StartupWMClass=aegis-web-%4\n"
        "Terminal=false\n"
        "X-Aegis-WebShortcut=true\n")
                                .arg(title, url, iconPath, id);
    f.write(desktop.toUtf8());
    emit webShortcutAdded(true, title);
    emit dockAppsChanged();
}
