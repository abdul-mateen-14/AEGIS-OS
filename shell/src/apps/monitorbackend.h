#pragma once

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QObject>
#include <QString>
#include <QTextStream>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <algorithm>
#include <unistd.h>

// ── M3 — Monitor: the /proc reader behind MonitorApp.qml ──────────────────
//
// One refresh() walks /proc once: cpu ticks (delta against the previous
// walk → % across all cores, top-style per-core normalization), meminfo
// (MemTotal − MemAvailable), loadavg, uptime, /proc/net/dev byte deltas
// (loopback excluded), and the process table (pid, comm, state, utime+stime
// delta, rss). Processes sort by cpu desc, capped at 40 rows so the QML
// ListView never walks hundreds of entries.
class MonitorBackend : public QObject {
    Q_OBJECT
    // {cpu, memUsedMb, memTotalMb, memPercent, uptimeSec, load1, netUpKbps,
    //  netDownKbps, processCount}
    Q_PROPERTY(QVariantMap summary READ summary NOTIFY updated)
    // per-core percent, one entry per logical core
    Q_PROPERTY(QVariantList cores READ cores NOTIFY updated)
    // [{pid, name, cpu, rssMb, state}] — cpu desc, max 40
    Q_PROPERTY(QVariantList processes READ processes NOTIFY updated)

public:
    explicit MonitorBackend(QObject *parent = nullptr) : QObject(parent) {}

    QVariantMap summary() const { return m_summary; }
    QVariantList cores() const { return m_cores; }
    QVariantList processes() const { return m_processes; }

    Q_INVOKABLE void refresh() { walk(); }

signals:
    void updated();

private:
    struct ProcSample {
        qint64 ticks = 0;
        qint64 rssBytes = 0;
        QString name;
        QString state;
    };

    static qint64 fieldSum(const QStringList &fields, int from)
    {
        qint64 s = 0;
        for (int i = from; i < fields.size(); ++i)
            s += fields[i].toLongLong();
        return s;
    }

    void walk()
    {
        const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
        const double dt = m_lastMs > 0 ? (nowMs - m_lastMs) / 1000.0 : 0.0;
        const long pageSize = sysconf(_SC_PAGESIZE);

        // ── cpu ─────────────────────────────────────────────────────────
        QFile statFile(QStringLiteral("/proc/stat"));
        QVariantList coreList;
        qint64 totalTicks = 0, idleTicks = 0;
        if (statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&statFile);
            while (!in.atEnd()) {
                const QStringList f = in.readLine().simplified().split(' ');
                if (f.isEmpty()) continue;
                if (f[0] == QStringLiteral("cpu")) {
                    totalTicks = fieldSum(f, 1);
                    // idle column + iowait column (4 and 5 after "cpu")
                    idleTicks = f.size() > 5 ? f[4].toLongLong() + f[5].toLongLong() : 0;
                } else if (f[0].startsWith(QStringLiteral("cpu"))
                           && f[0].size() > 3) {
                    const qint64 t = fieldSum(f, 1);
                    const qint64 idl = f.size() > 5
                                           ? f[4].toLongLong() + f[5].toLongLong() : 0;
                    if (m_lastCoreTotals.contains(f[0])) {
                        const qint64 dT = t - m_lastCoreTotals.value(f[0]);
                        const qint64 dI = idl - m_lastCoreIdles.value(f[0]);
                        coreList.append(dT > 0
                                        ? qBound(0.0, (1.0 - double(dI) / double(dT)) * 100.0, 100.0)
                                        : 0.0);
                    } else {
                        coreList.append(0.0);
                    }
                    m_lastCoreTotals[f[0]] = t;
                    m_lastCoreIdles[f[0]] = idl;
                }
            }
        }

        double cpuPercent = 0.0;
        if (m_lastTotal > 0 && dt > 0) {
            const qint64 dT = totalTicks - m_lastTotal;
            const qint64 dI = idleTicks - m_lastIdle;
            if (dT > 0)
                cpuPercent = qBound(0.0, (1.0 - double(dI) / double(dT)) * 100.0, 100.0);
        }
        m_lastTotal = totalTicks;
        m_lastIdle = idleTicks;

