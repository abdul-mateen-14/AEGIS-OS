#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QVariantList>

// Software Update backend — the GUI path for every patch on Aegis OS
// (macOS model: one app answers "is my system current?", one button
// applies everything, unattended-upgrades keeps security fixes flowing
// in the background meanwhile — etc/apt/apt.conf.d/20auto-upgrades).
//
// Phases:
//   idle → checking (pkexec apt-get update; then apt-get -s dist-upgrade)
//        → available (updates parsed into cards) / up-to-date / error
//        → installing (pkexec apt-get dist-upgrade, live percent)
//        → up-to-date (+ rebootRequired when /var/run/reboot-required)
class UpdateManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString phase READ phase NOTIFY phaseChanged)
    Q_PROPERTY(QVariantList updates READ updates NOTIFY updatesChanged)
    Q_PROPERTY(QString statusLine READ statusLine NOTIFY statusLineChanged)
    Q_PROPERTY(int percent READ percent NOTIFY percentChanged) // -1 = indeterminate
    Q_PROPERTY(bool busy READ busy NOTIFY phaseChanged)
    Q_PROPERTY(bool rebootRequired READ rebootRequired NOTIFY rebootRequiredChanged)
    Q_PROPERTY(QString osLabel READ osLabel CONSTANT)

public:
    explicit UpdateManager(QObject *parent = nullptr);

    QString phase() const { return m_phase; }
    QVariantList updates() const { return m_updates; }
    QString statusLine() const { return m_statusLine; }
    int percent() const { return m_percent; }
    bool busy() const;
    bool rebootRequired() const { return m_rebootRequired; }
    QString osLabel() const;

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void installNow();
    Q_INVOKABLE void restartNow();

signals:
    void phaseChanged();
    void updatesChanged();
    void statusLineChanged();
    void percentChanged();
    void rebootRequiredChanged();

private:
    enum class Stage { None, Refresh, Probe, Install };

    void setPhase(const QString &phase);
    void setPercent(int percent);
    void setStatusLine(const QString &line);
    void runApt(const QStringList &aptArgs, Stage stage);
    bool pkexecAvailable() const;
    void fail(const QString &why);
    void finishStage(int exitCode, Stage stage);
    void parseProbe(const QString &out);
    void trackProgress(const QString &chunk);
    static qint64 sizeToBytes(const QString &human);

    QProcess m_proc;
    Stage m_stage = Stage::None;
    QString m_phase = QStringLiteral("idle");
    QVariantList m_updates;
    QString m_statusLine;
    QString m_tail;
    QString m_outBuffer;   // full stdout — parsed once a stage finishes
    int m_percent = -1;
    int m_count = 0;
    int m_progressed = 0;
    qint64 m_totalBytes = 0;
    bool m_rebootRequired = false;
};
