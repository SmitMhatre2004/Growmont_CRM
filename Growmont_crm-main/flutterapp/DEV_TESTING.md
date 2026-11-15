# Local testing against the Firebase Emulator

Growmont CRM is deployed and in daily use. A development build must never
read or write the live `growmontcrm` project, so local testing runs against
the Firebase Emulator Suite with seeded sample data and throwaway logins.

This document covers how to do that, and the guards that make hitting
production by accident impossible rather than merely unlikely.

## The three guards

| Risk | Guard |
|---|---|
| A build silently points at localhost | `USE_FIREBASE_EMULATOR` is a compile-time define that **defaults to false**. Every ordinary build, including anything `installer/build_release.ps1` produces, is unchanged. |
| A shipped installer points at localhost | The define is ANDed with `!kReleaseMode` in [`lib/core/config/dev_config.dart`](lib/core/config/dev_config.dart). A **release build cannot be made to use the emulator**, even if someone passes the define. It logs that it ignored it. |
| Test rows mixing into real local data | The app is local-first: Firestore documents are synced into a SQLite file under `%APPDATA%`. Emulator mode uses a **separate database file** (`growmont-emulator.db` instead of `growmont.db`), so seeded rows can never end up in the real database and get synced upward later. |

A fourth guard lives in the seed script: [`scripts/seed-emulator.js`](../scripts/seed-emulator.js)
sets the emulator host variables itself and **refuses to run** if they point
anywhere other than loopback. The Admin SDK connects to the live project
whenever those variables are absent, so the script does not rely on the
caller remembering to set them.

## Prerequisites

- Firebase CLI (`firebase --version`)
- Java 11+ — the Firestore emulator is a JVM process
- Node 18+ for the seed script

One-time, from the repo root:

```bash
cd scripts
npm install

cd ../flutterapp
flutter pub get
```

## Running it

**1. Start the emulators** (repo root, leave this running):

```bash
firebase emulators:start --only auth,firestore --project growmontcrm
```

Ports come from `firebase.json`: Auth 9099, Firestore 8080, UI 4000.
Browse the data at <http://localhost:4000>.

**2. Seed accounts and sample data** (new terminal):

```bash
cd scripts
npm run seed:emulator
```

This wipes and repopulates the emulator with three logins, 13 clients,
~53 sales spread over six months, and ~18 interactions — enough for the
Monthly Report to show real figures, month-over-month deltas and a
populated trend chart.

| Login | Password | Role |
|---|---|---|
| `dev@growmont.com` | `devpass123` | ADMIN |
| `asha@growmont.com` | `devpass123` | EMPLOYEE |
| `bilal@growmont.com` | `devpass123` | EMPLOYEE |

Override the password with `DEV_PASSWORD=... npm run seed:emulator`.

One client is seeded **deliberately without a `created_at`**, so the
Monthly Report's data-quality warning and its "this is a minimum, not a
total" wording are visible rather than theoretical.

**3. Run the app** (new terminal):

```bash
cd flutterapp
flutter run -d windows --dart-define=USE_FIREBASE_EMULATOR=true
```

On startup the console prints:

```
EMULATOR MODE: Auth :9099, Firestore :8080, Storage :9199 on 127.0.0.1.
The live Firebase project is NOT in use.
```

If that line is absent, the build is talking to production — stop and
check the define.

## Checking the figures are right

"It renders" is not "it is correct". `scripts/verify-report.js` recomputes
every figure the Monthly Report shows — in JavaScript, straight from the
emulator's Firestore documents, with no reference to the Dart aggregation
code. Two independent implementations agreeing is real evidence; one
implementation agreeing with itself is not.

```bash
npm --prefix scripts run verify            # the current month
node scripts/verify-report.js 2026-10      # any month, YYYY-MM
```

It prints the expected KPI cards, breakdowns, team table and data-quality
counts, plus a set of internal-consistency checks (breakdowns summing to
revenue, team revenue summing to the company total, and so on). Compare
its output with the screen. **Any mismatch is a bug — report it with both
numbers.**

### What to work through

| # | Check | Expected |
|---|---|---|
| 1 | Admin report vs `npm run verify` | Every figure matches |
| 2 | Sign in as `asha@growmont.com` | Only her own totals; **no Team performance section** |
| 3 | Data-quality banner | Warns about 1 client with no date added — one is seeded that way on purpose |
| 4 | Month arrows / trend bars | Previous months load; forward arrow disabled on the current month; a bar **click** changes the month but **hovering does not** |
| 5 | Export → Both | PDF and Excel both save; the rupee sign renders in the PDF; all three show identical figures |
| 6 | A month far in the past | Honest empty state, not a grid of zeroes |
| 7 | Reports vs the Sales screen | Same month, same count and total |

