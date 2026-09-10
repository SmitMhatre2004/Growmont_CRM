# Growmont CRM — Local-First Storage + Self-Update + Installer

**Implementation plan. Written for an executing agent (Sonnet, medium effort).**

Port of the CruSam desktop patterns into the Growmont Flutter app.
Source of the patterns: `C:\Soham\Kamachya_Goshti\CruSam\CruSam\` — read those
files when this plan says "port from".

---

## 0. Read this first (rules for the executor)

1. **The Django `server/` directory is dead.** Do not read it, do not import
   from it, do not touch it. The only app is `flutterapp/`. The backend is
   Firebase (Firestore + Auth + Functions + Storage).
2. **Work phase by phase, in order.** Each phase ends with an explicit
   *Acceptance* block. Do not start phase N+1 until phase N's acceptance
   passes. Commit at the end of each phase with the message given.
3. **`flutter analyze` must be clean (0 errors) at the end of every phase.**
   Warnings/infos that already existed before you started are acceptable;
   new ones are not.
4. **Never change existing call sites unless a phase explicitly tells you to.**
   The whole design of Phase 6 is to avoid touching the 47 existing
   `apiServiceProvider` / `firestoreServiceProvider` call sites. If you find
   yourself editing a screen file outside Phase 8/9, stop — you took a wrong turn.
5. **Do not invent file paths.** Every path in this plan is real and verified.
   If a path in this plan doesn't exist when you go to edit it, stop and report
   rather than creating something similar-looking elsewhere.
6. **Never write user data into the install folder.** This is the single
   most important invariant in the whole plan — see §1.
7. When a phase says "port from `<CruSam file>`", open that file, copy it, and
   apply only the listed edits. Do not rewrite it from scratch.

### Verified repo facts (do not re-derive these)

| Fact | Value |
|---|---|
| Flutter app root | `Growmont_crm-main/flutterapp` |
| Package name | `growmont_crm` |
| Current version | `1.0.0+1` in `flutterapp/pubspec.yaml` |
| Windows binary name | `growmont_crm.exe` (`windows/CMakeLists.txt:7`) |
| Windows `Runner.rc` | already wired to `FLUTTER_VERSION_*` (lines 63–77) — **no edit needed** |
| App icon | `flutterapp/windows/runner/resources/app_icon.ico` |
| State management | Riverpod (`flutter_riverpod: ^2.6.1`) |
| Data layer | `flutterapp/lib/core/firebase/firestore_service.dart` (595 lines) |
| Providers | `flutterapp/lib/core/providers.dart` (`firestoreServiceProvider`, `apiServiceProvider`) |
| Theme | `flutterapp/lib/core/theme/app_theme.dart` (`AppColors`, `AppTypography`) which re-exports `design_tokens.dart` (`AppSpacing`, `AppRadius`, `AppSizing`, `AppLayout`) |
| Profile screen | `flutterapp/lib/features/profile/profile_screen.dart` (1035 lines), tabs enum `ProfileTab { sales, interactions, reminders }` at line 18 |
| Git remote | `https://github.com/SmitMhatre2004/Growmont_CRM.git` |
| Firestore collections | `employees`, `clients`, `sales`, `interactions`, `reminders` |

### Decisions already made — do not revisit

- **Local-first depth: full offline.** SQLite is the read source of truth;
  writes commit locally first and drain to Firestore through an outbox.
- **Releases go to a separate public release repo**, not the source repo.
  Owner/name is a `TODO(release-repo)` constant you will leave for the user
  to fill in — see Phase 10.
- **No `updater.exe`.** CruSam still builds one for legacy reasons but its
  current update path (`UpdateService.launchUpdaterAndExit`) runs the Inno
  Setup installer directly with `/VERYSILENT`. Growmont skips the helper exe
  entirely. Do not port `CruSam/updater/`.

---

## 1. Architecture in one page

### Storage (the bug being prevented)

`sqflite_common_ffi`'s `getDatabasesPath()` defaults to `Directory.current`,
which for a launched `.exe` is the **install folder**. Anything written there
is destroyed by the next in-place update. Every CruSam storage decision exists
to prevent that, and Growmont inherits it:

```
%APPDATA%\Roaming\com.growmont\growmont_crm\GrowmontCRM\    <- ALL user data
  growmont.db
  growmont.backup.<timestamp>.db   (3 most recent kept)

%LOCALAPPDATA%\Programs\GrowmontCRM\                        <- install dir only
  growmont_crm.exe, flutter_windows.dll, data\, ...
```

The installer and uninstaller only ever touch the second path. Nothing in
`growmont_installer.iss` may reference an `%AppData%` path.

### Data flow

```
        UI (unchanged, 47 call sites)
                │  ref.read(apiServiceProvider).getSales()
                ▼
        CrmRepository  extends FirestoreService     <- Phase 6
         │  reads: local only          │ writes: local first, then enqueue
         ▼                             ▼
    LocalStore (SQLite)  ◄──────  SyncEngine  ◄──────► Firestore
      documents                   push outbox
      sync_pending (outbox)       pull snapshots
      sync_meta                   pre-pull backup
```

- **Reads** never hit the network. `getSales()` etc. read `documents` rows.
- **Writes** insert/update the local row (`dirty = 1`), append an outbox entry,
  and return immediately. The UI never waits on the network.
- **Doc IDs are generated offline.** `firestore.collection(c).doc().id` is a
  client-side random ID and works with no network — so there are **no temp IDs
  and no ID remapping**. This is important; do not build an ID-mapping table.
- **Pull** attaches a Firestore `snapshots()` listener per collection while
  online. Each batch writes into `documents`, **skipping any row with
  `dirty = 1`** (a queued local edit always wins until it has been pushed).
  That single rule is what prevents a stale server read from clobbering an
  unsent local change — it is CruSam's `hasPendingSync()` guard.
- **Deletes** are soft locally (`is_deleted = 1`, hidden from reads) and become
  a real Firestore `delete()` when the outbox drains; the local row is then
  removed.

### What stays online-only (cannot be queued)

These call Cloud Functions or Firebase Auth and have no meaningful offline
semantics. `CrmRepository` must **not** override them — they inherit from
`FirestoreService` and go straight to the network:

