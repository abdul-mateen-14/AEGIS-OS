#pragma once
#include <QObject>
#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QMimeType>
#include <QMimeData>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

// Small file-system bridge for Aegis Files — the operations the spec needs
// that pure QML cannot do. Everything else (listing, filtering, navigation)
// stays in FolderListModel; no KIO dependency.
//
// W1/W2 (v0.6.9): clipboard (cut/copy/paste with overwrite prompt), MIME-kind
// metadata (tint/label/icon per §8.1 — QMimeDatabase sniffing, not extension
// guessing), hidden-item count for the status footer, Open With choices from
// the .desktop database, a properties map, and the Files view-prefs store
// (grid/sort) that the Aegis ID sync reads as files.prefs.
class FileManager : public QObject {
    Q_OBJECT
public:
    explicit FileManager(QObject *parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE QUrl homeUrl() const
    {
        return QUrl::fromLocalFile(QDir::homePath());
    }

    // The trash view reads the XDG trash "files" directory directly;
    // emptying trash via gio is out of skeleton scope (M4).
    Q_INVOKABLE QUrl trashUrl() const
    {
        const QString base = QStandardPaths::writableLocation(
                                 QStandardPaths::GenericDataLocation)
                             + QStringLiteral("/Trash/files");
        return QUrl::fromLocalFile(base);
    }

    Q_INVOKABLE QString pathOf(const QUrl &u) const { return u.toLocalFile(); }

    Q_INVOKABLE bool makeDir(const QUrl &parent, const QString &name)
    {
        return QDir(parent.toLocalFile()).mkdir(name);
    }

    Q_INVOKABLE bool moveToTrash(const QUrl &f)
    {
        return QFile::moveToTrash(f.toLocalFile());
    }

    Q_INVOKABLE bool rename(const QUrl &f, const QString &newName)
    {
        const QFileInfo fi(f.toLocalFile());
        if (newName.isEmpty() || newName == fi.fileName())
            return false;
        return QFile::rename(fi.absoluteFilePath(),
                             fi.dir().absoluteFilePath(newName));
    }

    // ── W1 — clipboard (cut / copy / paste) ──────────────────────────────
    // The internal list drives the paste; the system clipboard also gets the
    // uri-list so files can cross into KDE apps (and back). paste() with
    // overwrite=false copies nothing when a name conflicts and returns the
    // conflicting names — QML shows the "Replace?" sheet, then re-invokes
    // with overwrite=true. Cut entries are removed after a clean paste.
    Q_INVOKABLE void copyPaths(const QStringList &paths)
    {
        m_clipPaths = paths;
        m_clipCut = false;
        publishClipboard();
    }

    Q_INVOKABLE void cutPaths(const QStringList &paths)
    {
        m_clipPaths = paths;
        m_clipCut = true;
        publishClipboard();
    }

    Q_INVOKABLE bool hasClipboard() const { return !m_clipPaths.isEmpty(); }

    Q_INVOKABLE QStringList paste(const QUrl &targetDir, bool overwrite)
    {
        QDir dir(targetDir.toLocalFile());
        QStringList conflicts;
        if (m_clipPaths.isEmpty())
            return conflicts;
        for (const QString &src : m_clipPaths) {
            const QFileInfo fi(src);
            if (!fi.exists())
                continue;
            const QString dst = dir.filePath(fi.fileName());
            if (dst == fi.absoluteFilePath())
                continue;
            if (m_clipCut) {
                if (dir.exists(fi.fileName()) && !overwrite) {
                    conflicts << fi.fileName();
                    continue;
                }
                if (dir.exists(fi.fileName()))
                    QFile::remove(dst);
                if (!QFile::rename(fi.absoluteFilePath(), dst))
                    conflicts << fi.fileName();
            } else {
                if (dir.exists(fi.fileName()) && !overwrite) {
                    conflicts << fi.fileName();
                    continue;
                }
                if (!QFile::copy(fi.absoluteFilePath(), dst))
                    conflicts << fi.fileName();
            }
        }
        if (m_clipCut && conflicts.isEmpty())
            m_clipPaths.clear();
        return conflicts;
    }

    // ── W2 — MIME-kind metadata (§8.1 kind tints) ────────────────────────
    // One sniffed call per card: {name, isDir, tint, label, icon, mime}.
    // Tints: folders blue · PDFs red · archives amber · images purple ·
    // audio pink · video amber-orange · text blue · unknown grey.
    Q_INVOKABLE QVariantMap fileMeta(const QString &path) const
    {
        return metaFor(QFileInfo(path));
    }

    // Status footer: how many dot-entries this folder hides.
    Q_INVOKABLE int hiddenCount(const QUrl &folder) const
    {
        const QDir dir(folder.toLocalFile());
        return dir.entryList(QDir::Hidden | QDir::NoDotAndDotDot).size();
    }

    // ── W1 — Open With (applications matching the file's MIME type) ──────
    // [{name, icon, exec}] from the XDG .desktop database, exact MIME match
    // plus one parent level (text/plain matches text/markdown & friends).
    Q_INVOKABLE QVariantList openWithChoices(const QString &path) const
    {
        const QMimeDatabase db;
        QMimeType mt = db.mimeTypeForFile(path);
        QStringList wanted;
        if (mt.isValid()) {
            wanted << mt.name();
            wanted << mt.parentMimeTypes();
        }
        QVariantList out;
        QStringList seen;
        for (const QString &dirPath : applicationDirs()) {
            const QDir dir(dirPath);
            const auto files = dir.entryList({QStringLiteral("*.desktop")},
                                             QDir::Files);
            for (const QString &f : files) {
                const QVariantMap app = parseDesktopEntry(dir.filePath(f));
                if (app.isEmpty())
                    continue;
                const QString mimeTypes = app.value(
                                              QStringLiteral("mimetypes"))
                                              .toString();
                bool match = false;
                for (const QString &w : wanted)
                    if (!w.isEmpty()
                        && mimeTypes.contains(w, Qt::CaseInsensitive))
                        match = true;
                const QString exec = app.value(QStringLiteral("exec"))
                                         .toString();
                if (!match || exec.isEmpty())
                    continue;
                const QString head = exec.section(QLatin1Char(' '), 0, 0);
                if (seen.contains(head))
                    continue;
                seen << head;
                out.append(QVariantMap{
                    {QStringLiteral("name"),
                     app.value(QStringLiteral("name")).toString()},
                    {QStringLiteral("icon"),
                     app.value(QStringLiteral("icon")).toString()},
                    {QStringLiteral("exec"), exec},
                });
            }
        }
        return out;
    }

    // Launch a .desktop Exec against a file: substitute the field codes and
    // run detached (same /bin/sh -c contract as Util::launch).
    Q_INVOKABLE bool launchWith(const QString &exec, const QString &path)
    {
        QString cmd = exec;
        const QString quoted = path.contains(QLatin1Char(' '))
                                   ? QLatin1Char('"') + path + QLatin1Char('"')
                                   : path;
        const QString url = QUrl::fromLocalFile(path).toString();
        if (cmd.contains(QLatin1String("%f")) || cmd.contains(QLatin1String("%F")))
            cmd.replace(QLatin1String("%F"), quoted)
                .replace(QLatin1String("%f"), quoted);
        else if (cmd.contains(QLatin1String("%u")) || cmd.contains(QLatin1String("%U")))
            cmd.replace(QLatin1String("%U"), url)
                .replace(QLatin1String("%u"), url);
        else
            cmd += QLatin1Char(' ') + quoted;
        return QProcess::startDetached(QStringLiteral("/bin/sh"),
                                       {QStringLiteral("-c"), cmd});
    }

    // ── W1 — properties sheet ────────────────────────────────────────────
    Q_INVOKABLE QVariantMap propertiesOf(const QString &path) const
    {
        const QFileInfo fi(path);
        QVariantMap m = metaFor(fi);
        const qint64 bytes = fi.isDir() ? -1 : fi.size();
        QString size;
        if (fi.isDir())
            size = QStringLiteral("—");
        else if (bytes >= 1048576)
            size = QString::number(bytes / 1048576.0, 'f', 1) + QStringLiteral(" MB");
        else if (bytes >= 1024)
            size = QString::number(bytes / 1024.0, 'f', 1) + QStringLiteral(" KB");
        else
            size = QString::number(bytes) + QStringLiteral(" B");
        m.insert(QStringLiteral("size"), size);
        m.insert(QStringLiteral("modified"),
                 fi.lastModified().toString(QStringLiteral("yyyy-MM-dd HH:mm")));
        m.insert(QStringLiteral("path"), fi.absoluteFilePath());
        return m;
    }

    // ── Files view prefs (grid/sort) — also the files.prefs sync payload ─
    Q_INVOKABLE void saveViewPrefs(const QString &json)
    {
        QFile file(prefsPath());
        if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            file.write(json.toUtf8());
            emit viewPrefsChanged(); // a synced pull re-applies live
        }
    }