        // ── memory ──────────────────────────────────────────────────────
        qint64 memTotal = 0, memAvail = 0;
        QFile memInfo(QStringLiteral("/proc/meminfo"));
        if (memInfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&memInfo);
            while (!in.atEnd()) {
                const QStringList f = in.readLine().simplified().split(' ');
                if (f.size() < 2) continue;
                if (f[0] == QStringLiteral("MemTotal:")) memTotal = f[1].toLongLong();
                else if (f[0] == QStringLiteral("MemAvailable:")) memAvail = f[1].toLongLong();
            }
        }
        const qint64 memUsedKb = qMax<qint64>(0, memTotal - memAvail);

        // ── uptime + load ───────────────────────────────────────────────
        double uptimeSec = 0;
        QFile upFile(QStringLiteral("/proc/uptime"));
        if (upFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QStringList f = QTextStream(&upFile).readLine().split(' ');
            if (!f.isEmpty()) uptimeSec = f[0].toDouble();
        }
        double load1 = 0;
        QFile loadFile(QStringLiteral("/proc/loadavg"));
        if (loadFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QStringList f = QTextStream(&loadFile).readLine().split(' ');
            if (!f.isEmpty()) load1 = f[0].toDouble();
        }

        // ── network rates ───────────────────────────────────────────────
        qint64 rxBytes = 0, txBytes = 0;
        QFile netFile(QStringLiteral("/proc/net/dev"));
        if (netFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&netFile);
            in.readLine(); in.readLine();   // two header rows
            while (!in.atEnd()) {
                const QString line = in.readLine();
                const int colon = line.indexOf(':');
                if (colon < 0) continue;
                if (line.left(colon).trimmed() == QStringLiteral("lo")) continue;
                const QStringList f = line.mid(colon + 1).simplified().split(' ');
                if (f.size() >= 9) { rxBytes += f[0].toLongLong(); txBytes += f[8].toLongLong(); }
            }
        }
        double downKbps = 0, upKbps = 0;
        if (m_lastMs > 0 && dt > 0) {
            downKbps = qMax<qint64>(0, rxBytes - m_lastRx) / dt / 1024.0;
            upKbps = qMax<qint64>(0, txBytes - m_lastTx) / dt / 1024.0;
        }
        m_lastRx = rxBytes;
        m_lastTx = txBytes;
        m_lastMs = nowMs;

        // ── processes ───────────────────────────────────────────────────
        QHash<QString, ProcSample> samples;
        QDir procDir(QStringLiteral("/proc"));
        const QStringList pids = procDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot,
                                                   QDir::Name);
        int processCount = 0;
        for (const QString &pid : pids) {
            bool numeric = false;
            pid.toLongLong(&numeric);
            if (!numeric) continue;
            QFile sf(QStringLiteral("/proc/%1/stat").arg(pid));
            if (!sf.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
            const QString line = QTextStream(&sf).readLine();
            // comm is "(...)" and may contain spaces — split after the last ')'
            const int closeParen = line.lastIndexOf(')');
            if (closeParen < 0) continue;
            const QString name = line.mid(1, closeParen - 1);
            const QStringList f = line.mid(closeParen + 2).simplified().split(' ');
            // after the ')' the fields shift: state is f[0], utime f[11],
            // stime f[12], rss f[21]
            if (f.size() < 22) continue;
            ProcSample s;
            s.name = name;
            s.state = f[0];
            s.ticks = f[11].toLongLong() + f[12].toLongLong();
            s.rssBytes = f[21].toLongLong() * pageSize;
            samples[pid] = s;
            ++processCount;
        }

        const qint64 dTotalTicks = (m_lastTotal > 0 && dt > 0)
                                       ? totalTicks - m_lastProcessAnchor : 0;
        QVariantList procList;
        for (auto it = samples.constBegin(); it != samples.constEnd(); ++it) {
            double cpu = 0.0;
            const qint64 prev = m_prevTicks.value(it.key(), -1);
            if (prev >= 0 && dt > 0 && dTotalTicks > 0) {
                // top-style: normalized to one core (can exceed 100)
                cpu = double(it->ticks - prev) / double(dTotalTicks)
                      * 100.0 * qMax(1, int(coreList.size()));
                cpu = qBound(0.0, cpu, 100.0 * qMax(1, int(coreList.size())));
            }
            QVariantMap row;
            row[QStringLiteral("pid")] = it.key().toLongLong();
            row[QStringLiteral("name")] = it->name;
            row[QStringLiteral("state")] = it->state;
            row[QStringLiteral("cpu")] = cpu;
            row[QStringLiteral("rssMb")] = it->rssBytes / (1024.0 * 1024.0);
            procList.append(row);
        }
        m_prevTicks.clear();
        for (auto it = samples.constBegin(); it != samples.constEnd(); ++it)
            m_prevTicks[it.key()] = it->ticks;
        m_lastProcessAnchor = totalTicks;

        std::sort(procList.begin(), procList.end(),
                  [](const QVariant &a, const QVariant &b) {
                      return a.toMap().value(QStringLiteral("cpu")).toDouble()
                           > b.toMap().value(QStringLiteral("cpu")).toDouble();
                  });
        if (procList.size() > 40)
            procList = procList.mid(0, 40);

        m_summary = QVariantMap{
            { QStringLiteral("cpu"), cpuPercent },
            { QStringLiteral("memUsedMb"), memUsedKb / 1024.0 },
            { QStringLiteral("memTotalMb"), memTotal / 1024.0 },
            { QStringLiteral("memPercent"),
              memTotal > 0 ? double(memUsedKb) / double(memTotal) * 100.0 : 0.0 },
            { QStringLiteral("uptimeSec"), uptimeSec },
            { QStringLiteral("load1"), load1 },
            { QStringLiteral("netUpKbps"), upKbps },
            { QStringLiteral("netDownKbps"), downKbps },
            { QStringLiteral("processCount"), processCount }
        };
        m_cores = coreList;
        m_processes = procList;
        emit updated();
    }

    // T11-D6 — the summary map must carry the FULL zeroed key set from
    // construction. MonitorApp.qml binds summary.load1.toFixed(2) at
    // component creation, BEFORE the first /proc walk fills the map, and
    // undefined.toFixed threw "TypeError: Cannot call method 'toFixed'"
    // at MonitorApp.qml:150 (v0.6.33 boot test 43136845770 — the verdict
    // had been masked by the PV-m/PV-n parse collision since D5).
    QVariantMap m_summary = {
        { QStringLiteral("cpu"), 0.0 },
        { QStringLiteral("memUsedMb"), 0.0 },
        { QStringLiteral("memTotalMb"), 0.0 },
        { QStringLiteral("memPercent"), 0.0 },
        { QStringLiteral("uptimeSec"), 0 },
        { QStringLiteral("load1"), 0.0 },
        { QStringLiteral("netUpKbps"), 0.0 },
        { QStringLiteral("netDownKbps"), 0.0 },
        { QStringLiteral("processCount"), 0 }
    };
    QVariantList m_cores;
    QVariantList m_processes;
    qint64 m_lastMs = 0, m_lastTotal = 0, m_lastIdle = 0;
    qint64 m_lastRx = 0, m_lastTx = 0;
    qint64 m_lastProcessAnchor = 0;
    QHash<QString, qint64> m_lastCoreTotals;
    QHash<QString, qint64> m_lastCoreIdles;
    QHash<QString, qint64> m_prevTicks;
};

