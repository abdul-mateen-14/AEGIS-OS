#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>

class QNetworkAccessManager;   // W22 — web-shortcut fetch pipeline

// Small C++ helpers the QML surfaces need: config loading, app launching,
// battery status, hardware controls (brightness, volume, radio states),
// the app inventory for the Launcher, and the PAM-verified unlock bridge
// for the lock screen. Deliberately pragmatic — shell C++ stays light.
class Util : public QObject {
    Q_OBJECT
    // T11-D5 — the session API's bus name. Without this Q_CLASSINFO Qt
    // exports the invokables under the generated local.aegis.Util
    // interface, so every busctl --user call org.aegis.Shell ... launch
    // failed with "No such interface" (observed on every boot test since
    // the automation surface was added; the geometric click fallback hid
    // it until the four M3 app captures arrived). With it, Qt publishes
    // the invokables under org.aegis.Shell as the callers expect.
    Q_CLASSINFO("D-Bus Interface", "org.aegis.Shell")
    Q_PROPERTY(QVariantMap config READ config CONSTANT)
    // W8/W9 — the dock model: config.json slots with every Tier B slot
    // ("resolve": true) re-marked from its installed .desktop entry (Icon=,
    // Name=) and dropped entirely when the product is not installed. Tier A
    // first-party slots pass through untouched. W22 — user-added web
    // shortcuts append before Trash; the list recomputes on demand.
    Q_PROPERTY(QVariantList dockApps READ dockApps NOTIFY dockAppsChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool onBattery READ onBattery NOTIFY batteryChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY batteryChanged)
    // preferences + session state
    Q_PROPERTY(bool darkMode READ darkMode WRITE setDarkMode NOTIFY darkModeChanged)
    // W5 — the one-token accent (six presets, default #3E8BFF). Persisted at
    // $XDG_CONFIG_HOME/aegis/tokens.conf; Tokens.qml binds it so every surface
    // recolors together. App processes write it here AND forward over DBus
    // (see setOwnsDBus) so the shell recolors live.
    Q_PROPERTY(QString accent READ accent WRITE setAccent NOTIFY accentChanged)
    // W4 — live wallpaper. Desktop.qml binds this; setWallpaper() persists to
    // the session prefs and forwards to the shell process over DBus.
    Q_PROPERTY(QString wallpaper READ wallpaper NOTIFY wallpaperChanged)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
    Q_PROPERTY(bool ccOpen READ ccOpen WRITE setCcOpen NOTIFY ccOpenChanged)
    Q_PROPERTY(bool launcherOpen READ launcherOpen WRITE setLauncherOpen NOTIFY launcherOpenChanged)
    // hardware states (Control Center tiles, panel status cluster)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY linkStatesChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled NOTIFY linkStatesChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY linkStatesChanged)
    Q_PROPERTY(qreal volume READ volume NOTIFY linkStatesChanged)
    Q_PROPERTY(qreal brightness READ brightness NOTIFY linkStatesChanged)
    // lock screen identity
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString userInitials READ userInitials CONSTANT)

