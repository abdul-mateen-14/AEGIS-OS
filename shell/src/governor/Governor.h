#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QTimer>
#include <QVariantMap>
#include <deque>
#include <utility>

class QQuickWindow;
class Util;

// Adaptive effects governor — proposal Listing 2 as code (chapter 09).
//
// The shell-side tier machine. KWin effects (and anything else in the
// session) subscribe by reading the state file or listening to the DBus
// signal; the Control Center badge renders the live tier so the system
// never degrades in secret.
//
//   state Tier: A | B | C
//   on_frame_time(t): if t > 11 ms for 2 s and Tier==A: demote(B)
//                     if t > 22 ms for 2 s and Tier==B: demote(C)
//   on_battery(level): if level < 20 %: demote(C); toast("Calm Mode · battery")
//   demote(T): blur.live = (T==A)   blur.any = (T!=C)
//              motion.spring = (T!=C)   shadows.half = (T==B)
//
// Table 21 exits: B promotes back to A after 60 s of clear frames
// (auto mode only); C is manual-only so it never flaps. Demotions are
// sticky downward on battery, self-healing on AC.
class Governor : public QObject {
    Q_OBJECT
    // T15-D4 (W39.2) — the Settings Desktop-Effects switches call
    // setEffect over the bus. With no Q_CLASSINFO Qt exported the
    // invokables as the generated local.Governor interface (the exact
    // W20 Util lesson: the Q_CLASSINFO D-Bus Interface fix) — the
    // interface name is pinned so the app-process forward resolves.
    Q_CLASSINFO("D-Bus Interface", "org.aegis.Governor")
    Q_PROPERTY(QString tier READ tier NOTIFY tierChanged)
    Q_PROPERTY(bool autoMode READ autoMode NOTIFY tierChanged)
    Q_PROPERTY(int fps READ fps NOTIFY metricsChanged)
    Q_PROPERTY(QVariantMap effects READ effects NOTIFY tierChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool onBattery READ onBattery NOTIFY batteryChanged)

public:
    explicit Governor(Util *util, QObject *parent = nullptr);

    QString tier() const { return m_tier; }
    bool autoMode() const { return m_autoMode; }
    int fps() const { return m_fps; }
    QVariantMap effects() const { return m_effects; }
    int batteryPercent() const;
    bool onBattery() const;

    // Shell windows report frame times here — main.cpp wires every
    // QQuickWindow after its layer surface is configured.
    void watchWindow(QQuickWindow *window);

    // Manual picks from the Control Center governor popover. Picking a
    // tier switches off auto mode (Table 21: C never auto-promotes).
    Q_INVOKABLE void setTier(const QString &tier);
    Q_INVOKABLE void setAutoMode(bool auto_);

    // T15-D4 (W39.2) — per-effect user switches (the Settings Desktop
    // Effects rows are REAL now). An override rides OVER the tier map and
    // persists across sessions; the accepted keys are the governor map
    // plus the wallpaperDim veil key. The app process forwards the call
    // to the shell's governor over the bus (Desktop.qml binds the shell
    // instance) and keeps its own copy in sync for the switch UI.
    Q_INVOKABLE void setEffect(const QString &key, bool on);

    // Registers the DBus service + starts the evaluators. Called once the
    // session bus exists (main.cpp, after engine load).
    void start();

signals:
    void tierChanged();
    void metricsChanged();
    void batteryChanged();
    void toast(const QString &title, const QString &body);

private slots:
    void evaluate();

private:
    void demote(const QString &to, const QString &reason);
    void promote(const QString &to);
    void applyTier();
    void publishState(); // state file for KWin + DBus broadcast

    Util *m_util = nullptr;
    QString m_tier = QStringLiteral("A");
    bool m_autoMode = true;
    int m_fps = 60;
    QVariantMap m_effects;

    // T15-D4 — per-effect user overrides (persisted) + whether this
    // instance owns the org.aegis.Governor bus name (only the shell
    // calls start(); the apps instance forwards writes instead of
    // publishing)
    QVariantMap m_overrides;
    bool m_dbusOwned = false;
    void loadOverrides();
    void persistOverride(const QString &key, bool on);

    // frame-time ring: (timestamp ms, dt ms)
    std::deque<std::pair<qreal, qreal>> m_frames;
    QElapsedTimer m_clock;
    bool m_haveLast = false;
    qreal m_lastTs = 0.0;

    // sustained-violation accumulators (Listing 2: "for 2 s", "clear 60 s")
    qreal m_badMs = 0;
    qreal m_goodMs = 0;

    QTimer m_evalTimer;
};