// ── M3 — Editor: text file load/save (EditorApp.qml) ──────────────────────
class TextFileBackend : public QObject {
    Q_OBJECT
public:
    explicit TextFileBackend(QObject *parent = nullptr) : QObject(parent) {}

    // file:///home/x/notes.txt -> /home/x/notes.txt (decoded) — the status
    // footer shows the real path, never the scheme
    Q_INVOKABLE QString prettyPath(const QUrl &file) const
    {
        return file.toLocalFile().isEmpty() ? file.toString() : file.toLocalFile();
    }

    // {ok, text, error} — cap at 4 MB so a stray binary never hangs the UI
    Q_INVOKABLE QVariantMap load(const QUrl &file) const
    {
        QVariantMap out;
        const QString path = file.toLocalFile();
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            out[QStringLiteral("ok")] = false;
            out[QStringLiteral("error")] = f.errorString();
            return out;
        }
        if (f.size() > 4 * 1024 * 1024) {
            out[QStringLiteral("ok")] = false;
            out[QStringLiteral("error")] = QStringLiteral("File larger than 4 MB");
            return out;
        }
        out[QStringLiteral("ok")] = true;
        out[QStringLiteral("text")] = QString::fromUtf8(f.readAll());
        return out;
    }

    Q_INVOKABLE QVariantMap save(const QUrl &file, const QString &text) const
    {
        QVariantMap out;
        QFile f(file.toLocalFile());
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            out[QStringLiteral("ok")] = false;
            out[QStringLiteral("error")] = f.errorString();
            return out;
        }
        const qint64 n = f.write(text.toUtf8());
        out[QStringLiteral("ok")] = n >= 0;
        if (n < 0)
            out[QStringLiteral("error")] = f.errorString();
        return out;
    }
};