Check 2 is the one worth doing carefully: an employee seeing company-wide
figures is a data leak, and it is the bug that got through an entire
passing test suite once already.

## What does not work in emulator mode

The **Functions emulator is not wired up**, because nothing this mode is
used to exercise calls a Cloud Function, and running them would need
`npm install` under `functions/` first. So these stay broken locally:

- Creating, reviewing, restricting or deleting an employee
- Changing a password or email from inside the app
- The reminder-email scheduler

Seed those accounts with the seed script instead. To add the Functions
emulator later: `npm install` in `functions/`, add `functions` to the
`--only` list, and wire `useFunctionsEmulator` in `main.dart` alongside
the others.

## Signing in with Google

Google sign-in goes to real Google servers and will not resolve to an
emulator user. Use email + password with the seeded accounts.

## Switching back to production

Just drop the define:

```bash
flutter run -d windows
```

The app returns to the live project and the real `growmont.db`. Nothing
needs undoing — the two data sets were never in the same file.

## Known local build issues on Visual Studio 2026

**Skip this section if you build with Visual Studio 2022** — it bundles
CMake 3.x and none of the following happens. VS 2022 is the recommended
toolchain for this project, and is what cut release 1.2.2.

Visual Studio 2026 bundles CMake 4.x, which breaks the Windows build in
two independent places. Both are environment incompatibilities, unrelated
to any application code:

1. **Firebase C++ SDK 12.7.0** declares `cmake_minimum_required` below
   3.5, and CMake 4 removed that compatibility. Work around it by setting
   `CMAKE_POLICY_VERSION_MINIMUM=3.5` in the environment before building.

2. **Flutter's own `windows/CMakeLists.txt:68`** tests
   `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT`, which CMake 4 no longer
   sets. The install prefix therefore stays at its default
   `C:/Program Files/growmont_crm` and the INSTALL step fails with
   "Maybe need administrative privileges".

The durable fix is to **build with Visual Studio 2022**, which bundles
CMake 3.x — and which is almost certainly what the machine that cut
release 1.2.2 used. Patching `windows/CMakeLists.txt` would also work but
changes the build for everyone and affects the documented release
pipeline, so it is not done here.

### Other build snags seen on that machine

**`Cannot open source file: ...ephemeral\cpp_client_wrapper\*.cc`**

Flutter copies its C++ client wrapper into
`windows/flutter/ephemeral/cpp_client_wrapper/` at build time. On the
VS 2026 machine it copies only the `include/` subfolder and drops the
`.cc` files next to it.

**The fix is to clear that step's build stamp so it runs again:**

```bash
find .dart_tool/flutter_build -name "unpack_windows.stamp" -delete
flutter run -d windows --dart-define=USE_FIREBASE_EMULATOR=true
```

### Why that, and not the things that look like they should work

Flutter's `unpack_windows` build step is the one that copies the C++
client wrapper into `ephemeral/`. Like every step in that build system it
is incremental: it writes `unpack_windows.stamp`, and skips itself when
that stamp still looks current. Once the `.cc` files are missing but the
stamp says the copy is done, **nothing puts them back** — every
subsequent build skips straight past the step and the compiler fails on
files that were never recreated.

That explains the two fixes that half-worked:

- **Hand-copying the files from the SDK cache** survives until the next
  build, which clears `ephemeral/` and re-skips the copy.
- **`flutter precache --windows --force`** does fix it — it re-downloads
  the artifacts, which changes their timestamps and invalidates the
  stamp — but it is slow (it rebuilds the Flutter tool and runs a pub
  upgrade, which can touch `pubspec.lock`) and only holds until the
  stamp goes stale again.

Deleting the stamp does the same job directly, in a second, with no side
effects.

What is still not understood is why the `.cc` files go missing in the
first place; antivirus was ruled out (hand-copied files stay on disk
until Flutter itself clears them). It has not been seen on a Visual
Studio 2022 machine.

**`LNK1168: cannot open growmont_crm.exe for writing`**

A previous run of the app is still holding the executable. Close the app
window, or:

```bash
taskkill //FI "IMAGENAME eq growmont_crm.exe" //F
```

Quitting a `flutter run` session with `q` shuts the app down cleanly and
avoids this; killing the terminal does not.
