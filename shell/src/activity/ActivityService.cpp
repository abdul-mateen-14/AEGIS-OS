#include "ActivityService.h"

#include <QDBusConnection>
#include <QDBusMessage>

#include <algorithm>

// Priority stack — Table 5b, fixed order. Lower sorts first.
int ActivityService::priorityFor(const QString &kind) const
{
    if (kind == QStringLiteral("call"))
        return 0;
    if (kind == QStringLiteral("aegisId"))
        return 1;
    if (kind == QStringLiteral("timer"))
        return 2;
    if (kind == QStringLiteral("media"))
        return 3;
    if (kind == QStringLiteral("charging"))
        return 4;
    return 5; // generic
}

ActivityService::ActivityService(QObject *parent)
    : QObject(parent)
{
    m_chargingTimer.setSingleShot(true);
    connect(&m_chargingTimer, &QTimer::timeout, this, [this] {
        endActivity(QStringLiteral("charging"));
    });
}

QVariantList ActivityService::activities() const
{
    QVariantList out;
    for (const Activity &a : m_activities) {
        QVariantMap map;
        map.insert(QStringLiteral("id"), a.id);
        map.insert(QStringLiteral("kind"), a.kind);
        map.insert(QStringLiteral("data"), a.data);
        out.append(map);
    }
    return out;
}

QVariantList ActivityService::banners() const
{
    QVariantList out;
    for (const Banner &b : m_banners) {
        QVariantMap map;
        map.insert(QStringLiteral("id"), b.id);
        map.insert(QStringLiteral("app"), b.app);
        map.insert(QStringLiteral("icon"), b.icon);
        map.insert(QStringLiteral("summary"), b.summary);
        map.insert(QStringLiteral("body"), b.body);
        map.insert(QStringLiteral("actions"), b.actions);
        map.insert(QStringLiteral("ttl"), b.ttl);
        out.append(map);
    }
    return out;
}

void ActivityService::setDnd(bool dnd)
{
    if (m_dnd == dnd)
        return;
    m_dnd = dnd;
    emit dndChanged();
    emit bannersChanged();
}

// M3 — Calm Mode. Banners quiet through dnd (one flag, one behavior — the
// panel reads calm for the chrome collapse, the governor tile reads calm to
// pin Tier C). Turning calm off restores the tier machine to auto mode;
// the Control Center tile owns that wiring, the service only carries state.
void ActivityService::setCalm(bool calm)
{
    if (m_calm == calm)
        return;
    m_calm = calm;
    if (calm && !m_dnd) {
        m_dnd = true;
        emit dndChanged();
        emit bannersChanged();
    }
    emit calmChanged();
}

int ActivityService::indexOfActivity(const QString &id) const
{
    for (int i = 0; i < m_activities.size(); ++i)
        if (m_activities[i].id == id)
            return i;
    return -1;
}

int ActivityService::indexOfBanner(uint id) const
{
    for (int i = 0; i < m_banners.size(); ++i)
        if (m_banners[i].id == id)
            return i;
    return -1;
}

void ActivityService::publishActivity(const QString &id, const QString &kind,
                                      const QVariantMap &data)
{
    if (id.isEmpty())
        return;
    const int at = indexOfActivity(id);
    if (at >= 0) {
        m_activities[at].kind = kind;
        m_activities[at].data = data;
        m_activities[at].priority = priorityFor(kind);
    } else {
        Activity a;
        a.id = id;
        a.kind = kind;
        a.data = data;
        a.priority = priorityFor(kind);
        m_activities.append(a);
    }
    std::sort(m_activities.begin(), m_activities.end(),
              [](const Activity &a, const Activity &b) {
                  return a.priority < b.priority;
              });
    emit activitiesChanged();
    sendSignal(QStringLiteral("/org/aegis/Island"),
               QStringLiteral("org.aegis.Island"),
               QStringLiteral("activityStarted"),
               {id, kind});
}

void ActivityService::endActivity(const QString &id)
{
    const int at = indexOfActivity(id);
    if (at < 0)
        return;
    const QString kind = m_activities[at].kind;
    m_activities.removeAt(at);
    emit activitiesChanged();
    sendSignal(QStringLiteral("/org/aegis/Island"),
               QStringLiteral("org.aegis.Island"),
               QStringLiteral("activityEnded"),
               {id, kind});
}

void ActivityService::respondActivity(const QString &id, const QString &action)
{
    // Forward to the publishing app, then retire call activities —
    // accept / decline both end the incoming-call capsule.
    sendSignal(QStringLiteral("/org/aegis/Island"),
               QStringLiteral("org.aegis.Island"),
               QStringLiteral("activityAction"),
               {id, action});
    if (action == QStringLiteral("accept") || action == QStringLiteral("decline"))
        endActivity(id);
}

