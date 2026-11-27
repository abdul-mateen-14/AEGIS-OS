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
#include <QStorageInfo>
#include <QTextStream>
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
//
// W89 (v0.6.99) — the user: "dolphin is working accurately but the files app
// is mostly placeholders" (Dolphin shipped in the ISO from the M1 era and
// gets deleted in the same round; the parity it had over Files is exactly
// this list). Adds the real Dolphin-parity backend: mounted volumes for the
// sidebar Devices (QStorageInfo — the Removable row had NO onClicked at
// all), the XDG trash ledger (list/restore/empty — the trash view could
// show files but nothing else), permanent delete and duplicate.
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
        return QUrl::fromLocalFile(trashBase() + QStringLiteral("/files"));
    }

    Q_INVOKABLE QString pathOf(const QUrl &u) const { return u.toLocalFile(); }

    // W89 — selection helpers for the QML keyboard contract: the paths of
    // a folder (sorted dirs-first like FolderListModel's default) so
    // Ctrl+A / Shift-range can build the selection without a get() API
    // (FolderListModel exposes none), and a plain is-dir probe.
    Q_INVOKABLE QStringList listPaths(const QUrl &folder) const
    {
        const QDir dir(folder.toLocalFile());
        QStringList dirs, files;
        for (const QFileInfo &fi : dir.entryInfoList(
                 QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot)) {
            (fi.isDir() ? dirs : files) << fi.absoluteFilePath();
        }
        dirs.sort(Qt::CaseInsensitive);
        files.sort(Qt::CaseInsensitive);
        return dirs + files;
    }

    Q_INVOKABLE bool isDir(const QUrl &f) const
    {
        return QFileInfo(f.toLocalFile()).isDir();
    }

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

    // ── W89 — Dolphin parity: volumes / trash ledger / permanent ops ─────

    // Mounted filesystems for the sidebar Devices rail. Skips pseudo-fs
    // (proc/sys/run/devtmpfs, squashfs live medium, snap loop mounts) so
    // the list matches what a file manager should offer: the root
    // filesystem ("System") plus every real block device, removable
    // flags included. [{name, path, icon, removable, free, capacity}]
    Q_INVOKABLE QVariantList volumes() const
    {
        QVariantList out;
        const auto all = QStorageInfo::mountedVolumes();
        for (const QStorageInfo &si : all) {
            if (!si.isValid() || !si.isReady())
                continue;
            const QString fs = QString::fromUtf8(si.fileSystemType());
            const QString mp = si.rootPath();
            if (fs == QLatin1String("proc") || fs == QLatin1String("sysfs")
                || fs == QLatin1String("devtmpfs")
                || fs == QLatin1String("tmpfs")
                || fs == QLatin1String("squashfs")
                || fs == QLatin1String("efivarfs")
                || fs.startsWith(QLatin1String("fuse."))
                || mp.startsWith(QLatin1String("/snap/"))
                || mp.startsWith(QLatin1String("/sys/"))
                || mp.startsWith(QLatin1String("/proc/"))
                || mp.startsWith(QLatin1String("/run/"))
                || mp.startsWith(QLatin1String("/dev/"))
                || mp == QLatin1String("/boot/efi"))
                continue;
            const QString label = si.displayName().isEmpty()
                                      ? mp : si.displayName();
            out.append(QVariantMap{
                {QStringLiteral("name"), label},
                {QStringLiteral("path"), mp},
                {QStringLiteral("icon"),
                 si.isRoot() ? QStringLiteral("drive-harddisk-root")
                             : (si.isReadOnly()
                                    ? QStringLiteral("drive-removable")
                                    : QStringLiteral("drive-harddisk"))},
                {QStringLiteral("removable"), si.isReadOnly() || !si.isRoot()},
                {QStringLiteral("free"),
                 QString::number(si.bytesFree() / 1073741824.0, 'f', 0)},
                {QStringLiteral("capacity"),
                 QString::number(si.bytesTotal() / 1073741824.0, 'f', 0)},
            });
        }
        return out;
    }

    static QString trashBase()
    {
        return QStandardPaths::writableLocation(
                   QStandardPaths::GenericDataLocation)
               + QStringLiteral("/Trash");
    }

    // The XDG trash ledger: files/ holds the payloads, info/*.trashinfo
    // holds Path= (URL-encoded) and DeletionDate=. Full records so the
    // trash view can show where a file came from and when it died.
    // [{name, path, originalPath, deletionDate, isDir, tint, label, icon}]
    Q_INVOKABLE QVariantList trashItems() const
    {
        QVariantList out;
        const QDir files(trashBase() + QStringLiteral("/files"));
        const QDir info(trashBase() + QStringLiteral("/info"));
        for (const QFileInfo &fi : files.entryInfoList(
                 QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot)) {
            QVariantMap m = metaFor(fi);
            const QFileInfo ti(info.filePath(fi.fileName()
                                            + QStringLiteral(".trashinfo")));
            if (ti.exists()) {
                QFile f(ti.absoluteFilePath());
                if (f.open(QIODevice::ReadOnly)) {
                    QTextStream ts(&f);
                    QString line;
                    while (ts.readLineInto(&line)) {
                        if (line.startsWith(QLatin1String("Path=")))
                            m.insert(QStringLiteral("originalPath"),
                                     QUrl::fromPercentEncoding(
                                         line.mid(5).trimmed().toUtf8()));
                        else if (line.startsWith(
                                     QLatin1String("DeletionDate=")))
                            m.insert(QStringLiteral("deletionDate"),
                                     line.mid(13).trimmed()
                                         .replace(QLatin1Char('T'),
                                                  QLatin1Char(' ')));
                    }
                }
            }
            m.insert(QStringLiteral("path"), fi.absoluteFilePath());
            out.append(m);
        }
        return out;
    }

    // Restore: move the payload back to its recorded Path= (creating the
    // parent when it vanished), then drop the .trashinfo.
    Q_INVOKABLE bool restoreFromTrash(const QString &trashPath)
    {
        const QFileInfo fi(trashPath);
        const QFileInfo ti(QDir(trashBase() + QStringLiteral("/info"))
                               .filePath(fi.fileName()
                                         + QStringLiteral(".trashinfo")));
        QString original;
        if (ti.exists()) {
            QFile f(ti.absoluteFilePath());
            if (f.open(QIODevice::ReadOnly)) {
                QTextStream ts(&f);
                QString line;
                while (ts.readLineInto(&line))
                    if (line.startsWith(QLatin1String("Path=")))
                        original = QUrl::fromPercentEncoding(
                            line.mid(5).trimmed().toUtf8());
            }
        }
        if (original.isEmpty())
            return false;
        QDir().mkpath(QFileInfo(original).absolutePath());
        if (!QFile::rename(fi.absoluteFilePath(), original))
            return false;
        QFile::remove(ti.absoluteFilePath());
        return true;
    }

    // Empty the trash: payloads + info records. Returns how many items
    // went (the UI toast).
    Q_INVOKABLE int emptyTrash()
    {
        int n = 0;
        const QDir files(trashBase() + QStringLiteral("/files"));
        const QDir info(trashBase() + QStringLiteral("/info"));
        for (const QFileInfo &fi : files.entryInfoList(
                 QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot)) {
            const bool ok = fi.isDir()
                                ? QDir(fi.absoluteFilePath())
                                      .removeRecursively()
                                : QFile::remove(fi.absoluteFilePath());
            if (ok)
                ++n;
            QFile::remove(info.filePath(fi.fileName()
                                        + QStringLiteral(".trashinfo")));
        }
        return n;
    }

    // Shift+Delete — no recycle, no undo.
    Q_INVOKABLE bool deletePermanently(const QUrl &f)
    {
        const QFileInfo fi(f.toLocalFile());
        return fi.isDir()
                   ? QDir(fi.absoluteFilePath()).removeRecursively()
                   : QFile::remove(fi.absoluteFilePath());
    }

    // Dolphin's "Duplicate Here": copy in place as "name copy" (then
    // "name copy 2", ...) — never overwrites anything.
    Q_INVOKABLE QString duplicate(const QUrl &f)
    {
        const QFileInfo fi(f.toLocalFile());
        QDir dir = fi.dir();
        QString base = fi.fileName();
        const QString dot = fi.completeSuffix().isEmpty()
                                ? QString()
                                : QStringLiteral(".")
                                      + fi.completeSuffix();
        if (!dot.isEmpty())
            base.chop(dot.length());
        QString candidate = base + QStringLiteral(" copy") + dot;
        for (int i = 2; dir.exists(candidate); ++i)
            candidate = base + QStringLiteral(" copy ") + QString::number(i)
                        + dot;
        const QString dst = dir.filePath(candidate);
        const bool ok = fi.isDir()
                            ? copyRecursively(fi.absoluteFilePath(), dst)
                            : QFile::copy(fi.absoluteFilePath(), dst);
        return ok ? dst : QString();
    }

    // Open a terminal in the folder (Dolphin parity — the context menu
    // item the user expects in a file manager).
    Q_INVOKABLE bool openTerminalHere(const QUrl &folder)
    {
        const QString path = folder.toLocalFile();
        if (path.isEmpty() || !QDir(path).exists())
            return false;
        return QProcess::startDetached(
            QStringLiteral("konsole"),
            {QStringLiteral("--workdir"), path});
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
        // W28 — the sheet binds size/modified/path; they showed as
        // placeholders in the VM review when the input arrived as a
        // file:// URL (QFileInfo on a URL string: size 0, epoch mtime).
        // Accept both shapes and always work on a local path.
        QString p = path;
        if (p.startsWith(QStringLiteral("file://")))
            p = QUrl(p).toLocalFile();
        const QFileInfo fi(p);
        QVariantMap m = metaFor(fi);
        const qint64 bytes = fi.isDir() ? -1 : fi.size();
        QString size;
        if (fi.isDir())
            size = QStringLiteral("—");
        else if (bytes >= 1073741824)
            size = QString::number(bytes / 1073741824.0, 'f', 1)
                   + QStringLiteral(" GB");
        else if (bytes >= 1048576)
            size = QString::number(bytes / 1048576.0, 'f', 1) + QStringLiteral(" MB");
        else if (bytes >= 1024)
            size = QString::number(bytes / 1024.0, 'f', 1) + QStringLiteral(" KB");
        else
            size = QString::number(bytes) + QStringLiteral(" B");
        m.insert(QStringLiteral("size"), size);
        // W28 — the v1.3 date style: "12 Nov 2026 14:32"
        m.insert(QStringLiteral("modified"),
                 fi.lastModified().toString(QStringLiteral("d MMM yyyy HH:mm")));
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

    // QDir::copyRecursively does not exist in QDir itself (QDir::cp was
    // Qt 6.7+ and not on Kubuntu's 6.4 at the time of the M1 build);
    // fold directories by hand for Duplicate.
    static bool copyRecursively(const QString &src, const QString &dst)
    {
        const QFileInfo sfi(src);
        if (sfi.isFile())
            return QFile::copy(src, dst);
        if (!QDir().mkpath(dst))
            return false;
        const QDir s(src);
        bool ok = true;
        for (const QFileInfo &fi : s.entryInfoList(
                 QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot)) {
            ok = copyRecursively(
                     fi.absoluteFilePath(),
                     dst + QLatin1Char('/') + fi.fileName())
                 && ok;
        }
        return ok;
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
