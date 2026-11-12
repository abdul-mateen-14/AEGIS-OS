#include "aegisid.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFutureWatcher>
#include <QHostInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUuid>
#include <QVariantMap>
#include <QtConcurrent/QtConcurrent>

#include <utility>
#include <vector>

#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <openssl/sha.h>

// ── lifecycle ─────────────────────────────────────────────────────────────

AegisId::AegisId(QObject *parent)
    : QObject(parent)
{
    m_baseUrl = qEnvironmentVariable("AEGIS_SYNC_URL",
                                     QStringLiteral("https://aegis-sync"
                                                    ".abdulmateen14"
                                                    ".workers.dev"));
    m_deviceId = deviceId();
    m_net = new QNetworkAccessManager(this);

    // silent restore: the secret service holds the rotating refresh token
    const QString stored = loadTokens();
    if (!stored.isEmpty() && !m_deviceId.isEmpty()) {
        setState(QStringLiteral("working"),
                 QStringLiteral("Restoring session…"));
        m_refreshToken = stored;
        QJsonObject body{{QStringLiteral("refresh_token"), stored}};
        post(QStringLiteral("/v1/auth/refresh"), body, false);
    }
}

void AegisId::setState(const QString &state, const QString &status)
{
    if (!status.isEmpty())
        m_statusText = status;
    m_state = state;
    emit stateChanged();
}

// W34 — the classification table behind the form's error line: transport
// failure, service trouble, and server-rejected each get their own
// sentence; anything else is the server's message or the caller's
// fallback.
QString AegisId::classifyError(int status, const QString &errText,
                               const QString &fallback)
{
    if (status == 0)
        return QStringLiteral(
            "Can't reach the Aegis sync service — check the network, then retry");
    if (status == 401 || status == 403)
        return QStringLiteral("Wrong email or password");
    if (status >= 500)
        return QStringLiteral(
            "Service error — the sync backend is having trouble, try again later");
    return errText.isEmpty() ? fallback : errText;
}

// ── crypto primitives (static, worker-thread safe) ────────────────────────

QByteArray AegisId::sha256(const QByteArray &data)
{
    QByteArray out(SHA256_DIGEST_LENGTH, Qt::Uninitialized);
    SHA256(reinterpret_cast<const unsigned char *>(data.constData()),
           static_cast<size_t>(data.size()),
           reinterpret_cast<unsigned char *>(out.data()));
    return out;
}

// PBKDF2-SHA256 — the backend's KDF (PKCS5_PBKDF2_HMAC, per the API doc).
QByteArray AegisId::pbkdf2(const QByteArray &password,
                           const QByteArray &salt, int iterations)
{
    QByteArray out(32, Qt::Uninitialized);
    PKCS5_PBKDF2_HMAC(password.constData(), password.size(),
                      reinterpret_cast<const unsigned char *>(salt.constData()),
                      salt.size(), iterations, EVP_sha256(), out.size(),
                      reinterpret_cast<unsigned char *>(out.data()));
    return out;
}

// RFC 5869 HKDF-SHA256: extract (HMAC with zero salt) + expand.
QByteArray AegisId::hkdfSha256(const QByteArray &ikm,
                               const QByteArray &info, int length)
{
    const QByteArray zeroSalt(32, '\x00');
    unsigned char prk[EVP_MAX_MD_SIZE];
    unsigned int prkLen = 0;
    HMAC(EVP_sha256(), zeroSalt.constData(), zeroSalt.size(),
         reinterpret_cast<const unsigned char *>(ikm.constData()),
         static_cast<size_t>(ikm.size()), prk, &prkLen);

    QByteArray out;
    QByteArray t;
    unsigned char counter = 1;
    while (out.size() < length) {
        QByteArray input = t + info;
        input.append(char(counter));
        unsigned char block[EVP_MAX_MD_SIZE];
        unsigned int blockLen = 0;
        HMAC(EVP_sha256(), prk, int(prkLen),
             reinterpret_cast<const unsigned char *>(input.constData()),
             static_cast<size_t>(input.size()), block, &blockLen);
        t = QByteArray(reinterpret_cast<char *>(block), int(blockLen));
        out += t;
        counter++;
    }
    return out.left(length);
}

