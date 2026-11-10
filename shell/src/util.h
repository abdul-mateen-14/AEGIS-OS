#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>

// Small C++ helpers the QML surfaces need: config loading, app launching,
// battery status, hardware controls (brightness, volume, radio states),
// the app inventory for the Launcher, and the PAM-verified unlock bridge
// for the lock screen. Deliberately pragmatic — shell C++ stays light.
class Util : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap config READ config CONSTANT)
    // W8/W9 — the dock model: config.json slots with every Tier B slot
    // ("resolve": true) re-marked from its installed .desktop entry (Icon=,
    // Name=) and dropped entirely when the product is not installed. Tier A
    // first-party slots pass through untouched.
    Q_PROPERTY(QVariantList dockApps READ dockApps CONSTANT)
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
    // Session-level: launch() records every command it starts. M3 swaps the
    // backing store for real KWin window tracking; the QML contract
    // (isRunning / runningCmdsChanged) stays the same.
    Q_PROPERTY(QStringList runningCmds READ runningCmds NOTIFY runningCmdsChanged)
    QStringList runningCmds() const { return m_runningCmds; }
    Q_INVOKABLE bool isRunning(const QString &cmd) const
    {
        return m_runningCmds.contains(cmd);
    }

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

private slots:
    void refreshBattery();

private:
    QVariantMap defaultConfig() const;
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
};