    Q_INVOKABLE QString loadViewPrefs() const
    {
        QFile file(prefsPath());
        if (!file.open(QIODevice::ReadOnly))
            return QStringLiteral("{}");
        return QString::fromUtf8(file.readAll());
    }

signals:
    void viewPrefsChanged();

private:
    static QString prefsPath()
    {
        const QString base = QStandardPaths::writableLocation(
                                 QStandardPaths::GenericConfigLocation);
        QDir(base).mkpath(QStringLiteral("aegis"));
        return base + QStringLiteral("/aegis/files-prefs.json");
    }

    static QStringList applicationDirs()
    {
        QStringList dirs;
        if (!qEnvironmentVariableIsEmpty("HOME"))
            dirs << qEnvironmentVariable("HOME")
                          + QStringLiteral("/.local/share/applications");
        dirs << QStringLiteral("/usr/local/share/applications")
             << QStringLiteral("/usr/share/applications");
        return dirs;
    }

    // Minimal .desktop parse — Name/Icon/Exec/MimeType of [Desktop Entry].
    static QVariantMap parseDesktopEntry(const QString &path)
    {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        QVariantMap app;
        QString line;
        bool inEntry = false;
        while (file.canReadLine()) {
            const QString t = QString::fromUtf8(file.readLine()).trimmed();
            if (t.isEmpty() || t.startsWith(QLatin1Char('#')))
                continue;
            if (t.startsWith(QLatin1Char('['))) {
                if (inEntry)
                    break;
                inEntry = t.compare(QStringLiteral("[Desktop Entry]"),
                                    Qt::CaseInsensitive) == 0;
                continue;
            }
            if (!inEntry || !t.contains(QLatin1Char('=')))
                continue;
            const int eq = t.indexOf(QLatin1Char('='));
            const QString key = t.left(eq).trimmed();
            const QString value = t.mid(eq + 1).trimmed();
            if (key == QLatin1String("Name"))
                app.insert(QStringLiteral("name"), value);
            else if (key == QLatin1String("Icon"))
                app.insert(QStringLiteral("icon"), value);
            else if (key == QLatin1String("Exec"))
                app.insert(QStringLiteral("exec"), value);
            else if (key == QLatin1String("MimeType"))
                app.insert(QStringLiteral("mimetypes"), value);
        }
        return app;
    }