// AES-256-GCM with the 16-byte tag appended; 12-byte nonce in/out.
QByteArray AegisId::aesGcmEncrypt(const QByteArray &key,
                                  const QByteArray &plaintext,
                                  QByteArray *nonceOut)
{
    QByteArray nonce(12, Qt::Uninitialized);
    RAND_bytes(reinterpret_cast<unsigned char *>(nonce.data()), 12);

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    bool ok = ctx != nullptr;
    if (ok)
        ok = EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr,
                                reinterpret_cast<const unsigned char *>(
                                    key.constData()),
                                reinterpret_cast<const unsigned char *>(
                                    nonce.constData())) == 1;
    QByteArray out;
    if (ok) {
        out.resize(plaintext.size() + 16);
        int len = 0;
        int total = 0;
        ok = EVP_EncryptUpdate(ctx,
                               reinterpret_cast<unsigned char *>(out.data()),
                               &len,
                               reinterpret_cast<const unsigned char *>(
                                   plaintext.constData()),
                               plaintext.size()) == 1;
        if (ok) {
            total = len;
            ok = EVP_EncryptFinal_ex(
                ctx, reinterpret_cast<unsigned char *>(out.data()) + total,
                &len) == 1;
            if (ok) {
                total += len;
                unsigned char tag[16];
                EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
                out.resize(total);
                out.append(reinterpret_cast<char *>(tag), 16);
                if (nonceOut)
                    *nonceOut = nonce;
            }
        }
    }
    if (ctx)
        EVP_CIPHER_CTX_free(ctx);
    if (!ok)
        return {};
    return out;
}

QByteArray AegisId::aesGcmDecrypt(const QByteArray &key,
                                  const QByteArray &ciphertext,
                                  const QByteArray &nonce)
{
    if (ciphertext.size() <= 16 || nonce.size() != 12)
        return {};
    const QByteArray body = ciphertext.left(ciphertext.size() - 16);
    const QByteArray tag = ciphertext.right(16);

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    bool ok = ctx != nullptr;
    if (ok)
        ok = EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr,
                                reinterpret_cast<const unsigned char *>(
                                    key.constData()),
                                reinterpret_cast<const unsigned char *>(
                                    nonce.constData())) == 1;
    QByteArray out;
    if (ok) {
        out.resize(body.size());
        int len = 0;
        int total = 0;
        ok = EVP_DecryptUpdate(ctx,
                               reinterpret_cast<unsigned char *>(out.data()),
                               &len,
                               reinterpret_cast<const unsigned char *>(
                                   body.constData()),
                               body.size()) == 1;
        if (ok) {
            total = len;
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16,
                                const_cast<char *>(tag.constData()));
            ok = EVP_DecryptFinal_ex(
                ctx, reinterpret_cast<unsigned char *>(out.data()) + total,
                &len) == 1;
            if (ok)
                out.resize(total);
        }
    }
    if (ctx)
        EVP_CIPHER_CTX_free(ctx);
    if (!ok)
        return {}; // auth failure — wrong key or tampered payload
    return out;
}

// ── identity & token plumbing ─────────────────────────────────────────────