`provisionPendingEmployee`, `reviewEmployee`, `createEmployee`,
`deleteEmployee`, `changePassword`, `streamPendingReview`, `storage`.

`CrmRepository` **does** override `updateEmployee` (a plain doc update → queueable).

---

## PHASE 1 — Dependencies and app-data paths

### 1.1 `flutterapp/pubspec.yaml`

Add to `dependencies:` (keep existing entries untouched):

```yaml
  sqflite: ^2.4.2
  sqflite_common_ffi: ^2.3.0
  path: ^1.9.0
  package_info_plus: ^9.0.1
  connectivity_plus: ^6.1.3
```

`crypto`, `http`, `path_provider`, `shared_preferences` are already present —
do not duplicate them.

Run `flutter pub get` in `flutterapp/`.

### 1.2 Create `flutterapp/lib/core/storage/app_paths.dart`

Port from `CruSam/CruSam/crusam/lib/core/storage/app_paths.dart`. Edits:

- `_appFolderName` = `'GrowmontCRM'`.
- `AppStorageInfo` carries `database` (for `growmont.db`) and drops
  `semanticIndex` entirely — Growmont has no AI index. Keep
  `databaseDirectory`, `executableDirectory`, `toDiagnosticText()`.
- Add a `backupCount` int field to `AppStorageInfo`, populated by counting
  files matching `growmont.backup.*.db` in the directory.
- Keep `AppFileInfo` and `sizeLabel` exactly as-is.
- Keep the caching (`_cachedDir` / `_resolving`) exactly as-is — it matters,
  `getApplicationSupportDirectory()` is a platform channel call.
- Rewrite the doc comment header for Growmont, but **keep the explanation of
  why `getDatabasesPath()` is wrong**. That comment is the reason the file exists.

### 1.3 Wire it into `flutterapp/lib/main.dart`

Inside `main()`, **before** `runApp(...)` and **after**
`WidgetsFlutterBinding.ensureInitialized()`, add:

```dart
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    final appDataDir = await AppPaths.directory;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Defense-in-depth: neutralizes sqflite_common_ffi's Directory.current
    // default for any code that calls getDatabasesPath() directly.
    await databaseFactory.setDatabasesPath(appDataDir.path);
  }
```

Imports needed: `dart:io`, `package:flutter/foundation.dart` (for `kIsWeb`),
`package:sqflite/sqflite.dart`, `package:sqflite_common_ffi/sqflite_ffi.dart`,
`core/storage/app_paths.dart`.

Leave the existing `Firebase.initializeApp` + `persistenceEnabled` block exactly
as it is. Firestore's own cache is now a second-line fallback, not the
mechanism — but removing it would change mobile behavior for no benefit.

### Acceptance — Phase 1

- `cd flutterapp && flutter pub get` succeeds.
- `flutter analyze` → 0 errors.
- `flutter run -d windows` starts and the app behaves exactly as before.
- Add a temporary `debugPrint((await AppPaths.directory).path);` and confirm
  it prints a path under `AppData\Roaming`, **not** under `build\` or
  `Programs\`. Remove the debugPrint afterwards.

Commit: `chore(storage): add app-data path resolver and sqflite ffi bootstrap`

---

## PHASE 2 — Model JSON round-trip

The local mirror stores each Firestore document as a **JSON blob**, then
rehydrates it with the model's existing `fromJson(map, docId)` factory. That
works today for every field *except* `Timestamp` ones, because
`Timestamp` doesn't survive JSON. Two small fixes make the round-trip lossless.

### 2.1 `flutterapp/lib/models/employee.dart`

`_timestampToDate` at line 36 returns `null` for anything that isn't a
`Timestamp`, so ISO strings read back from SQLite would silently drop
`accessExpiresAt` / `requestedAt` / `approvedAt` / `rejectedAt` / `restrictedAt`.
Replace it with:

```dart
DateTime? _timestampToDate(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
  return null;
}
```

This is additive — existing `Timestamp` behavior is unchanged.

### 2.2 Verify the other four models

`sale.dart`, `interaction.dart`, `reminder.dart`, `client.dart` already handle
`rawDate is Timestamp` **or** `rawDate is String` in their `fromJson`. Read each
`fromJson` and confirm. If any date-ish field is `Timestamp`-only, extend it the
same way as 2.1. Do not restructure these factories beyond that.

### 2.3 Create `flutterapp/lib/core/local/firestore_json.dart`

A codec between "Firestore document data" and "JSON-safe map". No other file
may do this conversion.

```dart
/// Date-valued fields per collection. Used on the way OUT (local -> Firestore)
/// to restore real Timestamps, so Firestore queries and rules keep working.
const Map<String, List<String>> kDateFields = {
  'employees': ['dob', 'access_expires_at', 'requested_at', 'approved_at',
                'rejected_at', 'restricted_at', 'created_at', 'updated_at'],
  'clients':      ['created_at', 'updated_at'],
  'sales':        ['date', 'created_at', 'updated_at'],
  'interactions': ['date', 'follow_up_date', 'created_at', 'updated_at'],
  'reminders':    ['date', 'created_at', 'updated_at'],
};
```

Two functions:

- `Map<String, dynamic> toJsonSafe(Map<String, dynamic> data)` — recursive.
  `Timestamp` → `.toDate().toIso8601String()`. `DateTime` → `.toIso8601String()`.
  `Map` → recurse. `List` → map recurse. `FieldValue` → **drop the key entirely**
  (a sentinel must never be persisted locally). Everything else passes through.
- `Map<String, dynamic> toFirestore(String collection, Map<String, dynamic> json)`
  — for each key in `kDateFields[collection]`, if the value is a non-empty
  `String` that `DateTime.tryParse` accepts, replace it with
  `Timestamp.fromDate(parsed)`. Then unconditionally set
  `'updated_at': FieldValue.serverTimestamp()`. Everything else passes through.

Write unit tests in `flutterapp/test/firestore_json_test.dart` covering:
nested map, list of maps, `Timestamp` → ISO → `Timestamp` round-trip, and
`FieldValue.serverTimestamp()` being stripped by `toJsonSafe`.

### Acceptance — Phase 2

- `flutter test` passes (the new test file plus anything already there).
- `flutter analyze` → 0 errors.

Commit: `feat(local): add lossless Firestore<->JSON codec and fix Employee date parsing`

---

## PHASE 3 — The local database

### 3.1 Create `flutterapp/lib/core/local/local_database.dart`

Singleton, same shape as CruSam's `DatabaseHelper` (read
`CruSam/CruSam/crusam/lib/data/db/database_helper.dart` lines 19–65 for the
init pattern), but far smaller — one generic document table, not per-entity tables.

```dart
class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();
  static Database? _db;
  Future<Database> get database async => _db ??= await _init();
