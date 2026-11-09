#pragma once
#include <QObject>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

// Small file-system bridge for Aegis Files — the four operations the spec
// needs that pure QML cannot do. Everything else (listing, filtering,
// navigation) stays in FolderListModel; no KIO dependency.
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
};