void ActivityService::publishCharging(int percent, int minutes)
{
    QVariantMap data;
    data.insert(QStringLiteral("percent"), percent);
    data.insert(QStringLiteral("minutes"), minutes < 0 ? 40 : minutes);
    publishActivity(QStringLiteral("charging"), QStringLiteral("charging"),
                    data);
    m_chargingTimer.start(6000); // re-armed on every refresh while plugged
}

void ActivityService::pushBanner(const Banner &banner)
{
    // Stack ceiling — Table 17: at most three banners; the oldest drops.
    while (m_banners.size() >= 3) {
        const uint dropped = m_banners.first().id;
        m_banners.removeFirst();
        sendSignal(QStringLiteral("/org/freedesktop/Notifications"),
                   QStringLiteral("org.freedesktop.Notifications"),
                   QStringLiteral("NotificationClosed"),
                   {dropped, uint(2)});
    }
    m_banners.append(banner);
    emit bannersChanged();
}

void ActivityService::showBanner(const QString &app, const QString &icon,
                                 const QString &summary, const QString &body,
                                 const QStringList &actions, int ttl)
{
    Banner b;
    b.id = m_nextBannerId++;
    b.app = app;
    b.icon = icon;
    b.summary = summary;
    b.body = body;
    b.actions = actions;
    b.ttl = ttl > 0 && ttl <= 60000 ? ttl : 5000;
    pushBanner(b);
}

void ActivityService::removeBanner(uint id, uint reason)
{
    const int at = indexOfBanner(id);
    if (at < 0)
        return;
    m_banners.removeAt(at);
    emit bannersChanged();
    sendSignal(QStringLiteral("/org/freedesktop/Notifications"),
               QStringLiteral("org.freedesktop.Notifications"),
               QStringLiteral("NotificationClosed"),
               {id, reason});
}

void ActivityService::dismissBanner(uint id)
{
    removeBanner(id, uint(1)); // expired
}

void ActivityService::activateBanner(uint id)
{
    const int at = indexOfBanner(id);
    if (at < 0)
        return;
    const QStringList actions = m_banners[at].actions;
    if (actions.size() >= 2) {
        sendSignal(QStringLiteral("/org/freedesktop/Notifications"),
                   QStringLiteral("org.freedesktop.Notifications"),
                   QStringLiteral("ActionInvoked"),
                   {id, actions.at(0)});
    }
    removeBanner(id, uint(2)); // dismissed by user action
}

uint ActivityService::Notify(const QString &app_name, uint replaces_id,
                             const QString &app_icon, const QString &summary,
                             const QString &body, const QStringList &actions,
                             const QVariantMap &hints, int expire_timeout)
{
    Q_UNUSED(hints);
    if (replaces_id > 0 && indexOfBanner(replaces_id) >= 0)
        removeBanner(replaces_id, uint(2));
    showBanner(app_name.isEmpty() ? QStringLiteral("Aegis") : app_name,
               app_icon.isEmpty() ? QStringLiteral("dialog-information")
                                  : app_icon,
               summary, body, actions, expire_timeout);
    return m_nextBannerId - 1;
}

void ActivityService::CloseNotification(uint id)
{
    removeBanner(id, uint(3)); // closed by a Replace/Close call
}

QStringList ActivityService::GetCapabilities() const
{
    return QStringList{QStringLiteral("actions"), QStringLiteral("body"),
                       QStringLiteral("body-markup")};
}

void ActivityService::GetServerInformation(QString &name, QString &vendor,
                                           QString &version,
                                           QString &spec_version) const
{
    name = QStringLiteral("Aegis Shell");
    vendor = QStringLiteral("Aegis OS Project");
    version = QStringLiteral("1.4.0");
    spec_version = QStringLiteral("1.2");
}

void ActivityService::start()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;

    bus.registerService(QStringLiteral("org.aegis.Island"));
    bus.registerObject(QStringLiteral("/org/aegis/Island"), this,
                       QDBusConnection::ExportAllInvokables);

    // Own the standard notifications name when nobody else does — in the
    // Aegis session no other notification daemon is started, so every
    // notify-send lands as an Aegis banner.
    if (bus.registerService(QStringLiteral("org.freedesktop.Notifications"))) {
        bus.registerObject(QStringLiteral("/org/freedesktop/Notifications"),
                           this, QDBusConnection::ExportAllInvokables);
    }
}

void ActivityService::sendSignal(const QString &path, const QString &iface,
                                 const QString &name,
                                 const QList<QVariant> &args)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;
    QDBusMessage msg = QDBusMessage::createSignal(path, iface, name);
    msg.setArguments(args);
    bus.send(msg);
}