```

`_init()` opens at `await AppPaths.childPath('growmont.db')` on desktop and
`'${await getDatabasesPath()}/growmont.db'` on mobile, `version: 1`,
`onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')`,
`onCreate: _createTables`, `onOpen: _createTables` (all statements use
`IF NOT EXISTS`, so re-running on open is safe and self-healing).

Schema — exactly this:

```sql
CREATE TABLE IF NOT EXISTS documents (
  collection  TEXT    NOT NULL,
  doc_id      TEXT    NOT NULL,
  payload     TEXT    NOT NULL,          -- JSON, produced by toJsonSafe()
  updated_at  TEXT,                      -- ISO8601, for last-write-wins
  is_deleted  INTEGER NOT NULL DEFAULT 0,
  deleted_at  TEXT,
  synced_at   TEXT,                      -- NULL = never confirmed by server
  dirty       INTEGER NOT NULL DEFAULT 0,-- 1 = local edit not yet pushed
  PRIMARY KEY (collection, doc_id)
);
CREATE INDEX IF NOT EXISTS idx_documents_collection ON documents(collection, is_deleted);
CREATE INDEX IF NOT EXISTS idx_documents_dirty      ON documents(dirty);

CREATE TABLE IF NOT EXISTS sync_pending (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  collection  TEXT    NOT NULL,
  doc_id      TEXT    NOT NULL,
  op          TEXT    NOT NULL,          -- 'set' | 'delete'
  payload     TEXT,                      -- JSON for 'set', NULL for 'delete'
  created_at  TEXT    NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  last_error  TEXT
);
CREATE INDEX IF NOT EXISTS idx_pending_target ON sync_pending(collection, doc_id);

CREATE TABLE IF NOT EXISTS sync_meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);
```

Also on `LocalDatabase`:

```dart
/// Copies growmont.db to growmont.backup.<ts>.db before the first pull of a
/// session. Keeps the 3 most recent. Errors are logged and swallowed — a
/// backup failure must NEVER block startup or sync.
Future<void> createPreSyncBackup() async { ... }
```

Port the body from `DatabaseHelper.createPreSyncBackup()` (CruSam
`database_helper.dart` ~line 492): timestamp with `:` replaced by `-` so it is a
legal Windows filename, sort backups newest-first by filename, delete beyond 3,
wrap everything in try/catch.

### 3.2 Create `flutterapp/lib/core/local/local_store.dart`

The only class that talks to the `documents` / `sync_pending` tables.

```dart
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  /// Broadcast of collection names that just changed locally.
  /// CrmRepository's streams listen to this and re-query.
  Stream<String> get changes => _changes.stream;
  final _changes = StreamController<String>.broadcast();
```

Methods (all take `collection` as the first arg):

| Method | Behavior |
|---|---|
| `Future<List<Map<String,dynamic>>> all(String c)` | `SELECT * WHERE collection = ? AND is_deleted = 0`, JSON-decode each `payload`, inject `'id': doc_id`, return |
| `Future<Map<String,dynamic>?> byId(String c, String id)` | single row, `is_deleted = 0`, same decode |
| `Future<void> putLocal(String c, String id, Map<String,dynamic> json)` | `INSERT OR REPLACE` with `dirty = 1`, `synced_at = NULL`, `updated_at = now`; enqueue `{op:'set'}`; emit `c` on `changes` |
| `Future<void> putRemote(String c, String id, Map<String,dynamic> json)` | **skips the row entirely if its existing `dirty = 1`**; otherwise `INSERT OR REPLACE` with `dirty = 0`, `synced_at = now`; emit `c` |
| `Future<void> deleteLocal(String c, String id)` | set `is_deleted = 1`, `deleted_at = now`, `dirty = 1`; enqueue `{op:'delete'}`; emit `c` |
| `Future<void> deleteRemote(String c, String id)` | skip if `dirty = 1`; else hard `DELETE` the row; emit `c` |
| `Future<void> reconcilePull(String c, Set<String> serverIds)` | hard-delete rows in `c` where `dirty = 0 AND synced_at IS NOT NULL AND doc_id NOT IN serverIds` — these were deleted on another device. Never touches dirty or never-synced rows |
| `Future<List<PendingOp>> pending({int limit = 100})` | ordered by `id ASC` |
| `Future<void> markPushed(int opId, String c, String id)` | delete the outbox row; if no other outbox rows target `(c,id)`, set that document's `dirty = 0`, `synced_at = now`; for a completed `'delete'`, hard-delete the document row |
| `Future<void> markFailed(int opId, String error)` | `attempts = attempts + 1`, `last_error = error` |
| `Future<int> pendingCount()` | for the sync status card |

`putLocal`'s enqueue must **collapse** with any existing un-attempted `'set'`
op for the same `(collection, doc_id)`: update that row's `payload` and
`created_at` instead of appending a second one. Otherwise rapid edits pile up
redundant pushes.

Add `PendingOp` as a small data class in
`flutterapp/lib/core/local/sync_models.dart` along with:

```dart
enum SyncStatus { idle, syncing, offline, error }

class SyncSnapshot {
  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;
}
```

### Acceptance — Phase 3

- New test `flutterapp/test/local_store_test.dart` using
  `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` and an in-memory DB,
  covering: put/read round-trip; `putRemote` **not** overwriting a dirty row;
  `deleteLocal` hiding a row from `all()`; outbox collapsing two rapid
  `putLocal`s into one op; `reconcilePull` deleting a vanished clean row but
  sparing a dirty one.
- `flutter test` passes. `flutter analyze` → 0 errors.

Commit: `feat(local): add SQLite document store with outbox and pull reconciliation`

---