QString AegisId::deviceId() const
{
    const QString base = QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation);
    const QString path = base + QStringLiteral("/aegis/device-id");
    QFile file(path);
    if (file.open(QIODevice::ReadOnly)) {
        const QString id = QString::fromUtf8(file.readAll()).trimmed();
        if (!id.isEmpty())
            return id;
    }
    // one UUID per install — the "signed-in devices" pane is truthful
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QDir(base).mkpath(QStringLiteral("aegis"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(id.toUtf8());
    return id;
}

QString AegisId::deviceName() const
{
    return QStringLiteral("AEGIS-OS ") + QHostInfo::localHostName();
}

// Refresh token → the secret service via secret-tool (libsecret →
// kwallet/ksecretd). If the tool or a backend is missing, tokens stay in
// memory only — NEVER plaintext on disk. Rotation is inherent: presenting a
// refresh token mints a new pair, so the stored blob is rewritten on every
// restore.
void AegisId::persistTokens(const QString &refreshToken)
{
    const QString tool = QStandardPaths::findExecutable(
        QStringLiteral("secret-tool"), {QStringLiteral("/usr/bin")});
    if (tool.isEmpty())
        return; // session-only (honest fallback)
    QProcess p;
    p.start(tool, {QStringLiteral("store"),
                   QStringLiteral("--label=Aegis ID refresh token"),
                   QStringLiteral("aegis"), QStringLiteral("refresh")});
    if (!p.waitForStarted(2000))
        return;
    p.write(refreshToken.toUtf8());
    p.closeWriteChannel();
    p.waitForFinished(3000);
}

QString AegisId::loadTokens()
{
    const QString tool = QStandardPaths::findExecutable(
        QStringLiteral("secret-tool"), {QStringLiteral("/usr/bin")});
    if (tool.isEmpty())
        return {};
    QProcess p;
    p.start(tool, {QStringLiteral("lookup"), QStringLiteral("aegis"),
                   QStringLiteral("refresh")});
    if (!p.waitForFinished(3000))
        return {};
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}

void AegisId::clearTokens()
{
    const QString tool = QStandardPaths::findExecutable(
        QStringLiteral("secret-tool"), {QStringLiteral("/usr/bin")});
    if (!tool.isEmpty())
        QProcess::startDetached(tool, {QStringLiteral("clear"),
                                       QStringLiteral("aegis"),
                                       QStringLiteral("refresh")});
    m_accessToken.clear();
    m_refreshToken.clear();
    m_vaultKey.clear();
    m_masterKey.clear();
}

// ── HTTP ──────────────────────────────────────────────────────────────────

void AegisId::post(const QString &path, const QJsonObject &body, bool authed,
                   int attempt)
{
    QNetworkRequest req{QUrl(m_baseUrl + path)};
    req.setHeader(QNetworkRequest::ContentTypeHeader,
                  QStringLiteral("application/json"));
    if (authed && !m_accessToken.isEmpty())
        req.setRawHeader(QByteArrayLiteral("Authorization"),
                         ("Bearer " + m_accessToken).toUtf8());
    QNetworkReply *reply = m_net->post(req,
                                       QJsonDocument(body).toJson(
                                           QJsonDocument::Compact));
    handleReply(reply, QStringLiteral("POST ") + path, attempt);
}

void AegisId::get(const QString &path, bool authed, int attempt)
{
    QNetworkRequest req{QUrl(m_baseUrl + path)};
    if (authed && !m_accessToken.isEmpty())
        req.setRawHeader(QByteArrayLiteral("Authorization"),
                         ("Bearer " + m_accessToken).toUtf8());
    QNetworkReply *reply = m_net->get(req);
    handleReply(reply, QStringLiteral("GET ") + path, attempt);
}

void AegisId::handleReply(QNetworkReply *reply, const QString &kind,
                          int attempt)
{
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, kind, attempt] {
        reply->deleteLater();
        const QByteArray raw = reply->readAll();
        const int status = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject root = QJsonDocument::fromJson(raw).object();
        const QString errText =
            root.value(QStringLiteral("error")).toObject()
                .value(QStringLiteral("message")).toString();

        // W34 — the backend answered or it did not; both facts outlive
        // this reply and feed the form's state line. Any HTTP status
        // (even 4xx/5xx) means the transport is fine; only a zero status
        // (DNS, no route, timeout, TLS) means unreachable.
        m_backendState = (status == 0) ? QStringLiteral("unreachable")
                                       : QStringLiteral("reachable");
        m_lastAttempt = QDateTime::currentDateTime()
                            .toString(QStringLiteral("HH:mm"));
        emit stateChanged();

        // 401 → refresh once (the token rotates on use), then signed-out.
        if (status == 401 && !m_refreshToken.isEmpty() && attempt == 0) {
            const QString used = m_refreshToken;
            m_refreshToken.clear();
            QJsonObject body{{QStringLiteral("refresh_token"), used}};
            post(QStringLiteral("/v1/auth/refresh"), body, false, 1);
            return;
        }
        if (status == 401) {
            clearTokens();
            m_email.clear();
            m_devices.clear();
            emit devicesChanged();
            setState(QStringLiteral("signedOut"),
                     QStringLiteral("Session expired — signed out"));
            return;
        }

        if (kind == QStringLiteral("GET /v1/auth/kdf-params")) {
            if (status != 200) {
                setState(QStringLiteral("error"),
                         classifyError(status, errText,
                                       QStringLiteral("Account not found")));
                return;
            }
            const QByteArray salt = QByteArray::fromBase64(
                root.value(QStringLiteral("kdf_salt_b64")).toString()
                    .toUtf8());
            const int iterations =
                root.value(QStringLiteral("kdf_iterations")).toInt(100000);
            beginDerive(m_pendingEmail, m_pendingPassword, salt, iterations);
            return;
        }

        if (kind == QStringLiteral("POST /v1/auth/register")) {
            if (status != 200 && status != 201) {
                setState(QStringLiteral("error"),
                         classifyError(status, errText,
                                       QStringLiteral("Registration failed")));
                return;
            }
            // created — now sign in with the verifier we already derived
            m_pendingPassword.clear();
            finishLogin(m_pendingEmail, m_pendingVerifier);
            return;
        }

        if (kind == QStringLiteral("POST /v1/auth/login")
            || kind == QStringLiteral("POST /v1/auth/refresh")) {
            if (status != 200) {
                // W34 — a 4xx here means the verifier did not match; the
                // classifier says "Wrong email or password" (never the
                // generic fallback on the wrong-secret path).
                setState(QStringLiteral("error"),
                         classifyError(status, errText,
                                       QStringLiteral("Sign-in failed")));
                return;
            }
            onAuthSuccess(root);
            return;
        }

        if (kind == QStringLiteral("GET /v1/devices")) {
            if (status != 200)
                return;
            QVariantList devices;
            const QJsonArray rows =
                root.value(QStringLiteral("devices")).toArray();
            for (const auto &v : rows) {
                const QJsonObject d = v.toObject();
                devices.append(QVariantMap{
                    {QStringLiteral("id"),
                     d.value(QStringLiteral("id")).toString()},
                    {QStringLiteral("name"),
                     d.value(QStringLiteral("name")).toString()},
                    {QStringLiteral("platform"),
                     d.value(QStringLiteral("platform")).toString()},
                    {QStringLiteral("lastSeen"),
                     d.value(QStringLiteral("last_seen_at")).toString()},
                    {QStringLiteral("isThis"),
                     d.value(QStringLiteral("id")).toString() == m_deviceId},
                });
            }
            m_devices = devices;
            emit devicesChanged();
            return;
        }

        if (kind.startsWith(QStringLiteral("POST /v1/devices/"))) {
            QTimer::singleShot(400, this, &AegisId::refreshDevices);
            return;
        }

        if (kind == QStringLiteral("GET /v1/sync/cursor")) {
            if (status != 200)
                return;
            pullSync(root.value(QStringLiteral("cursor")).toInt());
            return;
        }

        if (kind.startsWith(QStringLiteral("GET /v1/sync/pull"))) {
            if (status != 200) {
                emit syncFinished(false,
                                  errText.isEmpty()
                                      ? QStringLiteral("pull failed")
                                      : errText);
                return;
            }
            QVariantMap state = syncState();
            const QJsonArray items =
                root.value(QStringLiteral("items")).toArray();
            for (const auto &v : items) {
                const QJsonObject it = v.toObject();
                const QString key =
                    it.value(QStringLiteral("item_key")).toString();
                state.insert(QStringLiteral("cursor"),
                             it.value(QStringLiteral("event_id")).toInt());
                if (it.value(QStringLiteral("deleted")).toBool())
                    continue;
                const QByteArray cipher = QByteArray::fromBase64(
                    it.value(QStringLiteral("ciphertext_b64")).toString()
                        .toUtf8());
                const QByteArray nonce = QByteArray::fromBase64(
                    it.value(QStringLiteral("nonce_b64")).toString().toUtf8());
                const QString json = decryptVaultValue(cipher, nonce);
                if (!json.isEmpty()) {
                    state.insert(key, QJsonObject{
                        {QStringLiteral("version"),
                         it.value(QStringLiteral("version")).toInt()},
                        {QStringLiteral("local"), json}});
                    emit syncApplied(key, json);
                }
            }
            state.insert(QStringLiteral("cursor"),
                         root.value(QStringLiteral("next_cursor")).toInt());
            saveSyncState(state);
            if (root.value(QStringLiteral("has_more")).toBool())
                pullSync(int(state.value(QStringLiteral("cursor")).toInt()));
            else
                emit syncFinished(true, QStringLiteral("synced"));
            return;
        }

        if (kind == QStringLiteral("POST /v1/sync/push")) {
            if (status != 200) {
                emit syncFinished(false,
                                  errText.isEmpty()
                                      ? QStringLiteral("push failed")
                                      : errText);
                // a version conflict or stale token — re-pull to converge
                get(QStringLiteral("/v1/sync/cursor"), true);
                return;
            }
            const QJsonArray results =
                root.value(QStringLiteral("results")).toArray();
            QVariantMap state = syncState();
            for (const auto &v : results) {
                const QJsonObject r = v.toObject();
                const QString key =
                    r.value(QStringLiteral("item_key")).toString();
                const int version =
                    r.value(QStringLiteral("version")).toInt(-1);
                if (version >= 0 && state.contains(key)) {
                    QJsonObject s = state.value(key).toJsonObject();
                    s.insert(QStringLiteral("version"), version);
                    state.insert(key, s);
                }
            }
            saveSyncState(state);
            get(QStringLiteral("/v1/sync/cursor"), true);
            emit syncFinished(true, QStringLiteral("synced"));
            return;
        }
    });
}

