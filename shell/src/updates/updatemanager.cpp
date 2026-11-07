#include "updatemanager.h"

#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

namespace {

// `Inst libfoo (2:1.2-3 Ubuntu:26.04/resolute [24,304 kB])`
const QRegularExpression kInstLine{
    QStringLiteral("^Inst\\s+(\\S+)\\s+\\((\\S+)[^\\[]*(?:\\[([^\\]]+)\\])?\\)")};

QString humanTotal(qint64 bytes)
{
    if (bytes >= 1024 * 1024 * 1024)
        return QStringLiteral("%1 GB").arg(QString::number(bytes / 1073741824.0, 'f', 1));
    if (bytes >= 1024 * 1024)
        return QStringLiteral("%1 MB").arg(QString::number(bytes / 1048576.0, 'f', 1));
    if (bytes >= 1024)
        return QStringLiteral("%1 kB").arg(qMax<qint64>(1, bytes / 1024));
    return QStringLiteral("%1 B").arg(bytes);
}

} // namespace

UpdateManager::UpdateManager(QObject *parent)
    : QObject(parent)
{
    connect(&m_proc, &QProcess::readyReadStandardOutput, this, [this] {
        const QString chunk = QString::fromUtf8(m_proc.readAllStandardOutput());
        m_outBuffer += chunk;
        trackProgress(chunk);
    });
    connect(&m_proc, &QProcess::readyReadStandardError, this, [this] {
        m_tail += QString::fromUtf8(m_proc.readAllStandardError());
        if (m_tail.size() > 4096)
            m_tail = m_tail.right(4096);
    });
    connect(&m_proc,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int code, QProcess::ExitStatus) {
        const Stage stage = m_stage;
        m_stage = Stage::None;
        finishStage(code, stage);
    });

    // A human hint for the first moments before the automatic check lands.
    setStatusLine(QStringLiteral("Checking happens automatically when you open Software Update."));
}

QString UpdateManager::osLabel() const
{
    QFile f(QStringLiteral("/etc/os-release"));
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream ts(&f);
        while (!ts.atEnd()) {
            const QString line = ts.readLine();
            if (line.startsWith(QStringLiteral("PRETTY_NAME=")))
                return line.mid(12).remove(QLatin1Char('"'));
        }
    }
    return QStringLiteral("Aegis OS");
}

bool UpdateManager::busy() const
{
    return m_phase == QStringLiteral("checking")
           || m_phase == QStringLiteral("installing");
}

bool UpdateManager::pkexecAvailable() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("pkexec")).isEmpty();
}

void UpdateManager::setPhase(const QString &phase)
{
    if (m_phase == phase)
        return;
    m_phase = phase;
    emit phaseChanged();
}

void UpdateManager::setPercent(int percent)
{
    if (m_percent == percent)
        return;
    m_percent = percent;
    emit percentChanged();
}

void UpdateManager::setStatusLine(const QString &line)
{
    if (m_statusLine == line)
        return;
    m_statusLine = line;
    emit statusLineChanged();
}

void UpdateManager::fail(const QString &why)
{
    setPhase(QStringLiteral("error"));
    setPercent(-1);
    setStatusLine(why);
}

void UpdateManager::runApt(const QStringList &aptArgs, Stage stage)
{
    if (!pkexecAvailable()) {
        fail(QStringLiteral("The authorization service (polkit) is unavailable."));
        return;
    }
    m_tail.clear();
    m_outBuffer.clear();
    m_stage = stage;
    QStringList argv;
    argv << QStringLiteral("pkexec") << QStringLiteral("/usr/bin/apt-get")
         << aptArgs;
    m_proc.start(argv.value(0), argv.mid(1));
    if (!m_proc.waitForStarted(5000)) {
        m_stage = Stage::None;
        fail(QStringLiteral("Could not start the package manager."));
    }
}

void UpdateManager::checkNow()
{
    if (busy())
        return;
    m_updates.clear();
    m_totalBytes = 0;
    m_count = 0;
    m_progressed = 0;
    emit updatesChanged();
    setPercent(-1);
    setPhase(QStringLiteral("checking"));
    setStatusLine(QStringLiteral("Checking for updates…"));
    runApt({QStringLiteral("update")}, Stage::Refresh);
}

void UpdateManager::installNow()
{
    if (m_phase != QStringLiteral("available"))
        return;
    setPercent(0);
    setPhase(QStringLiteral("installing"));
    setStatusLine(QStringLiteral("Installing updates…"));
    runApt({QStringLiteral("-y"),
            QStringLiteral("-o"), QStringLiteral("Dpkg::Options::=--force-confdef"),
            QStringLiteral("-o"), QStringLiteral("Dpkg::Options::=--force-confold"),
            QStringLiteral("dist-upgrade")},
           Stage::Install);
}