## PHASE 4 — The sync engine

### 4.1 Create `flutterapp/lib/core/local/sync_engine.dart`

```dart
class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const List<String> collections =
      ['employees', 'clients', 'sales', 'interactions', 'reminders'];

  SyncSnapshot get snapshot => ...;
```

Responsibilities, in order:

1. **`Future<void> start(FirebaseFirestore fs, String? uid)`** — idempotent.
   If `uid == null`, do nothing (signed out). Otherwise:
   `await LocalDatabase.instance.createPreSyncBackup()` (once per process),
   then attach listeners (step 2), then `unawaited(drainOutbox())`.
2. **Listeners.** For each collection in `collections`, attach
   `fs.collection(c).snapshots().listen(...)`. For each snapshot:
   for every doc → `LocalStore.putRemote(c, doc.id, toJsonSafe(doc.data()))`;
   then `LocalStore.reconcilePull(c, snapshot.docs.map((d) => d.id).toSet())`
   **only when `snapshot.metadata.isFromCache == false`** (a cache-only
   snapshot is not evidence that a doc was deleted server-side). Wrap each
   listener in `onError:` that records the error into the snapshot state and
   does **not** rethrow.
   - `reminders` is scoped per user: use
     `fs.collection('reminders').where('employee_id', isEqualTo: uid)`.
   - The other four are unscoped, matching current `FirestoreService` behavior.
3. **`Future<void> drainOutbox()`** — guarded by a `bool _draining` so two
   callers can't overlap. Loop over `LocalStore.pending()`:
   - `op == 'set'` → `fs.collection(c).doc(id).set(toFirestore(c, payload), SetOptions(merge: true))`
   - `op == 'delete'` → `fs.collection(c).doc(id).delete()`
   - success → `markPushed`; failure → `markFailed` and **stop the loop**
     (do not burn through the whole queue against a dead network).
   - Skip and hard-drop any op whose `attempts >= 5`, recording `last_error`
     into the snapshot so the UI can show it. Do not retry forever.
4. **Connectivity.** Subscribe to `Connectivity().onConnectivityChanged`;
   when the result is anything other than `ConnectivityResult.none`, call
   `drainOutbox()`. Also expose `Future<void> syncNow()` for the manual button:
   `drainOutbox()` then a one-shot `get()` per collection through the same
   `putRemote` + `reconcilePull` path.
5. **`Future<void> stop()`** — cancel all listeners and the connectivity
   subscription. Called on sign-out.
6. `notifyListeners()` whenever status / pendingCount / lastError changes.

**Do not** put retry backoff timers in here. Connectivity events plus the manual
button plus app start are sufficient triggers, and timers make the failure modes
much harder to reason about.

### 4.2 Create `flutterapp/lib/core/local/startup_sync.dart`

Port the shape of `CruSam/CruSam/crusam/lib/core/sync/startup_sync.dart`:

```dart
class StartupSync {
  StartupSync._();
  /// Fires on the next event-loop turn — AFTER the first frame and after auth
  /// has settled. Deliberately NOT Future.microtask(): a microtask runs before
  /// the event loop yields and races the auth token refresh.
  static void runInBackground(FirebaseFirestore fs, String? uid) {
    Future.delayed(Duration.zero, () async { ... });
  }
}
```

Keep that comment — it documents a real bug that was fixed once already.

### 4.3 Wire start/stop to auth

In `flutterapp/lib/core/providers.dart`, add:

```dart
final syncEngineProvider = ChangeNotifierProvider<SyncEngine>((ref) {
  final uid = ref.watch(authProvider).user?.id;
  final engine = SyncEngine.instance;
  if (uid == null) {
    engine.stop();
  } else {
    StartupSync.runInBackground(FirebaseFirestore.instance, uid);
  }
  return engine;
});
```

Then `ref.watch(syncEngineProvider)` once inside `GrowmontApp.build` in
`main.dart` so the provider is actually alive. Do not call `start()` from
`main()` directly — the uid isn't known there yet.

### Acceptance — Phase 4

- `flutter analyze` → 0 errors.
- `flutter run -d windows`, sign in. The app behaves as before (repository is
  not wired yet — this phase only fills the local DB).
- Confirm `growmont.db` now exists in the AppData folder from Phase 1 and has
  rows: open it, or add a temporary `debugPrint(await LocalStore.instance.all('clients'))`.
- Kill the app, disconnect the network, relaunch: no crash, no hang on startup.

Commit: `feat(sync): add Firestore<->SQLite sync engine with outbox drain`

---

## PHASE 5 — Payload normalization

`FirestoreService`'s create/update methods do per-collection normalization
inline before writing. `CrmRepository` needs the same rules applied *before the
local write*, so the local row and the eventual Firestore doc are identical.
Extract them once — do not duplicate them into the repository.

### Create `flutterapp/lib/core/local/payload_normalizer.dart`

```dart
/// Applies the same field normalization FirestoreService did inline, so a
/// locally-written document is byte-identical to what the server would have
/// stored. Rules are transcribed from firestore_service.dart — if you change
/// one here, check that method too.
class PayloadNormalizer {
  static Map<String, dynamic> forCollection(
    String collection,
    Map<String, dynamic> input, {
    required bool isCreate,
    String? currentUid,
  }) { ... }
}
```

Rules, transcribed from the current code — implement exactly these:

**`sales`** (from `createSale` / `updateSale`, lines 321–380)
- If `amount` present (or `amount_paise` absent/null on create):
  `amount_paise = (double.tryParse(amount.toString()) ?? 0.0 * 100).round()`,
  then `remove('amount')`.
- If key `sales_rep` present → move to `sales_rep_id` (as `String`), remove `sales_rep`.
- On create, if `sales_rep_id` still absent and `currentUid != null` → set it to `currentUid`.
- Leave `date` as an ISO `String` locally; `FirestoreJson.toFirestore` converts it on push.

**`interactions`** (lines 429–487)
- If key `employee` present → move to `employee_id`, remove `employee`.
- On create, if `employee_id` absent and `currentUid != null` → set it.
- `date` and `follow_up_date` stay ISO strings locally.

**`reminders`** (lines 526–568)
- If key `employee` present → move to `employee_id`, remove `employee`.
- On create, if `employee_id` absent and `currentUid != null` → set it.
- On create: `is_sent = false`.

