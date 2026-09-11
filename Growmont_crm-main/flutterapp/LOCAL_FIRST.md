# Growmont CRM — Local-First Storage

Growmont CRM is local-first on desktop: SQLite is the source of truth for
reads, and every write commits locally before it's pushed to Firestore in
the background. The app is fully usable with no network connection.

This page explains the storage layout, the read/write/sync flow, the
conflict rule, what stays online-only, and how to inspect the local
database — read this first when debugging anything sync-related.

## Storage layout

```
%APPDATA%\Roaming\...\GrowmontCRM\        <- ALL user data (via AppPaths)
  growmont.db
  growmont.backup.<timestamp>.db          (3 most recent kept)

%LOCALAPPDATA%\Programs\GrowmontCRM\      <- install folder ONLY
  growmont_crm.exe, flutter_windows.dll, data\, ...
```

The two directories are never mixed. `AppPaths`
(`lib/core/storage/app_paths.dart`) resolves the first via
`path_provider`'s application-support directory — deliberately **not**
`sqflite_common_ffi`'s default `getDatabasesPath()`, which resolves to
`Directory.current` (the install folder) on desktop and would be wiped by
every in-place update. The installer (`installer/growmont_installer.iss`)
only ever touches the second directory; see its `[UninstallDelete]`
section and `RELEASE.md`'s Data Safety note.

## Data flow

```
        UI (unchanged — screens call apiServiceProvider as before)
                │
                ▼
        CrmRepository  extends FirestoreService
         │  reads: local only          │ writes: local first, then queued
         ▼                             ▼
    LocalStore (SQLite)  ◄──────  SyncEngine  ◄──────► Firestore
      documents                   push outbox
      sync_pending (outbox)       pull snapshots
      sync_meta                   pre-pull backup
```

- **Reads** (`lib/core/local/crm_repository.dart`) never touch the network —
  they query `LocalStore.all()` / `.byId()` and rebuild the existing model
  classes (`Employee.fromJson`, `Sale.fromJson`, ...) from the stored JSON.
- **Writes** insert/update the local row (marking it `dirty = 1`), append an
  outbox entry in `sync_pending`, and return immediately — the UI never
  waits on the network. `PayloadNormalizer`
  (`lib/core/local/payload_normalizer.dart`) applies the same field rules
  (rupees→paise, `sales_rep`→`sales_rep_id`, etc.) `FirestoreService` used
  to apply inline, so a locally-written document matches what the server
  would have stored.
- **Doc IDs are generated client-side** (`firestore.collection(c).doc().id`)
  and work with no network, so creates work fully offline — there is no
  temporary-ID scheme and no ID remapping to reconcile later.
- **Pull**: `SyncEngine` (`lib/core/local/sync_engine.dart`) attaches a live
  `snapshots()` listener per collection. Every incoming doc is written via
  `LocalStore.putRemote`, which **skips any row with `dirty = 1`** — an
  unpushed local edit always wins over a pull until it's been confirmed
  pushed. After a server-confirmed (non-cache) snapshot,
  `LocalStore.reconcilePull` hard-deletes local rows that are clean,
  previously synced, and missing from the snapshot (deleted elsewhere) —
  but never a dirty row or a never-synced (offline-created) row.
- **Push**: `SyncEngine.drainOutbox()` walks `sync_pending` in order,
  pushing each op via `toFirestore()` (which restores real `Timestamp`
  values and stamps `updated_at` with `FieldValue.serverTimestamp()`).
  It stops at the first failure rather than burning through the whole
  queue against a dead network, and gives up on an op (recording the
  error) after 5 failed attempts. Triggered on outbox writes, on
  reconnect (`connectivity_plus`), and by the manual "Sync now" button.
- **Deletes** are soft locally (`is_deleted = 1`, hidden from reads) until
  the outbox drains, at which point they become a real Firestore
  `.delete()` and the local row is removed entirely.

## The conflict rule

**A queued local edit always wins over a pull, until it has been pushed.**
This is enforced in exactly one place — `LocalStore.putRemote` /
`.deleteRemote` checking the row's `dirty` flag — and is the single most
important invariant in the sync design. If a doc is edited on two devices
while one is offline, the offline device's edit is not overwritten by the
online device's write; it simply waits in the outbox and overwrites the
server once it reconnects (last-write-wins from the offline device's
perspective). There is no merge and no conflict UI.

## What stays online-only

These call Cloud Functions or Firebase Auth directly and are **not**
routed through the local store — they require a live connection and fail
outright (not silently) if offline:

- `provisionPendingEmployee`, `reviewEmployee`, `createEmployee`,
  `deleteEmployee` — admin/self-signup flows with server-side custom-claim
  logic that can't run offline.
- `changePassword` — Firebase Auth reauthentication.
- `streamPendingReview` — the admin review queue stays live rather than
  cached, since it's inherently a "what needs my attention right now"
  view.

Everything else (clients, sales, interactions, reminders, and
`updateEmployee`) is fully local-first.

## Inspecting `growmont.db`

The file lives at the path shown by Profile → System → Data Storage (or
resolve it yourself via `AppPaths.resolveStorageInfo()`). It's a normal
SQLite database — open it with any SQLite browser. Three tables:

- `documents` — one row per Firestore doc, keyed by `(collection, doc_id)`.
  `payload` is the JSON blob; `dirty`/`synced_at`/`is_deleted` drive the
  sync logic above.
- `sync_pending` — the outbox. `attempts`/`last_error` show why a push is
  stuck.
- `sync_meta` — reserved for future bookkeeping (currently unused).

## Backups

`LocalDatabase.createPreSyncBackup()` copies `growmont.db` to
`growmont.backup.<ISO-timestamp>.db` in the same folder once per app
session, before the first pull. The 3 most recent backups are kept
(sorted by filename, which sorts chronologically since the timestamp is
ISO-ordered); older ones are pruned automatically. A backup failure is
logged and swallowed — it must never block startup or sync.
