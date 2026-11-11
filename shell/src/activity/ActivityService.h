#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

// Live Activity API + notifications hub — §2.4 and chapter 07.
//
// Applications publish island activities over the session bus:
//
//   busctl --user call org.aegis.Island /org/aegis/Island \
//          org.aegis.Island.PublishActivity ss"a{sv}" media \
//          '{"title":"Aurora Drift","artist":"Aegis Sound"}'
//
// Kinds (priority stack, Table 5b — call > aegisId > timer > media >
// charging > generic): "media", "call", "timer", "charging", "aegisId",
// "generic". The island renders the top two by priority as the split
// capsule; everything else queues in Control Center.
//
// The same object implements org.freedesktop.Notifications, so every app
// that calls the standard notification API gets Aegis banners (356 × 84,
// stack ≤ 3, auto-out 5 s, DND-aware) without knowing Aegis exists.
class ActivityService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList activities READ activities NOTIFY activitiesChanged)
    Q_PROPERTY(QVariantList banners READ banners NOTIFY bannersChanged)
    Q_PROPERTY(bool bannersVisible READ bannersVisible NOTIFY bannersChanged)
    Q_PROPERTY(bool dnd READ dnd WRITE setDnd NOTIFY dndChanged)
    // M3 — Calm Mode: focus chrome. On: notifications pause (banners quiet
    // through dnd), the governor is pinned to Tier C (80 ms rung swaps), and
    // the top panel collapses its content (hover peeks it back). Session
    // state only — calm is a mood, not a config.

public:
    explicit ActivityService(QObject *parent = nullptr);

    QVariantList activities() const;
    QVariantList banners() const;
    bool bannersVisible() const { return !m_banners.isEmpty() && !m_dnd; }
    bool dnd() const { return m_dnd; }
    void setDnd(bool dnd);
    bool calm() const { return m_calm; }
    void setCalm(bool calm);

    // ── Live Activity API (org.aegis.Island) ─────────────────────────
    // kind: "media" | "call" | "timer" | "charging" | "aegisId" | "generic"
    // data keys per kind — see docs/LIVE-ACTIVITY-API.md.
    Q_INVOKABLE void publishActivity(const QString &id, const QString &kind,
                                     const QVariantMap &data);
    Q_INVOKABLE void endActivity(const QString &id);
    // Island buttons answer here: "accept"/"decline" for calls, "tap"
    // for anything else. Emitted as the org.aegis.Island activityAction
    // signal for the publishing app.
    Q_INVOKABLE void respondActivity(const QString &id, const QString &action);

    // Charging is a shell-owned activity: wired to the battery status
    // transition in main.cpp, auto-ends after 6 s of silence.
    Q_INVOKABLE void publishCharging(int percent, int minutes);

    // ── Banners (org.freedesktop.Notifications + internal toasts) ────
    Q_INVOKABLE void dismissBanner(uint id);
    // Click body: invokes the first action (or closes).
    Q_INVOKABLE void activateBanner(uint id);
    void showBanner(const QString &app, const QString &icon,
                    const QString &summary, const QString &body,
                    const QStringList &actions = {}, int ttl = 5000);

    // org.freedesktop.Notifications — exported to DBus with
    // ExportAllInvokables in start().
    Q_INVOKABLE uint Notify(const QString &app_name, uint replaces_id,
                            const QString &app_icon, const QString &summary,
                            const QString &body, const QStringList &actions,
                            const QVariantMap &hints, int expire_timeout);
    Q_INVOKABLE void CloseNotification(uint id);
    Q_INVOKABLE QStringList GetCapabilities() const;
    Q_INVOKABLE void GetServerInformation(QString &name, QString &vendor,
                                          QString &version,
                                          QString &spec_version) const;

    // Registers session-bus names + objects. Called from main.cpp.
    void start();

signals:
    void activitiesChanged();
    void bannersChanged();
    void dndChanged();
    void calmChanged();

private:
    struct Activity {
        QString id;
        QString kind;
        QVariantMap data;
        int priority;
    };
    struct Banner {
        uint id;
        QString app;
        QString icon;
        QString summary;
        QString body;
        QStringList actions; // [key0, label0, key1, label1, ...]
        int ttl;
    };

    int priorityFor(const QString &kind) const;
    int indexOfActivity(const QString &id) const;
    int indexOfBanner(uint id) const;
    void sendSignal(const QString &path, const QString &iface,
                    const QString &name, const QList<QVariant> &args);
    void pushBanner(const Banner &banner);
    void removeBanner(uint id, uint reason);

    QList<Activity> m_activities;
    QList<Banner> m_banners;
    uint m_nextBannerId = 1;
    bool m_dnd = false;
    bool m_calm = false;
    QTimer m_chargingTimer;
};