public:
    explicit Util(QObject *parent = nullptr);

    QVariantMap config() const { return m_config; }
    QVariantList dockApps() const;
    int batteryPercent() const { return m_batteryPercent; }
    bool onBattery() const { return m_onBattery; }
    bool charging() const { return m_charging; }

    bool darkMode() const { return m_darkMode; }
    // Q_INVOKABLE: QML calls this as a method (Appearance cards, Control
    // Center dark toggle) — plain Q_PROPERTY WRITE accessors are not
    // guaranteed to be method-callable from QML.
    Q_INVOKABLE void setDarkMode(bool dark);
    QString accent() const { return m_accent; }
    Q_INVOKABLE void setAccent(const QString &accent);
    QString wallpaper() const { return m_wallpaper; }
    Q_INVOKABLE void setWallpaper(const QString &path);
    // shell main.cpp marks the process that owns org.aegis.Shell on the
    // session bus. App processes (aegis-apps) leave it false: their accent/
    // wallpaper writes also go out as DBus calls to org.aegis.Shell so the
    // running shell applies them; the shell's own copy must NOT re-forward
    // (the DBus delivery would bounce back and loop).
    void setOwnsDBus(bool owns) { m_ownsDBus = owns; }
    bool locked() const { return m_locked; }
    bool ccOpen() const { return m_ccOpen; }
    void setCcOpen(bool open);
    bool launcherOpen() const { return m_launcherOpen; }
    void setLauncherOpen(bool open);

    bool wifiEnabled() const { return m_wifiEnabled; }
    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    bool muted() const { return m_muted; }
    qreal volume() const { return m_volume; }
    qreal brightness() const { return m_brightness; }

    QString userName() const { return m_userName; }
    QString userInitials() const { return m_userInitials; }

    // Reads a JSON file; falls back to the embedded defaults when missing
    // (dev runs outside the ISO).
    Q_INVOKABLE QVariantMap readConfig(const QString &path) const;

    // Runs a command detached ("dolphin", "xdg-open https://...").
    Q_INVOKABLE void launch(const QString &command);

    // ── Running apps (dock running dots) ─────────────────────────────
    // Session-level: launch() records every command it starts. W20 (T12)
    // adds the REAL backing store: the aegis-windowwatch KWin script
    // pushes the active-workspace window list over DBus and isRunning()
    // answers from both — so foreign-launched apps (CoreX opened from
    // Files) light their dot too. The QML contract stays the same.
    Q_PROPERTY(QStringList runningCmds READ runningCmds NOTIFY runningCmdsChanged)
    QStringList runningCmds() const { return m_runningCmds; }
    Q_INVOKABLE bool isRunning(const QString &cmd) const
    {
        return m_runningCmds.contains(cmd) || m_windowIds.contains(cmd);
    }
    // W20 — the island auto-hide predicate source: count of trackable
    // normal windows on the ACTIVE workspace + any maximized/fullscreen
    // flag (exposed as one property pair so the predicate can be tuned
    // later; the ruling's hide predicate is workspaceWindows > 0).
    Q_PROPERTY(int workspaceWindows READ workspaceWindows NOTIFY windowTrackingChanged)
    Q_PROPERTY(bool anyWindowFull READ anyWindowFull NOTIFY windowTrackingChanged)
    int workspaceWindows() const { return m_workspaceWindows; }
    bool anyWindowFull() const { return m_anyWindowFull; }
    // T13 D20 (W27) — the resourceClass of the currently ACTIVE window
    // ("" when none or a shell surface). The harness's restore assert
    // reads it from the payload dump.
    Q_PROPERTY(QString activeWindowClass READ activeWindowClass NOTIFY windowTrackingChanged)
    QString activeWindowClass() const { return m_activeClass; }

    // W27 — a dock click must bring an existing window back, not spawn
    // a second instance: when the command head matches a tracked window
    // (minimized included), the request rides kwinrc
    // [Script-aegis-windowwatch] ActivateRequest/ActivateSeq (scripts
    // have no inbound DBus or configChanged on 6.6 — the 150 ms poll in
    // the windowwatch script picks it up); otherwise the command
    // launches normally (with the launch field's resolved Exec).
    Q_INVOKABLE void activateOrLaunch(const QString &cmd,
                                      const QString &launch = QString());

    // W36.2 — the dock tile menu's actions. quitApp kills the app's
    // process group by head (the same key the tracking uses); emptyTrash
    // clears the freedesktop Trash (files + info) under the home.
    Q_INVOKABLE void quitApp(const QString &head);
    Q_INVOKABLE void emptyTrash();

    // "suspend" | "reboot" | "shutdown" via logind.
    Q_INVOKABLE void powerAction(const QString &action);

    Q_INVOKABLE QString version() const { return QStringLiteral("1.4.0-m2"); }

    // ── Lock screen ───────────────────────────────────────────────────
    Q_INVOKABLE void lock();
    // Verifies via the setuid PAM helper /usr/bin/aegis-auth; emits
    // unlockResult(ok) when done. On success the session unlocks itself.
    Q_INVOKABLE void unlock(const QString &user, const QString &password);

    // ── Shell toggles (org.aegis.Shell DBus surface for CLIs/scripts) ─
    Q_INVOKABLE void toggleControlCenter() { setCcOpen(!m_ccOpen); }
    Q_INVOKABLE void toggleLauncher() { setLauncherOpen(!m_launcherOpen); }
    // W20 — pushed by the aegis-windowwatch KWin script on every
    // windowAdded/Removed/Activated. ONE JSON STRING: {"count": n,
    // "anyFull": b, "ids": [...]}. KWin's callDBus marshals JS numbers
    // as DBus DOUBLE (jsArgument.toVariant() → QVariant(double)), so the
    // earlier (int, bool, QString) slot NEVER matched (the v0.6.37 run:
    // the script pushed, the island never hid) — a single string is the
    // no-type-roulette contract, and ids never travel as a JS array (it
    // would demarshal as DBus "av", not "as").
    Q_INVOKABLE void windowListChanged(const QString &json);
    // T13 D5 — the LAST RAW payload the windowwatch script pushed, kept
    // verbatim for the boot harness: the island auto-hide assert reads
    // pixels, this answers "did the push arrive at all, and with what
    // count" ("" = the script never successfully called the slot).
    Q_INVOKABLE QString windowListRaw() const { return m_lastJson; }

    // W21 — Dock.qml publishes the resting tile centers as the quote-free
    // string "head=cx,cy;head2=cx,cy" (D25 — JSON is NOT usable here:
    // QSettings IniFormat escapes the quotes as \" and KConfig rejects
    // the escape); this writes kwinrc [Effect-aegis-dockzoom] TileMap. The
    // aegis-dockzoom effect cannot callDBus (KWin 6.6 gives callDBus to
    // window scripts, not effects), so kwinrc + KConfigWatcher is the
    // transport into the effect's readConfig("TileMap").
    Q_INVOKABLE void publishDockTileMap(const QString &tileMap);

    // ── Web shortcuts (W22 — strictly opt-in dock entries) ────────
    // Fetches the page (title + apple-touch-icon/favicon.ico/theme-color),
    // stores the icon at ~/.local/share/aegis/webicons/<id>.png and the
    // launcher at ~/.local/share/applications/aegis-web-<id>.desktop
    // (Exec=xdg-open). The W8 resolver surfaces it; nothing is added to
    // the default dock, ever. A network failure still lands the shortcut
    // with a generated letter tile — the entry must always open.
    Q_INVOKABLE void addWebShortcut(const QString &url);
    // Deletes both files for the shortcut with this id.
    Q_INVOKABLE void removeWebShortcut(const QString &id);
    // [{id, name, icon, cmd, web}] — the user-added entries only.
    Q_INVOKABLE QVariantList webShortcuts() const;

    // ── Hardware controls (Control Center) ───────────────────────────
    Q_INVOKABLE void refreshLinkStates();
    Q_INVOKABLE void setWifiEnabled(bool on);
    Q_INVOKABLE void setBluetoothEnabled(bool on);
    Q_INVOKABLE void setMuted(bool on);
    Q_INVOKABLE void setVolume(qreal v);
    Q_INVOKABLE void setBrightness(qreal v);

    // ── Launcher inventory ───────────────────────────────────────────
    // config-pinned apps first, then every installed .desktop entry;
    // [{name, icon, cmd}] — identical shape to config.json "apps".
    Q_INVOKABLE QVariantList allApps() const;