**`employees`** (from `updateEmployee`, lines 259–272 — create stays online-only)
- `remove('password')` **always**. A password must never reach SQLite.
- `dob` stays an ISO string locally.

**`clients`** — no normalization beyond timestamps.

**All collections**
- On create: `created_at = DateTime.now().toUtc().toIso8601String()`.
- Always: `updated_at = DateTime.now().toUtc().toIso8601String()`.
  (`FirestoreJson.toFirestore` replaces `updated_at` with
  `FieldValue.serverTimestamp()` at push time — the local value is only there so
  local sorting works before the first successful push.)

### Acceptance — Phase 5

- `flutterapp/test/payload_normalizer_test.dart` covers: rupees→paise with a
  decimal amount (`"1234.56"` → `123456`); `sales_rep` → `sales_rep_id`;
  `employee` → `employee_id`; `password` stripped from an employees payload;
  `is_sent: false` on reminder create but not on update.
- `flutter test` passes. `flutter analyze` → 0 errors.

Commit: `feat(local): extract Firestore payload normalization rules`

---

## PHASE 6 — CrmRepository (the drop-in swap)

This is the phase that makes the app local-first **without editing a single
screen**. Read §0 rule 4 again before starting.

### 6.1 Expose the Firebase handles on `FirestoreService`

In `flutterapp/lib/core/firebase/firestore_service.dart`, add public getters
next to the existing `storage` / `currentUid` getters (around line 30). Purely
additive — change nothing else in this file:

```dart
  FirebaseFirestore get firestore => _firestore;
  FirebaseAuth get auth => _auth;
  FirebaseFunctions get functions => _functions;
```

(The private fields are library-private, so a subclass in another file cannot
reach them. These getters are what make `extends` viable.)

### 6.2 Create `flutterapp/lib/core/local/crm_repository.dart`

```dart
/// Local-first facade over FirestoreService.
///
/// Extends rather than wraps deliberately: every member this class does not
/// override keeps its original network behavior, so all existing call sites
/// compile and behave unchanged, and apiServiceProvider's declared
/// Provider<FirestoreService> type stays valid.
class CrmRepository extends FirestoreService {
  CrmRepository({super.firestore, super.auth, super.functions,
                 super.storage, super.devUid});
```

Override **only** these, and only in this way:

**Reads — local only, no network:**

| Override | Implementation |
|---|---|
| `getEmployees()` | `LocalStore.all('employees')` → `Employee.fromJson(m, m['id'])`, sorted by `name` |
| `getEmployee(id)` | `LocalStore.byId('employees', id)`; if null, **fall back to `super.getEmployee(id)`** (a profile fetched before the first sync must still work), and on success `putRemote` it |
| `getEmployeesDropdown()` | from local employees, map to `EmployeeDropdown.fromJson` |
| `getClients({employeeId})` | local `clients`, filter `employee_id == employeeId` in Dart when non-empty, sort by lowercased `name` |
| `getClient(id)` | local, same `super` fallback as `getEmployee` |
| `getEmployeeClients(id)` | `getClients(employeeId: id.toString())` — unchanged |
| `getSales({salesRepId, clientId})` | local `sales`, filter in Dart, sort newest-first by `date` |
| `getEmployeeSales(id)` | `getSales(salesRepId: id.toString())` |
| `getInteractions({employeeId, clientId})` | local, filter + sort newest-first |
| `getReminders()` | local `reminders` filtered to `currentUid`, sorted by date desc then time desc |

Reuse the existing sort semantics: `FirestoreService._byDateDesc` is private,
so add a private `_byDateDesc` in this file with the identical body (parse both
with `DateTime.tryParse`, nulls last, `dateB.compareTo(dateA)`), and for
reminders the same date-then-`b.time.compareTo(a.time)` tiebreak as
`_sortReminders`.

**Streams — local, re-emitting on `LocalStore.changes`:**

`streamSales`, `streamInteractions`, `streamReminders` become:

```dart
  Stream<List<Sale>> streamSales({String? salesRepId, String? clientId}) async* {
    yield await getSales(salesRepId: salesRepId, clientId: clientId);
    await for (final c in LocalStore.instance.changes) {
      if (c == 'sales') {
        yield await getSales(salesRepId: salesRepId, clientId: clientId);
      }
    }
  }
```

`streamPendingReview` is **not** overridden — it stays on Firestore live.

**Writes — local first, then queue:**

Every create follows this exact shape:

```dart
  @override
  Future<Sale> createSale(Map<String, dynamic> data) async {
    final id = firestore.collection('sales').doc().id; // offline-safe
    final payload = PayloadNormalizer.forCollection(
      'sales', data, isCreate: true, currentUid: currentUid);
    await LocalStore.instance.putLocal('sales', id, payload);
    unawaited(SyncEngine.instance.drainOutbox());
    return Sale.fromJson(payload, id);
  }
```

Update is the same minus the id generation: read the existing local payload,
merge `data` over it, normalize with `isCreate: false`, `putLocal`, drain,
return the model. **If the doc isn't in the local store, throw** — don't
silently create one.

Delete: `await LocalStore.instance.deleteLocal(c, id); unawaited(drainOutbox());`

Apply to: `createClient`, `updateClient`, `deleteClient`, `createSale`,
`updateSale`, `deleteSale`, `createInteraction`, `updateInteraction`,
`deleteInteraction`, `createReminder`, `updateReminder`, `deleteReminder`,
`updateEmployee` (returns `void` — keep the signature).

**Do not override:** `createEmployee`, `deleteEmployee`, `reviewEmployee`,
`provisionPendingEmployee`, `changePassword`, `streamPendingReview`, `storage`.

### 6.3 Flip the provider

In `flutterapp/lib/core/providers.dart`, change **only** the body of
`firestoreServiceProvider` to construct a `CrmRepository` instead of a
`FirestoreService`. Keep the declared type `Provider<FirestoreService>` and keep
`apiServiceProvider` exactly as it is.

### Acceptance — Phase 6

- `flutter analyze` → 0 errors **and zero files changed under `lib/features/`**.
  Verify with `git diff --stat` — only `lib/core/**` should appear.