// The KDF chain — ALWAYS off the UI thread (100k+ iterations, ~100–600 ms).
// Derives the verifier AND keeps the masterKey in-session (only the vault-key
// unwrap needs it; it lives in process memory, never on disk).
void AegisId::beginDerive(const QString &email, const QString &password,
                          const QByteArray &salt, int iterations)
{
    setState(QStringLiteral("working"), QStringLiteral("Deriving keys…"));
    const QByteArray pass = password.toUtf8();
    auto *watcher = new QFutureWatcher<std::pair<QByteArray, QByteArray>>(this);
    connect(watcher,
            &QFutureWatcher<std::pair<QByteArray, QByteArray>>::finished, this,
            [this, watcher, email] {
        watcher->deleteLater();
        const std::pair<QByteArray, QByteArray> result = watcher->result();
        const QByteArray masterKey = result.first;
        const QByteArray verifier = result.second;
        if (verifier.isEmpty()) {
            setState(QStringLiteral("error"),
                     QStringLiteral("Key derivation failed"));
            return;
        }
        m_masterKey = masterKey;
        finishLogin(email, verifier);
    });
    watcher->setFuture(QtConcurrent::run(
        [pass, salt, iterations]() -> std::pair<QByteArray, QByteArray> {
            // masterKey = PBKDF2-SHA256(password, kdf_salt, iterations)
            const QByteArray masterKey = pbkdf2(pass, salt, iterations);
            // authKey = HKDF-SHA256(masterKey, info="aegis-auth-v1")
            const QByteArray authKey = hkdfSha256(
                masterKey, QByteArrayLiteral("aegis-auth-v1"), 32);
            // verifier = PBKDF2-SHA256(authKey, "aegis-verifier-v1", 100k)
            const QByteArray verifier = pbkdf2(
                authKey, QByteArrayLiteral("aegis-verifier-v1"), 100000);
            return {masterKey, verifier};
        }));
}