void UpdateManager::restartNow()
{
    QProcess::startDetached(QStringLiteral("systemctl"),
                            {QStringLiteral("-i"), QStringLiteral("reboot")});
}

void UpdateManager::trackProgress(const QString &chunk)
{
    // apt's own percent line when it emits one
    static const QRegularExpression kProgress{QStringLiteral("Progress:\\s*\\[\\s*(\\d+)%")};
    auto it = kProgress.globalMatch(chunk);
    while (it.hasNext()) {
        const int pct = it.next().captured(1).toInt();
        setPercent(qBound(0, pct, 99));
    }

    if (m_stage == Stage::Install && m_count > 0) {
        // count "Unpacking"/"Setting up" lines — dpkg's honest progress
        static const QRegularExpression kStep{
            QStringLiteral("^(?:Unpacking|Setting up|Processing triggers for)\\s+")};
        it = kStep.globalMatch(chunk);
        while (it.hasNext()) {
            it.next();
            ++m_progressed;
        }
        const int totalSteps = qMax(1, m_count * 3);
        const int pct = qBound(0, m_progressed * 100 / totalSteps, 99);
        if (m_percent < 0 || m_percent < pct)
            setPercent(pct);
    }
}

void UpdateManager::finishStage(int exitCode, Stage stage)
{
    if (stage == Stage::Refresh) {
        if (exitCode != 0) {
            fail(QStringLiteral("Couldn't refresh the package lists — check your "
                               "network connection and try again."));
            return;
        }
        setPhase(QStringLiteral("checking"));
        setStatusLine(QStringLiteral("Looking for updates…"));
        runApt({QStringLiteral("-s"), QStringLiteral("dist-upgrade")}, Stage::Probe);
        return;
    }

    if (stage == Stage::Probe) {
        if (exitCode != 0) {
            fail(QStringLiteral("Couldn't check for updates — the package "
                               "manager returned an error."));
            return;
        }
        parseProbe(m_outBuffer);
        emit updatesChanged();
        if (m_count > 0) {
            setPhase(QStringLiteral("available"));
            setStatusLine(QStringLiteral("%1 update%2 available — %3 to download.")
                              .arg(m_count)
                              .arg(m_count == 1 ? QString() : QStringLiteral("s"))
                              .arg(humanTotal(m_totalBytes)));
        } else {
            setPhase(QStringLiteral("up-to-date"));
            setPercent(100);
            setStatusLine(QStringLiteral("Aegis OS is up to date."));
        }
        return;
    }

    if (stage == Stage::Install) {
        if (exitCode != 0) {
            fail(QStringLiteral("Some updates could not be installed. Try again — "
                               "nothing was lost."));
            return;
        }
        m_rebootRequired = QFile::exists(QStringLiteral("/var/run/reboot-required"));
        emit rebootRequiredChanged();
        setPercent(100);
        setPhase(QStringLiteral("up-to-date"));
        setStatusLine(m_rebootRequired
                          ? QStringLiteral("Aegis OS is up to date — restart to finish.")
                          : QStringLiteral("Aegis OS is up to date."));
    }
}

qint64 UpdateManager::sizeToBytes(const QString &human)
{
    static const QRegularExpression kSize{
        QStringLiteral("^([\\d.,]+)\\s*(B|kB|MB|GB)$")};
    const auto m = kSize.match(human.trimmed());
    if (!m.hasMatch())
        return 0;
    QString num = m.captured(1);
    num.remove(QLatin1Char(','));
    const double v = num.toDouble();
    const QString unit = m.captured(2);
    if (unit == QStringLiteral("GB")) return qint64(v * 1073741824.0);
    if (unit == QStringLiteral("MB")) return qint64(v * 1048576.0);
    if (unit == QStringLiteral("kB")) return qint64(v * 1024.0);
    return qint64(v);
}

void UpdateManager::parseProbe(const QString &out)
{
    m_updates.clear();
    m_count = 0;
    m_totalBytes = 0;
    const QStringList lines = out.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        const auto m = kInstLine.match(line);
        if (!m.hasMatch())
            continue;
        const QString name = m.captured(1);
        const QString version = m.captured(2);
        const QString size = m.captured(3); // may be empty
        m_totalBytes += sizeToBytes(size);
        ++m_count;
        m_updates.append(QVariantMap{
            {QStringLiteral("name"), name},
            {QStringLiteral("version"), version},
            {QStringLiteral("size"), size},
        });
    }
}
