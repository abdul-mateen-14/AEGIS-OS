#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>

// Small C++ helpers the QML surfaces need: config loading, app launching,
// battery status. Deliberately minimal — M1 keeps the shell C++-light.
class Util : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap config READ config CONSTANT)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool onBattery READ onBattery NOTIFY batteryChanged)

public:
    explicit Util(QObject *parent = nullptr);

    QVariantMap config() const { return m_config; }
    int batteryPercent() const { return m_batteryPercent; }
    bool onBattery() const { return m_onBattery; }

    // Reads a JSON file; falls back to the embedded defaults when missing
    // (dev runs outside the ISO).
    Q_INVOKABLE QVariantMap readConfig(const QString &path) const;

    // Runs a command detached ("dolphin", "xdg-open https://...").
    Q_INVOKABLE void launch(const QString &command);

    // "suspend" | "reboot" | "shutdown" via logind.
    Q_INVOKABLE void powerAction(const QString &action);

    Q_INVOKABLE QString version() const { return QStringLiteral("1.4.0-m1"); }

signals:
    void batteryChanged();

private slots:
    void refreshBattery();

private:
    QVariantMap m_config;
    int m_batteryPercent = -1;
    bool m_onBattery = false;
    QTimer m_batteryTimer;
};