void AegisId::finishLogin(const QString &email, const QByteArray &verifier)
{
    setState(QStringLiteral("working"), QStringLiteral("Signing in…"));
    QJsonObject device{
        {QStringLiteral("id"), m_deviceId},
        {QStringLiteral("name"), deviceName()},
        {QStringLiteral("platform"), QStringLiteral("linux")},
    };
    QJsonObject body{
        {QStringLiteral("email"), email.toLower()},
        {QStringLiteral("verifier_b64"),
         QString::fromUtf8(verifier.toBase64())},
        {QStringLiteral("device"), device},
    };
    post(QStringLiteral("/v1/auth/login"), body, false);
}

// login / refresh success — tokens + vault key + user block
void AegisId::onAuthSuccess(const QJsonObject &payload)
{
    m_accessToken = payload.value(QStringLiteral("access_token")).toString();
    const QString refresh =
        payload.value(QStringLiteral("refresh_token")).toString();
    m_user = payload.value(QStringLiteral("user")).toObject();
    if (!refresh.isEmpty())
        m_refreshToken = refresh;
    m_email = m_user.value(QStringLiteral("email")).toString();
    setState(QStringLiteral("signedIn"), m_email);

    // unwrap the vault key: KEK = HKDF(masterKey, "aegis-kek-v1"). Only the
    // session that knows the password can do this (login/register flows set
    // m_masterKey; a silent token restore cannot — sync payloads then stay
    // opaque until the next password sign-in).
    if (!m_masterKey.isEmpty()) {
        const QByteArray kek = hkdfSha256(m_masterKey,
                                          QByteArrayLiteral("aegis-kek-v1"),
                                          32);
        const QByteArray wrapped = QByteArray::fromBase64(
            m_user.value(QStringLiteral("wrapped_vault_key_b64")).toString()
                .toUtf8());
        const QByteArray nonce = QByteArray::fromBase64(
            m_user.value(QStringLiteral("vault_nonce_b64")).toString()
                .toUtf8());
        m_vaultKey = aesGcmDecrypt(kek, wrapped, nonce);
    }

    if (!m_refreshToken.isEmpty())
        persistTokens(m_refreshToken);

    refreshDevices();
    if (!m_vaultKey.isEmpty()) {
        // first login on a fresh account: ride the recovery-vault backup on
        // the sync log so a future backend recovery flow has the material
        if (!m_recoveryKey.isEmpty())
            pushRecoveryBackup();
        pullSync(int(syncState().value(QStringLiteral("cursor")).toInt()));
    }
}

