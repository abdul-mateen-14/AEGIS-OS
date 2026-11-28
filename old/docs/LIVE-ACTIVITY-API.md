# Live Activity API — the Dynamic Island's publishing interface

The Dynamic Island (§2.4) renders exactly what applications publish. It
never hosts applets and never invents content: an activity is a data row
(one geometry record in `Tokens.islandStates`) plus one content renderer
in `shell/src/qml/Island.qml`.

## Session bus interface

**Service** `org.aegis.Island` · **Path** `/org/aegis/Island`

| Member | Signature | Meaning |
| --- | --- | --- |
| `PublishActivity` | `s id, s kind, a{sv} data` | start or update an activity |
| `EndActivity` | `s id` | retire it |
| `activityStarted` | signal `s id, s kind` | the island morphs |
| `activityEnded` | signal `s id, s kind` | back to idle / next in stack |
| `activityAction` | signal `s id, s action` | island buttons answer here (`accept`/`decline`/`tap`) |

## Priority stack (Table 5b — fixed)

`call` > `aegisId` > `timer` > `media` > `charging` > `generic`

The top two render — as the **split capsule** (two lobes 8 px apart,
breathing as one wave). Two lobes is the ceiling; everything else queues.
`charging` is shell-owned: published automatically on the AC transition
and retired 6 s after the last battery refresh.

## Kinds and their data keys

| Kind | Island geometry | Data keys (all optional) |
| --- | --- | --- |
| `media` | 356 × 96, r 32 — Now Playing | `title`, `artist`, `artColor1`, `artColor2` |
| `call` | 300 × 64, r 32 — incoming call | `caller`, `initials` (buttons emit `activityAction` with `accept`/`decline`) |
| `timer` | 200 × 56, r 28 | `label`, `remaining` (`"12:34"`) |
| `charging` | 216 × 32, r 16 | `percent`, `minutes` |
| `aegisId` | 200 × 56, r 28 | `message` (`"Unlocked"`) |
| `generic` | 300 × 56, r 28 | `title`, `subtitle` |

Colors are strings (`"#5A9BFF"`). Every key is optional — the island
falls back to a sensible default per kind.

## Notifications

The shell owns `org.freedesktop.Notifications` inside the Aegis session
(no other daemon runs), so every standard notification becomes an Aegis
banner: 356 × 84, stack ≤ 3, auto-out 5 s with a hairline progress
track, hover pauses, click invokes the first action. Do Not Disturb (the
fifth Control Center tile) queues silently.

The `dnd` state is exposed on the shell singleton:
`QDBusProperty org.aegis.Island /org/aegis/Island dnd` is settable via
Control Center only — apps read it through `Activity.dnd` if embedded in
the shell process, otherwise they simply don't see banners while it's on.

## Trying it from a terminal

```sh
# a Now Playing card
aegis-activity publish demo media \
    title="Aurora Drift" artist="Aegis Sound" \
    artColor1="#5A9BFF" artColor2="#1E3E8C"

# …island morphs; end it
aegis-activity end demo

# a call with real accept/decline buttons
aegis-activity publish call call caller="Alex Mercer" initials=AM

# a notification banner
aegis-activity notify "Backup finished" "6 photos synced to OS Cloud"
```

Raw DBus (no helper):

```sh
gdbus call --session --dest org.aegis.Island \
    --object-path /org/aegis/Island \
    --method org.aegis.Island.PublishActivity \
    demo media "{'title':'Aurora Drift','artist':'Aegis Sound'}"
```

## From C++/Qt apps

```cpp
QDBusMessage m = QDBusMessage::createMethodCall(
    "org.aegis.Island", "/org/aegis/Island",
    "org.aegis.Island", "PublishActivity");
m << QStringLiteral("myapp-download")
  << QStringLiteral("generic")
  << QVariantMap{{"title", "Aegis Backup"},
                 {"subtitle", "Restoring 3 of 12 GB"}};
QDBusConnection::sessionBus().send(m); // fire-and-forget
```

Updates with the same `id` morph in place; `EndActivity` retires.
