#include "Governor.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <algorithm>
#include <cmath>

#include "../util.h"

Governor::Governor(Util *util, QObject *parent)
    : QObject(parent)
    , m_util(util)
{
    m_clock.start();
    applyTier();

    if (m_util)
        connect(m_util, &Util::batteryChanged, this, [this] {
            emit batteryChanged();
            evaluate(); // the battery rule runs on the same evaluator clock
        });

    connect(&m_evalTimer, &QTimer::timeout, this, &Governor::evaluate);
}

int Governor::batteryPercent() const
{
    return m_util ? m_util->batteryPercent() : -1;
}

bool Governor::onBattery() const
{
    return m_util ? m_util->onBattery() : false;
}

void Governor::watchWindow(QQuickWindow *window)
{
    if (!window)
        return;
    // frameSwapped fires once per composited frame; every shell surface
    // feeds the same ring, so the governor measures the session, not one
    // window. dt is governor-wide (last frame of any surface → this one).
    connect(window, &QQuickWindow::frameSwapped, this, [this] {
        const qreal now = qreal(m_clock.elapsed());
        const qreal dt = m_haveLast ? now - m_lastTs : 0.0;
        m_haveLast = true;
        m_lastTs = now;
        if (dt > 0.5 && dt < 1000.0) { // ignore startup gaps + resume stalls
            m_frames.emplace_back(now, dt);
            while (m_frames.size() > 480)
                m_frames.pop_front();
        }
    });
}

void Governor::start()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        bus.registerService(QStringLiteral("org.aegis.Governor"));
        bus.registerObject(QStringLiteral("/org/aegis/Governor"), this,
                           QDBusConnection::ExportInvokables);
    }
    m_evalTimer.start(500);
    publishState();
}

void Governor::setTier(const QString &tier)
{
    if (tier != QStringLiteral("A") && tier != QStringLiteral("B")
        && tier != QStringLiteral("C"))
        return;
    m_autoMode = false;
    m_badMs = 0;
    m_goodMs = 0;
    if (m_tier == tier)
        return;
    m_tier = tier;
    applyTier();
    emit tierChanged();
    publishState();
}

void Governor::setAutoMode(bool auto_)
{
    m_autoMode = auto_;
    if (auto_) {
        m_badMs = 0;
        m_goodMs = 0;
        // Auto picks the healthiest tier it is allowed to right now.
        const bool batteryCalm = onBattery() && batteryPercent() >= 0
                                 && batteryPercent() <= 20;
        m_tier = batteryCalm ? QStringLiteral("C") : QStringLiteral("A");
        applyTier();
        emit tierChanged();
        publishState();
    }
}

void Governor::evaluate()
{
    const qreal now = qreal(m_clock.elapsed());

    // prune frames older than 2.5 s
    while (!m_frames.empty() && m_frames.front().first < now - 2500.0)
        m_frames.pop_front();

    // average frame time over the active window
    qreal sum = 0.0;
    int count = 0;
    qreal span = 0.0;
    if (!m_frames.empty()) {
        span = m_frames.back().first - m_frames.front().first;
        for (const auto &f : m_frames) {
            if (f.second > 0.5 && f.second < 1000.0) { // skip stalls
                sum += f.second;
                ++count;
            }
        }
    }
    const bool active = count >= 24 && span >= 1200.0;
    const qreal avg = count > 0 ? sum / count : 0.0;

    const int newFps = active && avg > 0.0 ? int(std::round(1000.0 / avg)) : m_fps;
    if (newFps != m_fps) {
        m_fps = newFps;
        emit metricsChanged();
    }

    // ── battery rule (Listing 2) — sticky while the condition holds ──
    const bool batteryCalm = onBattery() && batteryPercent() >= 0
                             && batteryPercent() <= 20;
    if (batteryCalm && m_tier != QStringLiteral("C")) {
        demote(QStringLiteral("C"), QStringLiteral("battery"));
        emit toast(QStringLiteral("Calm Mode"),
                   QStringLiteral("Battery below 20% — panels went opaque."));
        return;
    }

    if (!active) {
        // No frames flowing: nothing to violate; idle counts as "clear".
        m_badMs = 0.0;
        if (m_autoMode && m_tier == QStringLiteral("B")
            && !batteryCalm) {
            m_goodMs += 500.0;
            if (m_goodMs >= 60000.0)
                promote(QStringLiteral("A"));
        } else {
            m_goodMs = 0.0;
        }
        return;
    }

    const bool clearA = avg <= 11.0;
    const bool clearB = avg <= 22.0;

    // ── frame-time demotions (Listing 2) ──
    if (m_autoMode && m_tier == QStringLiteral("A") && !clearA) {
        m_badMs += 500.0;
        if (m_badMs >= 2000.0) {
            demote(QStringLiteral("B"), QStringLiteral("frames"));
            return;
        }
    } else if (m_autoMode && m_tier == QStringLiteral("B") && !clearB) {
        m_badMs += 500.0;
        if (m_badMs >= 2000.0) {
            demote(QStringLiteral("C"), QStringLiteral("frames"));
            return;
        }
    } else {
        m_badMs = 0.0;
    }

    // ── B → A promotion: clear for 60 s (Table 21) ──
    if (m_autoMode && m_tier == QStringLiteral("B") && clearA
        && !batteryCalm) {
        m_goodMs += 500.0;
        if (m_goodMs >= 60000.0)
            promote(QStringLiteral("A"));
    } else if (!(m_autoMode && m_tier == QStringLiteral("B")
                 && clearA && !batteryCalm)) {
        m_goodMs = 0.0;
    }
}