// ── public QML surface ────────────────────────────────────────────────────

void AegisId::signIn(const QString &email, const QString &password)
{
    if (email.isEmpty() || password.isEmpty()) {
        setState(QStringLiteral("error"),
                 QStringLiteral("Email and password are required"));
        return;
    }
    m_pendingEmail = email.toLower();
    m_pendingPassword = password;
    setState(QStringLiteral("working"),
             QStringLiteral("Fetching kdf params…"));
    // kdf-params first — the salt is public and email-keyed
    get(QStringLiteral("/v1/auth/kdf-params?email=")
        + QString::fromUtf8(QUrl::toPercentEncoding(m_pendingEmail)), false);
}

void AegisId::registerAccount(const QString &email, const QString &password)
{
    if (email.isEmpty() || password.isEmpty()) {
        setState(QStringLiteral("error"),
                 QStringLiteral("Email and password are required"));
        return;
    }
    m_pendingEmail = email.toLower();
    m_pendingPassword = password;
    setState(QStringLiteral("working"), QStringLiteral("Creating account…"));

    // fresh vault: 16-byte salt, 100k iterations, 32-byte vault key
    QByteArray salt(16, Qt::Uninitialized);
    RAND_bytes(reinterpret_cast<unsigned char *>(salt.data()), 16);
    QByteArray vaultKey(32, Qt::Uninitialized);
    RAND_bytes(reinterpret_cast<unsigned char *>(vaultKey.data()), 32);

    auto *watcher = new QFutureWatcher<QJsonObject>(this);
    connect(watcher, &QFutureWatcher<QJsonObject>::finished, this,
            [this, watcher, email]() {
        watcher->deleteLater();
        const QJsonObject derived = watcher->result();
        if (derived.isEmpty()) {
            setState(QStringLiteral("error"),
                     QStringLiteral("Key derivation failed"));
            return;
        }
        m_masterKey = QByteArray::fromBase64(
            derived.value(QStringLiteral("masterKey_b64")).toString().toUtf8());
        // raw verifier bytes — finishLogin() re-encodes for the login body
        m_pendingVerifier = QByteArray::fromBase64(
            derived.value(QStringLiteral("verifier_b64")).toString().toUtf8());
        m_recoveryKey = derived.value(QStringLiteral("recoveryKey")).toString();
        emit recoveryKeyChanged();

        QJsonObject body{
            {QStringLiteral("email"), email.toLower()},
            {QStringLiteral("kdf_salt_b64"),
             derived.value(QStringLiteral("salt_b64")).toString()},
            {QStringLiteral("kdf"),
             QJsonObject{{QStringLiteral("algo"),
                          QStringLiteral("PBKDF2-SHA256")},
                         {QStringLiteral("iterations"), 100000}}},
            {QStringLiteral("verifier_b64"),
             QString::fromUtf8(m_pendingVerifier.toBase64())},
            {QStringLiteral("wrapped_vault_key_b64"),
             derived.value(QStringLiteral("wrapped_b64")).toString()},
            {QStringLiteral("vault_nonce_b64"),
             derived.value(QStringLiteral("nonce_b64")).toString()},
        };
        post(QStringLiteral("/v1/auth/register"), body, false);
    });

    const QByteArray pass = password.toUtf8();
    watcher->setFuture(QtConcurrent::run([pass, salt, vaultKey]() -> QJsonObject {
        const QByteArray masterKey = pbkdf2(pass, salt, 100000);
        const QByteArray authKey = hkdfSha256(masterKey,
                                              QByteArrayLiteral(
                                                  "aegis-auth-v1"), 32);
        const QByteArray verifier = pbkdf2(authKey,
                                           QByteArrayLiteral(
                                               "aegis-verifier-v1"), 100000);
        // wrap the vault key with KEK = HKDF(masterKey, "aegis-kek-v1")
        const QByteArray kek = hkdfSha256(masterKey,
                                          QByteArrayLiteral("aegis-kek-v1"),
                                          32);
        QByteArray nonce;
        const QByteArray wrapped = aesGcmEncrypt(kek, vaultKey, &nonce);

        // one-time recovery key — 96 bits from a 32-char alphabet, grouped
        // for reading. The backend has no recovery flow yet (audited gap
        // §7.1); the key is shown once and its wrapped-vault backup rides
        // the sync log (aegis.recovery-vault) for a future flow.
        QByteArray recoveryRaw(12, Qt::Uninitialized);
        RAND_bytes(reinterpret_cast<unsigned char *>(recoveryRaw.data()), 12);
        const QString alphabet = QStringLiteral("ABCDEFGHJKMNPQRSTUVWXYZ"
                                                "23456789");
        QString recovery;
        for (int i = 0; i < recoveryRaw.size(); ++i) {
            quint8 b = quint8(recoveryRaw.at(i));
            recovery += alphabet.at(int(b % quint8(alphabet.size())));
            if ((i + 1) % 4 == 0 && i + 1 < recoveryRaw.size())
                recovery += QLatin1Char('-');
        }

        return QJsonObject{
            {QStringLiteral("masterKey_b64"),
             QString::fromUtf8(masterKey.toBase64())},
            {QStringLiteral("salt_b64"),
             QString::fromUtf8(salt.toBase64())},
            {QStringLiteral("verifier_b64"),
             QString::fromUtf8(verifier.toBase64())},
            {QStringLiteral("wrapped_b64"),
             QString::fromUtf8(wrapped.toBase64())},
            {QStringLiteral("nonce_b64"),
             QString::fromUtf8(nonce.toBase64())},
            {QStringLiteral("recoveryKey"), recovery},
        };
    }));
}