    void publishClipboard() const
    {
        QList<QUrl> urls;
        for (const QString &p : m_clipPaths)
            urls << QUrl::fromLocalFile(p);
        QMimeData *mime = new QMimeData;
        mime->setUrls(urls);
        QGuiApplication::clipboard()->setMimeData(mime);
    }

    // The §8.1 kind map — one place, QML and properties reuse it.
    static QVariantMap metaFor(const QFileInfo &fi)
    {
        QVariantMap m;
        m.insert(QStringLiteral("name"), fi.fileName());
        m.insert(QStringLiteral("isDir"), fi.isDir());
        QString tint = QStringLiteral("#8A909C");
        QString label = QStringLiteral("File");
        QString icon = QStringLiteral("text-x-generic");
        bool tintable = false;
        QString mime;
        if (fi.isDir()) {
            tint = QStringLiteral("#5B8BFF");
            label = QStringLiteral("Folder");
            icon = QStringLiteral("folder");
            mime = QStringLiteral("inode/directory");
        } else {
            QMimeDatabase db;
            QMimeType mt = db.mimeTypeForFile(fi.absoluteFilePath());
            if (mt.isValid())
                mime = mt.name();
            const QString n = mime.toLower();
            // W16 — document kinds render DOCUMENT glyphs tinted by §8.1
            // (the provider template-recolors on the ?tint= query);
            // folder/image/audio/video glyphs are pre-colored theme SVGs
            // and stay untouched (tintable false).
            if (n == QLatin1String("application/pdf")) {
                tint = QStringLiteral("#FA2D48");
                label = QStringLiteral("PDF");
                icon = QStringLiteral("aegis-doc-page");
                tintable = true;
            } else if (n.contains(QLatin1String("zip"))
                       || n.contains(QLatin1String("tar"))
                       || n.contains(QLatin1String("compressed"))
                       || n.contains(QLatin1String("archive"))) {
                tint = QStringLiteral("#FF9F0A");
                label = QStringLiteral("Archive");
                icon = QStringLiteral("aegis-doc-archive");
                tintable = true;
            } else if (n.startsWith(QLatin1String("image/"))) {
                tint = QStringLiteral("#8B5CF6");
                label = QStringLiteral("Image");
                icon = QStringLiteral("folder-pictures");
            } else if (n.startsWith(QLatin1String("audio/"))) {
                tint = QStringLiteral("#FF6B84");
                label = QStringLiteral("Audio");
                icon = QStringLiteral("folder-music");
            } else if (n.startsWith(QLatin1String("video/"))) {
                tint = QStringLiteral("#FFB84D");
                label = QStringLiteral("Video");
                icon = QStringLiteral("folder-videos");
            } else if (n.startsWith(QLatin1String("text/"))) {
                tint = QStringLiteral("#3E8BFF");
                label = QStringLiteral("Text");
                icon = QStringLiteral("aegis-doc-text");
                tintable = true;
            }
        }
        m.insert(QStringLiteral("tint"), tint);
        m.insert(QStringLiteral("tintable"), tintable);
        m.insert(QStringLiteral("label"), label);
        m.insert(QStringLiteral("icon"), icon);
        m.insert(QStringLiteral("mime"), mime);
        return m;
    }

    QStringList m_clipPaths;
    bool m_clipCut = false;
};