signals:
    void batteryChanged();
    void darkModeChanged();
    void accentChanged();
    void wallpaperChanged();
    void lockedChanged();
    void ccOpenChanged();
    void launcherOpenChanged();
    void linkStatesChanged();
    // Fired on a charging-state transition (island publishing lives in
    // main.cpp, which forwards this to ActivityService).
    void chargingEvent(bool charging, int percent, int minutesToFull);
    void unlockResult(bool ok);
    void runningCmdsChanged();
    // W20 — the window-tracking state changed (count / anyFull / ids)
    void windowTrackingChanged();
    // W22 — the dock model changed (web shortcut added/removed)
    void dockAppsChanged();
    // W22 — addWebShortcut finished (ok=false: the URL never resolved;
    // the tile still lands with a generated letter tile when possible)
    void webShortcutAdded(bool ok, const QString &name);

private slots:
    void refreshBattery();

private:
    QVariantMap defaultConfig() const;
    // W22 — writes the aegis-web-<id>.desktop launcher once the icon is
    // settled (fetched or letter-tile), then fires webShortcutAdded and
    // dockAppsChanged so the dock re-resolves with the new slot.
    void writeWebDesktop(const QString &url, const QString &id,
                         const QString &title, const QString &iconPath);
    void loadPrefs();
    void savePrefs() const;
    void loadAccent();
    void saveAccent() const;
    void forwardToShell(const QString &method, const QString &value) const;
    QString backlightDevice() const;

    QVariantMap m_config;
    QString m_accent = QStringLiteral("#3E8BFF");
    QString m_wallpaper;
    bool m_ownsDBus = false;
    int m_batteryPercent = -1;
    bool m_onBattery = false;
    bool m_charging = false;
    int m_minutesToFull = -1;
    bool m_darkMode = true;
    bool m_locked = false;
    bool m_ccOpen = false;
    bool m_launcherOpen = false;
    bool m_wifiEnabled = false;
    bool m_bluetoothEnabled = false;
    bool m_muted = false;
    qreal m_volume = 0.5;
    qreal m_brightness = -1.0;
    QString m_userName;
    QString m_userInitials;
    QTimer m_batteryTimer;
    QTimer m_linkTimer;
    QStringList m_runningCmds;
    // W20 — the KWin-reported window state. D20: m_windowIds carries
    // allIds (EVERY managed window incl. minimized) so isRunning() and
    // the dock dots stay lit for minimized apps.
    int m_workspaceWindows = 0;
    bool m_anyWindowFull = false;
    QStringList m_windowIds;
    QString m_activeClass;
    // T13 D5 — the raw payload for the harness dump
    QString m_lastJson;
    // W22 — the fetch pipeline for opt-in web shortcuts
    QNetworkAccessManager *m_nam = nullptr;
};