- Manual, on Windows:
  1. Online: sign in, create a client → appears in the list → confirm the doc
     landed in Firestore console.
  2. **Pull the network cable / disable Wi-Fi.** Create a sale, edit an
     interaction, delete a reminder. All three succeed instantly in the UI.
  3. Kill the app, relaunch still offline: all data (including the offline
     edits) is present.
  4. Reconnect. Within a few seconds the queued writes appear in Firestore, and
     `LocalStore.pendingCount()` returns 0.
  5. Edit the same doc on the Firestore console while the app is offline with a
     pending edit on it. Reconnect: the **local** edit wins (this is the
     `dirty` guard doing its job). Confirm.

Commit: `feat(local): route all CRM reads and writes through the local store`

---

## PHASE 7 — Self-update system

Port from `CruSam/CruSam/crusam/lib/core/updater/` (5 files). All 5 go into
`flutterapp/lib/core/updater/`.

### 7.1 `version_constants.dart`

```dart
/// GitHub repository that hosts Growmont CRM releases.
/// This is the ONLY place the owner/repo pair is declared — build every URL
/// from these constants, never hardcode the path again.
///
/// TODO(release-repo): replace with the real public release repo once created.
const String kGitHubRepoOwner = 'REPLACE_ME_OWNER';
const String kGitHubRepoName  = 'REPLACE_ME_REPO';

const String kLatestReleaseApiUrl =
    'https://api.github.com/repos/$kGitHubRepoOwner/$kGitHubRepoName/releases/latest';

const String kInstallerAssetPrefix    = 'Growmont-Setup-';
const String kInstallerAssetExtension = '.exe';
```

Leave the `REPLACE_ME_*` placeholders in place and call them out in your final
report. Do not guess a repo name.

### 7.2 `update_model.dart`

Copy verbatim. `UpdateInfo` needs no changes.

### 7.3 `update_service.dart`

Copy from CruSam and apply exactly these edits:

- Delete `_readInstalledVersionFile()` and its call in `getCurrentVersion()`,
  plus the doc paragraph about it. That file was a bridge for legacy CruSam
  installs; Growmont has none, and CruSam's own docs say not to extend it.
  `getCurrentVersion()` becomes: `PackageInfo.fromPlatform()` → `.version.trim()`.
- Keep `checkForUpdate`, `_noUpdateInfo`, `_fetchLatestRelease`,
  `_stripLeadingV`, `_isInstallerAsset`, `downloadUpdate`,
  `_installerFileNameFrom`, `_verifyChecksumIfAvailable`,
  `launchUpdaterAndExit`, `_isNewer`, `_parse`, `_LatestRelease` **as-is**.
- Rename nothing else. In particular keep `launchUpdaterAndExit`'s name even
  though there is no updater exe — the doc comment already explains that it runs
  the installer directly. Keep that comment.
- Update the `User-Agent` header value (it derives from `kGitHubRepoName`
  already — no edit needed) and every doc reference from CruSam to Growmont.
- Keep `_verifyChecksumIfAvailable` exactly as written, including its "no-op
  until the pipeline publishes a `.sha256` sibling" behavior. Phase 9 **will**
  start publishing that sibling, at which point this switches on by itself.

### 7.4 `update_notifier.dart`

Copy verbatim. Two edits: rename the local `zipPath` variable to
`installerPath` (the zip pipeline is long gone), and fix the stale comment
above `launchUpdaterAndExit` that mentions `installed_version.txt` — replace it
with: *"The installer embeds the new version at build time, so the relaunched
exe reports it via PackageInfo with no file to write."*

### 7.5 `update_dialog.dart`

Copy from CruSam, then **retheme**. CruSam imports
`../theme/app_colors.dart` / `app_spacing.dart` / `app_text_styles.dart`, which
do not exist here. Replace with a single import of
`../theme/app_theme.dart` (it re-exports `design_tokens.dart`) and substitute:

| CruSam | Growmont |
|---|---|
| `AppSpacing.radiusLg` | `AppRadius.lg` |
| CruSam indigo gradient `[0xFF0F172A, 0xFF1E1B4B]` | `[AppColors.sidebarBg, AppColors.sidebarBgDeep]` |
| indigo accents | `AppColors.primaryGreen` |
| CruSam text styles | `AppTypography.cardTitle`, `.bodyPrimary`, `.bodySecondary`, `.caption` |

Keep the dialog's **behavior** identical: `barrierDismissible: false`,
`ListenableBuilder` on `UpdateNotifier.instance`, 420px width, per-state body
(idle / downloading with progress / launching / error).

### 7.6 `flutterapp/lib/features/profile/widgets/update_card.dart`

Do **not** copy CruSam's version — it hardcodes a private `_Tok` design-token
class for a different app. Write a fresh `UpdateCard` with the same structure
and states, built from `AppColors` / `AppTypography` / `AppSpacing` /
`AppRadius` / `AppSizing`:

- Header row: `Icons.system_update_outlined` + `'APP VERSION'`.
- Rows: current version (from `UpdateService.getCurrentVersion()` in
  `initState`), and latest version once a check has run.
- Status badge, one of: checking / downloading N% / launching / update
  available (warning colors) / up to date (`successSoft` + `success`) / prompt
  to check.
- Error box using `AppColors.dangerSoft` + `AppColors.danger`.
- Buttons: **Check** (`OutlinedButton.icon`, disabled while busy) and, only when
  `notifier.hasUpdate`, **Update Now** (`FilledButton.icon` → `UpdateDialog.show`).

### 7.7 Profile integration

In `flutterapp/lib/features/profile/profile_screen.dart`:

- Add `system` to the `ProfileTab` enum (line 18) → `{ sales, interactions, reminders, system }`.
- Add its chip in the tab-chip row alongside the existing three
  (`_tabChip('System', ProfileTab.system, 0)` — pass 0, or drop the count for
  this one if `_tabChip`'s signature makes that awkward; a small overload is fine).
- Add `ProfileTab.system => _systemTab()` to the `switch (_tab)` at line 400.
- `_systemTab()` returns a scrollable `ListView` with, in order:
  `UpdateCard()`, `DataLocationCard()` (Phase 8), `SyncStatusCard()` (Phase 8),
  separated by `SizedBox(height: AppSpacing.lg)`, padded `AppSpacing.lg`.
- Guard the whole tab with `if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)`
  — on mobile the tab shows only `SyncStatusCard` (no self-update, no file paths).

### 7.8 Startup check

In `main.dart`, after `runApp`-adjacent setup, fire a non-blocking check on
desktop only:

```dart
  if (!kIsWeb && Platform.isWindows) {
    UpdateNotifier.instance.checkForUpdate(); // deliberately not awaited
  }
```

Startup must never block on a network call. Do **not** auto-show the dialog;
the badge in the System tab is the notification. (If the user later wants a
prompt on launch, that's a follow-up.)

### Acceptance — Phase 7

- `flutter analyze` → 0 errors.
- Profile → System tab renders all cards; **Check** reports "No update
  information available." against the placeholder repo (this is the correct,
  graceful failure — `_fetchLatestRelease` returns null and never throws).
- Current version shows `1.0.0`.

Commit: `feat(updater): add GitHub Releases self-update check and Profile system tab`

---

## PHASE 8 — Storage + sync visibility cards

### 8.1 `flutterapp/lib/features/profile/widgets/data_location_card.dart`

Desktop only. Uses `AppPaths.resolveStorageInfo()`:

- Header: `Icons.folder_outlined` + `'DATA STORAGE'`.
- Rows: database folder, `growmont.db` path with size + last-modified,
  backup count, program folder.
- Buttons: **Copy paths** (`Clipboard.setData(ClipboardData(text: info.toDiagnosticText()))`
  + a confirming SnackBar) and **Open folder**
  (`Process.run('explorer', [dir])` on Windows; hide the button elsewhere).
- A short explanatory line: *"Your data lives outside the program folder, so
  updates and reinstalls never touch it."* — this is the whole point of the
  card; keep it.

### 8.2 `flutterapp/lib/features/profile/widgets/sync_status_card.dart`

Consumes `ref.watch(syncEngineProvider)`:

- Status badge driven by `SyncStatus`: syncing / offline / error / "All changes
  synced".
- `'N change(s) waiting to upload'` when `pendingCount > 0`.
- Last synced timestamp, formatted with the app's existing `intl` usage.
- **Sync now** button → `SyncEngine.instance.syncNow()`, disabled while syncing.
- If `lastError != null`, show it in a `dangerSoft` box.

Both cards are added to `_systemTab()` in Phase 7.7 — if you did Phase 7 first,
just fill in the placeholders now.

### Acceptance — Phase 8

- `flutter analyze` → 0 errors.
- The paths shown by the card are under `AppData\Roaming`, and **Open folder**
  opens a directory that actually contains `growmont.db`.
- Go offline, make an edit: the sync card shows a pending count. Reconnect:
  it returns to 0 and the timestamp updates.

Commit: `feat(profile): add data location and sync status cards`

---

## PHASE 9 — Windows installer

New directory `Growmont_crm-main/installer/` (sibling of `flutterapp/`, matching
CruSam's `installer/` ↔ `crusam/` layout).

### 9.1 `installer/growmont_installer.iss`

Port from `CruSam/CruSam/installer/crusam_installer.iss`. Edits:

```
#define MyAppName "Growmont CRM"
#define MyAppPublisher "Growmont"
#define MyAppExeName "growmont_crm.exe"
#define MyAppId "{7B3F1A62-9C48-4E1D-BF06-2A5D8C4E9F13}"
#define AppIconFile "../flutterapp/windows/runner/resources/app_icon.ico"
#ifndef ReleaseDir
  #define ReleaseDir "../flutterapp/build/windows/x64/runner/Release"
#endif
```

- `MyAppURL` → the release repo URL (leave a `TODO(release-repo)` comment).
- `DefaultDirName={localappdata}\Programs\GrowmontCRM`
- `OutputBaseFilename=Growmont-Setup-{#MyAppVersion}`
- `CloseApplicationsFilter=growmont_crm.exe` (no updater.exe)
- **Keep unchanged and do not "improve":** `PrivilegesRequired=lowest`,
  `UsePreviousAppDir=yes`, `CloseApplications=yes`, `RestartApplications=no`,
  `ArchitecturesAllowed=x64`, `MinVersion=10.0`, the single `[Files]` entry,
  both `[Run]` entries (`skipifsilent` for the interactive checkbox +
  `skipifnotsilent` for the silent auto-relaunch), and the `[UninstallDelete]`
  entry.
- **The `MyAppId` GUID above is permanent.** Changing it later breaks in-place
  upgrades for everyone already installed. Copy the comment saying so.
- Keep the header comment about forward slashes in `/D` defines — Inno's
  preprocessor applies C-style escaping and a path containing `\x64` gets
  silently corrupted.
- Verify by reading: **no `%AppData%` path appears anywhere in this file.**

### 9.2 `installer/build_release.ps1`

Port from `CruSam/CruSam/installer/build_release.ps1`. Edits:

- `$AppDir = Join-Path $RepoRoot 'flutterapp'` (CruSam calls this `$CrusamDir`).
- **Delete step 6 entirely** (the `dart compile exe` updater build and its copy).
  Renumber the remaining steps.
- `growmont_crm.exe` everywhere `crusam.exe` appears.
- `Growmont-Setup-$versionOnly.exe` as the expected output name.
- **Keep** the pubspec version parse (`^version:\s*(\S+)`, top-level only), the
  `flutter clean` → `pub get` → `build windows --release` sequence, the dual
  Release-path probe (`build\windows\x64\runner\Release` then
  `build\windows\runner\Release`), the ISCC discovery (PATH → both Program Files),
  and the `-replace '\\','/'` on `$ReleaseDirForIscc`.
- **Keep the embedded-version verification step and its `Fail` message.** This
  is the guard against the stale-CMake-cache bug where a rebuilt exe ships an
  old `FILEVERSION`. It is the reason `flutter clean` is mandatory.
- **New step, after the installer compiles:** write the SHA-256 sibling asset,
  which turns on `_verifyChecksumIfAvailable` in `update_service.dart`:

```powershell
$hash = (Get-FileHash -Algorithm SHA256 $installerPath).Hash.ToLower()
Set-Content -Path "$installerPath.sha256" -Value "$hash  $(Split-Path -Leaf $installerPath)" -Encoding utf8
```

  Both files get uploaded to the release. The updater fetches
  `<download_url>.sha256` and aborts on mismatch.

### 9.3 `installer/README.md`

Port CruSam's, adjusted for the above: prerequisites (Flutter with Windows
desktop, Inno Setup 6), usage, `-SkipVerify` / `-IsccPath` options, the
"installer-only" invocation, what the installer does and does not touch, and
the note that `installer\Output\` is build output.

### 9.4 `.gitignore`

Add `installer/Output/` at the repo root's `.gitignore` (create the file if the
repo doesn't have one — it currently has `.gitattributes` only).

### Acceptance — Phase 9

- `.\installer\build_release.ps1` from a PowerShell prompt at
  `Growmont_crm-main` completes and produces
  `installer\Output\Growmont-Setup-1.0.0.exe` plus `.sha256`.
- Running that installer installs to `%LOCALAPPDATA%\Programs\GrowmontCRM`
  with **no UAC prompt** and launches the app.
- **The critical test:** with the app installed and holding real data, bump
  `pubspec.yaml` to `1.0.1+2`, rebuild, and run the new installer over the top.
  After it finishes: the app relaunches, Profile → System shows `1.0.1`, and
  **every client / sale / interaction / reminder is still there.** If any data
  is missing, stop — something is writing to the install folder and §1 has been
  violated.
- Uninstall removes `%LOCALAPPDATA%\Programs\GrowmontCRM` and **leaves the
  AppData folder and `growmont.db` intact.** Verify this explicitly.

Commit: `feat(installer): add Inno Setup packaging and release pipeline`

---

## PHASE 10 — Release documentation

Two files, ported from CruSam and rewritten for Growmont. These are not
optional — the version-mismatch failure mode they document is subtle and will
recur without them.

### 10.1 `flutterapp/RELEASE.md`

Port `CruSam/CruSam/crusam/RELEASE.md`. Keep the structure and **keep these
sections in full**, adapted:

- *"Single source of truth: `pubspec.yaml`"* — including "do not introduce a
  second place that declares the version".
- *"How this flows into the compiled `.exe`"* — the 6-step chain from
  `pubspec.yaml` → `generated_config.cmake` → `Runner.rc` → `VS_VERSION_INFO`
  → `PackageInfo.fromPlatform()`.
- *"Required release steps"* 1–6.
- *"Why clean builds are required on Windows"* — the CMake-timestamp
  explanation, verbatim in substance.
- *"How the app discovers updates (GitHub Releases)"* — with the
  `Growmont-Setup-<version>.exe` naming rule and the warning that a misnamed
  asset makes the updater silently report "no update available".

**Drop** the CruSam-only sections: `latest.json` deprecation and the
`installed_version.txt` note. Neither exists here.

**Add** a short section: *"Publishing a release"* — create the GitHub release
tagged `v<version>` on the release repo, upload both
`Growmont-Setup-<version>.exe` and `Growmont-Setup-<version>.exe.sha256`, and
confirm `kGitHubRepoOwner`/`kGitHubRepoName` in `version_constants.dart` point
at that repo.

### 10.2 `flutterapp/UPDATE_SYSTEM_README.md`

Port CruSam's, listing the actual files added/changed by Phases 7–9, the
GitHub Releases update source, the release flow, and a **Data safety** section
stating that the installer only writes inside
`%LOCALAPPDATA%\Programs\GrowmontCRM` and never touches the AppData folder
holding `growmont.db`.

### 10.3 `flutterapp/LOCAL_FIRST.md` (new — no CruSam equivalent)

One page covering: the storage layout diagram from §1, the read/write/sync flow,
the `dirty`-wins conflict rule, which operations are online-only and why, how to
inspect `growmont.db`, and how backups are named and pruned. Whoever debugs a
sync complaint six months from now reads this first.

### Acceptance — Phase 10

- All three docs exist and every file path they reference actually exists.
- A reader who has never seen this plan could cut a release from `RELEASE.md`
  alone.

Commit: `docs: add release, update-system and local-first documentation`

---

## Known pitfalls (read before you hit them)

1. **Don't add per-entity SQLite tables.** The generic `documents` table plus
   the models' existing `fromJson` is deliberate. Per-entity columns would mean
   a schema migration every time a Firestore field is added.
2. **`FieldValue.serverTimestamp()` must never be JSON-encoded.** `toJsonSafe`
   drops it. If you see `Instance of 'FieldValue'` in a payload, that's the bug.
3. **`putRemote` must respect `dirty`.** Skipping this check is how you lose a
   user's offline edit. It is the single most important line in `LocalStore`.
4. **`reconcilePull` must not run on a cache-only snapshot.** Check
   `snapshot.metadata.isFromCache` first, or a cold offline start will delete
   the entire local database.
5. **Don't `await` the outbox drain in a write path.** `unawaited(...)`. The UI
   returning instantly is the whole point of local-first.
6. **Don't change the installer `AppId` GUID after the first release.**
7. **Don't skip `flutter clean` before a release build.** The verification step
   in `build_release.ps1` will catch it, but only if you don't pass `-SkipVerify`.
8. **`_verifyChecksumIfAvailable` failing open is intentional** for releases
   with no `.sha256` asset. Don't "fix" it into a hard requirement — that would
   break the updater for any already-published release.
9. **Password fields.** `PayloadNormalizer` strips `password` from employees
   payloads. Double-check no other path can write one into SQLite.
10. **Firestore security rules are unchanged by this work.** The outbox pushes
    as the signed-in user, so anything the rules rejected before is still
    rejected — it will surface as a `markFailed` with a permission error, not
    as silent data loss. Surface those in the sync card's error box.

---

## Suggested execution order for a fresh session

Phases are strictly sequential. A reasonable split across sessions, if context
gets tight:

- Session A: Phases 1–3 (storage foundation)
- Session B: Phases 4–6 (sync + repository swap) ← the risky one; test hard
- Session C: Phases 7–8 (updater + UI)
- Session D: Phases 9–10 (installer + docs)

At the start of each session, re-read §0 and the acceptance block of the last
completed phase before writing any code.