void Governor::demote(const QString &to, const QString &reason)
{
    if (m_tier == to)
        return;
    m_tier = to;
    m_badMs = 0.0;
    m_goodMs = 0.0;
    applyTier();
    emit tierChanged();
    publishState();
    Q_UNUSED(reason);
}

void Governor::promote(const QString &to)
{
    if (m_tier == to)
        return;
    m_tier = to;
    m_goodMs = 0.0;
    applyTier();
    emit tierChanged();
    publishState();
}

void Governor::applyTier()
{
    // Listing 2 — demote(T):
    //   blur.live     = (T == A)
    //   blur.any      = (T != C)
    //   motion.spring = (T != C)
    //   shadows.half  = (T == B)
    m_effects = QVariantMap{
        {QStringLiteral("blurLive"), m_tier == QStringLiteral("A")},
        {QStringLiteral("blurAny"), m_tier != QStringLiteral("C")},
        {QStringLiteral("motionSpring"), m_tier != QStringLiteral("C")},
        {QStringLiteral("shadowsHalf"), m_tier == QStringLiteral("B")},
    };
}

void Governor::publishState()
{
    // 1. State file — the cheapest subscription channel for KWin effects:
    //    a script can poll this path, no bus round-trip per frame.
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR",
                                                 QStringLiteral("/tmp"));
    QDir dir(runtime + QStringLiteral("/aegis"));
    if (!dir.exists())
        QDir(runtime).mkpath(QStringLiteral("aegis"));

    QJsonObject root;
    root.insert(QStringLiteral("tier"), m_tier);
    root.insert(QStringLiteral("auto"), m_autoMode);
    root.insert(QStringLiteral("fps"), m_fps);
    QJsonObject effects;
    effects.insert(QStringLiteral("blurLive"), m_effects.value(QStringLiteral("blurLive")).toBool());
    effects.insert(QStringLiteral("blurAny"), m_effects.value(QStringLiteral("blurAny")).toBool());
    effects.insert(QStringLiteral("motionSpring"), m_effects.value(QStringLiteral("motionSpring")).toBool());
    effects.insert(QStringLiteral("shadowsHalf"), m_effects.value(QStringLiteral("shadowsHalf")).toBool());
    root.insert(QStringLiteral("effects"), effects);

    QFile file(dir.filePath(QStringLiteral("governor.json")));
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));

    // 2. DBus broadcast — org.aegis.Governor /org/aegis/Governor
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        QDBusMessage msg = QDBusMessage::createSignal(
            QStringLiteral("/org/aegis/Governor"),
            QStringLiteral("org.aegis.Governor"),
            QStringLiteral("tierChanged"));
        msg << m_tier;
        bus.send(msg);
    }
}