// vault backup wrapped with the recovery key (HKDF over its UTF-8 bytes) —
// pushed once, right after the first login of the account that created it.
void AegisId::pushRecoveryBackup()
{
    if (m_vaultKey.isEmpty() || m_recoveryKey.isEmpty())
        return;
    const QByteArray recoveryKek = hkdfSha256(m_recoveryKey.toUtf8(),
                                              QByteArrayLiteral(
                                                  "aegis-kek-v1"), 32);
    QByteArray nonce;
    const QByteArray wrapped = aesGcmEncrypt(recoveryKek, m_vaultKey, &nonce);
    if (wrapped.isEmpty())
        return;
    const QString json = QString::fromUtf8(
        QJsonDocument(QJsonObject{
            {QStringLiteral("recovery"),
             QStringLiteral("aegis.recovery-vault/v1")},
            {QStringLiteral("wrapped_vault_key_b64"),
             QString::fromUtf8(wrapped.toBase64())},
            {QStringLiteral("nonce_b64"),
             QString::fromUtf8(nonce.toBase64())},
        }).toJson(QJsonDocument::Compact));
    pushItem(QStringLiteral("aegis.recovery-vault"), json);
}

void AegisId::signOut()
{
    // kill this session server-side, then forget everything local
    post(QStringLiteral("/v1/auth/logout"), QJsonObject{}, true);
    clearTokens();
    m_email.clear();
    m_user = QJsonObject();
    m_devices.clear();
    emit devicesChanged();
    setState(QStringLiteral("signedOut"),
             QStringLiteral("Local account · sync off"));
}

void AegisId::refreshDevices()
{
    get(QStringLiteral("/v1/devices"), true);
}

void AegisId::revokeDevice(const QString &deviceId)
{
    if (deviceId == m_deviceId)
        return; // never revoke the device you are using
    post(QStringLiteral("/v1/devices/") + deviceId
         + QStringLiteral("/revoke"), QJsonObject{}, true);
}

// ── sync (item_type "setting", vault-encrypted, ≤512 KB) ─────────────────

QVariantMap AegisId::syncState() const
{
    const QString base = QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation);
    QFile f(base + QStringLiteral("/aegis/sync-state.json"));
    if (!f.open(QIODevice::ReadOnly))
        return {{QStringLiteral("cursor"), 0}};
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}

