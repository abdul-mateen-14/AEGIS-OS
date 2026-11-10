#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <openssl/sha.h>

// ── W6 — Aegis ID: the zero-knowledge account client ──────────────────────
//
// Talks to the live aegis-sync Cloudflare worker (the audited API doc is
// packaged with the fix pack: AEGIS-ID-cloudflare-backend.md §5/§6). The
// security model is the backend's own, implemented client-side:
//
//   masterKey  = PBKDF2-SHA256(password, kdf_salt, iterations)   [worker thread]
//   authKey    = HKDF-SHA256(masterKey, info="aegis-auth-v1")
//   verifier   = PBKDF2-SHA256(authKey, "aegis-verifier-v1", 100k)
//   vaultKey   = AES-256-GCM-unwrap(wrapped_vault_key, KEK)
//                KEK = HKDF-SHA256(masterKey, info="aegis-kek-v1")
//
// The password NEVER leaves the device; tokens never touch the disk in
// plaintext (secret-tool when present, session-only otherwise). Sync
// payloads are AES-256-GCM encrypted with the vaultKey.
//
// KDF runs in a QtConcurrent worker — 100k+ iterations never touch the UI
// thread (the "zero-knowledge promises are code, not comments" rule).

class QNetworkReply;

class AegisId : public QObject {
    Q_OBJECT
    // signedOut · working · signedIn · error
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString email READ email NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    // [{id, name, platform, lastSeen, isThis}]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    // The one-time recovery key, shown after account creation only.
    Q_PROPERTY(QString recoveryKey READ recoveryKey NOTIFY recoveryKeyChanged)

public:
    explicit AegisId(QObject *parent = nullptr);

    QString state() const { return m_state; }
    QString email() const { return m_email; }
    QString statusText() const { return m_statusText; }
    QVariantList devices() const { return m_devices; }
    QString recoveryKey() const { return m_recoveryKey; }

    Q_INVOKABLE void signIn(const QString &email, const QString &password);
    Q_INVOKABLE void registerAccount(const QString &email,
                                     const QString &password);
    Q_INVOKABLE void signOut();
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void revokeDevice(const QString &deviceId);
    // Pushes the live prefs (desktop.accent, desktop.wallpaper,
    // files.prefs) as vault-encrypted "setting" items, then re-pulls.
    Q_INVOKABLE void syncNow();
    Q_PROPERTY(bool signedIn READ signedIn NOTIFY stateChanged)
    Q_INVOKABLE bool signedIn() const
    {
        return m_state == QStringLiteral("signedIn");
    }

signals:
    void stateChanged();
    void devicesChanged();
    void recoveryKeyChanged();
    // A pulled setting item decrypted and ready — QML routes desktop.* into
    // Util (accent/wallpaper), files.prefs into Files.
    void syncApplied(const QString &key, const QString &jsonValue);
    void syncFinished(bool ok, const QString &message);

private:
    // ── crypto (OpenSSL, worker-thread safe) ─────────────────────────────
    static QByteArray pbkdf2(const QByteArray &password,
                             const QByteArray &salt, int iterations);
    static QByteArray hkdfSha256(const QByteArray &ikm,
                                 const QByteArray &info, int length = 32);
    static QByteArray sha256(const QByteArray &data);
    // AES-256-GCM — tag appended; returns empty on failure.
    static QByteArray aesGcmEncrypt(const QByteArray &key,
                                    const QByteArray &plaintext,
                                    QByteArray *nonceOut);
    static QByteArray aesGcmDecrypt(const QByteArray &key,
                                    const QByteArray &ciphertext,
                                    const QByteArray &nonce);

    // ── identity & token plumbing ────────────────────────────────────────
    QString deviceId() const;
    QString deviceName() const;
    void persistTokens(const QString &refreshToken);
    QString loadTokens();
    void clearTokens();

    // ── HTTP ─────────────────────────────────────────────────────────────
    void post(const QString &path, const QJsonObject &body, bool authed,
              int attempt = 0);
    void get(const QString &path, bool authed, int attempt = 0);
    void handleReply(QNetworkReply *reply, const QString &kind, int attempt);
    void onAuthSuccess(const QJsonObject &payload);
    void beginDerive(const QString &email, const QString &password,
                     const QByteArray &salt, int iterations);
    void finishLogin(const QString &email, const QByteArray &verifier);

    // ── sync ─────────────────────────────────────────────────────────────
    void pullSync(int fromCursor);
    void pushItem(const QString &itemKey, const QString &jsonValue);
    void pushRecoveryBackup();
    QString decryptVaultValue(const QByteArray &ciphertext,
                              const QByteArray &nonce);
    QVariantMap syncState() const;
    void saveSyncState(const QVariantMap &state);

    void setState(const QString &state, const QString &status = QString());

    QString m_baseUrl;
    QString m_state = QStringLiteral("signedOut");
    QString m_email;
    QString m_statusText = QStringLiteral("Local account · sync off");
    QString m_recoveryKey;
    QVariantList m_devices;

    // secrets live in memory only; the refresh token additionally goes to
    // the secret service (never plaintext on disk)
    QByteArray m_masterKey; // vault-key unwrap only, this session
    QByteArray m_vaultKey;  // sync payload encryption
    QString m_accessToken;
    QString m_refreshToken;
    QString m_deviceId;
    QString m_pendingEmail;
    QString m_pendingPassword;
    QByteArray m_pendingVerifier; // base64 of the derived verifier
    QJsonObject m_user;

    QNetworkAccessManager *m_net = nullptr;
};