void AegisId::saveSyncState(const QVariantMap &state)
{
    const QString base = QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation);
    QDir(base).mkpath(QStringLiteral("aegis"));
    QFile f(base + QStringLiteral("/aegis/sync-state.json"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(QJsonObject::fromVariantMap(state))
                    .toJson(QJsonDocument::Compact));
}

QString AegisId::decryptVaultValue(const QByteArray &ciphertext,
                                   const QByteArray &nonce)
{
    const QByteArray plain = aesGcmDecrypt(m_vaultKey, ciphertext, nonce);
    return plain.isEmpty() ? QString() : QString::fromUtf8(plain);
}

void AegisId::pullSync(int fromCursor)
{
    get(QStringLiteral("/v1/sync/pull?cursor=")
        + QString::number(fromCursor), true);
}

void AegisId::pushItem(const QString &itemKey, const QString &jsonValue)
{
    if (m_vaultKey.isEmpty())
        return; // encrypted sync needs the vault key from a password login
    QVariantMap state = syncState();
    const QJsonObject prev = state.value(itemKey).toJsonObject();
    QByteArray nonce;
    const QByteArray cipher =
        aesGcmEncrypt(m_vaultKey, jsonValue.toUtf8(), &nonce);
    if (cipher.isEmpty())
        return;

    QJsonObject item{
        {QStringLiteral("item_type"), QStringLiteral("setting")},
        {QStringLiteral("item_key"), itemKey},
        {QStringLiteral("base_version"),
         prev.value(QStringLiteral("version")).toInt(0)},
        {QStringLiteral("ciphertext_b64"),
         QString::fromUtf8(cipher.toBase64())},
        {QStringLiteral("nonce_b64"),
         QString::fromUtf8(nonce.toBase64())},
        {QStringLiteral("deleted"), false},
    };
    QJsonObject body{{QStringLiteral("items"), QJsonArray{item}}};
    post(QStringLiteral("/v1/sync/push"), body, true);
    // remember the plaintext + version locally so the next push is optimistic
    state.insert(itemKey, QJsonObject{
        {QStringLiteral("version"),
         prev.value(QStringLiteral("version")).toInt(0)},
        {QStringLiteral("local"), jsonValue}});
    saveSyncState(state);
}

void AegisId::syncNow()
{
    if (!signedIn() || m_vaultKey.isEmpty()) {
        emit syncFinished(false,
                          QStringLiteral("Signed in without the vault key — "
                                         "sign in once with the password"));
        return;
    }
    // desktop.accent (one JSON setting, small by design)
    {
        QSettings tokens(QStandardPaths::writableLocation(
                             QStandardPaths::GenericConfigLocation)
                             + QStringLiteral("/aegis/tokens.conf"),
                         QSettings::IniFormat);
        const QString accent =
            tokens.value(QStringLiteral("accent"),
                         QStringLiteral("#3E8BFF")).toString();
        pushItem(QStringLiteral("desktop.accent"),
                 QString::fromUtf8(QJsonDocument(QJsonObject{
                     {QStringLiteral("accent"), accent}})
                     .toJson(QJsonDocument::Compact)));
    }
    // desktop.wallpaper — the selection (path), never the image (≤512 KB)
    {
        const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR",
                                                     QStringLiteral("/tmp"));
        QFile f(runtime + QStringLiteral("/aegis/prefs.json"));
        if (f.open(QIODevice::ReadOnly)) {
            const QString wallpaper =
                QJsonDocument::fromJson(f.readAll())
                    .object().value(QStringLiteral("wallpaper")).toString();
            if (!wallpaper.isEmpty())
                pushItem(QStringLiteral("desktop.wallpaper"),
                         QString::fromUtf8(QJsonDocument(QJsonObject{
                             {QStringLiteral("wallpaper"), wallpaper}})
                             .toJson(QJsonDocument::Compact)));
        }
    }
    // files.prefs (grid + sort)
    {
        QFile f(QStandardPaths::writableLocation(
                    QStandardPaths::GenericConfigLocation)
                + QStringLiteral("/aegis/files-prefs.json"));
        if (f.open(QIODevice::ReadOnly)) {
            const QString json = QString::fromUtf8(f.readAll());
            if (!json.isEmpty())
                pushItem(QStringLiteral("files.prefs"), json);
        }
    }
    get(QStringLiteral("/v1/sync/cursor"), true);
}
