# Growmont CRM → Flutter Conversion Plan

This plan is based on a direct read of the uploaded repo (`Growmont_crm-main.zip`), not assumptions — model fields, API routes, and screen lists below are taken from the actual `server/core/models.py`, `server/backend/urls.py`, and `client/src/**` source files.

---

## 1. Executive Summary

The repo is a two-part app:

| Part | Stack | Verdict |
|---|---|---|
| `server/` | Django 4.2 + DRF + SimpleJWT + Celery/Redis + PostgreSQL (Supabase) | **Keep as-is.** Flutter talks to this over REST/JSON. Flutter cannot "become" a Django backend — it's a client framework. |
| `client/` | Next.js 16 + React 19 + TypeScript + Tailwind CSS 4 | **This is what gets converted to Flutter.** |

So "convert to Flutter" = rebuild the `client/` app as a Flutter app (Android/iOS/Web/Desktop from one codebase) that consumes the existing Django REST API unchanged. This is the standard, sane interpretation — flag it to whoever asked for this if there's any doubt.

**Frontend size:** 9 route pages + 9 shared components + 1 context provider ≈ 6,700 lines of TSX. Medium-sized CRUD CRM — realistically 3–5 weeks for one Flutter dev to reach parity, depending on polish expected.

---

## 2. What the Current App Actually Does

**App name (from layout.tsx):** "Growmont Employee Portal"

**Roles:** `ADMIN` and `EMPLOYEE` (from `Employee.role`), with different views (e.g. Info Portal is an admin-style combined data view).

**Core entities** (from `core/models.py`):

- **Employee** — linked 1:1 to Django `User`; name, email, mobile_no, gender, dob, avatar (image), role
- **Client** — name, contact_number, M2M to Employees
- **Sale** — date, client_name, sales_rep (FK Employee), product (16-choice enum: Mutual Funds, Health/General/Life Insurance, NCDs, MLDs, Bonds, Corporate FDs, AIFs, PMS, Advisory, Shares Broking, Unlisted Shares, Real Estate, Loans, Will Making), company, scheme, amount (decimal), frequency (Monthly/Quarterly/Half-Yearly/Yearly/One-Time), remarks
- **Interaction** — date, client_name, client_contact, employee (FK), follow_up_date, follow_up_time, priority (High/Medium/Low), discussion_notes
- **Reminder** — employee (FK), event_name, type (Corporate/Personal), priority, date, time, end_time, description, repeat settings (none/daily/weekly/monthly + specific days), is_sent

**Screens** (from `client/src/app/`):

1. `page.tsx` → Login (redirects to `/dashboard` if already authenticated)
2. `dashboard/page.tsx` → recent sales/interactions/reminders widgets + sticky-notes-style TodoWidget
3. `employees/page.tsx` → employee list
4. `employees/[id]/page.tsx` → employee detail (their clients, sales)
5. `sales/page.tsx` → sales CRUD table with filters + Excel import/export
6. `interactions/page.tsx` → interactions CRUD table with filters
7. `info-portal/page.tsx` → combined admin view: tabbed Sales/Interactions table, search, filters, inline edit/delete
8. `profile/page.tsx` → user profile / settings
9. `not-found.tsx` → 404

**Shared components:** `Navbar`, `Sidebar`, `AddEmployeeModal`, `AddSalesModal`, `AddInteractionsModal`, `AddReminderModal`, `Remiander` (reminder card widget), `TodoWidgets`.

**No charting library, no complex date-picker library** — just native HTML inputs and `lucide-react` icons. This keeps the Flutter rebuild's dependency list light.

---

## 3. Auth & API Contract (already reverse-engineered — reuse exactly)

**Login flow:** `POST /api/auth/login/` with `{username, password}` → response:
```json
{
  "access": "...", "refresh": "...",
  "user": { "id": 1, "name": "...", "email": "...", "avatar": "url|null", "role": "ADMIN|EMPLOYEE" }
}
```
Access token is a JWT (SimpleJWT), sent as `Authorization: Bearer <token>`. On `401`, the client currently wipes storage and force-redirects to login — replicate this as a Dio interceptor.

**Full endpoint list** (from `backend/urls.py` — this is the complete, real API surface):

```
Auth
  POST /api/auth/login/
  POST /api/auth/refresh/
  POST /api/auth/logout/
  GET  /api/me/
  POST /api/auth/password/change/
  POST /api/auth/password/forgot/

Employees
  GET    /api/employees/
  GET    /api/employees/<id>/
  PUT    /api/employees/<id>/update/
  DELETE /api/employees/<id>/delete/
  GET    /api/employees/<id>/clients/
  GET    /api/employees/<id>/sales/
  GET    /api/employees/dropdown/

Sales
  GET    /api/sales/
  POST   /api/sales/create/
  PUT    /api/sales/<pk>/update/
  DELETE /api/sales/<pk>/delete/

Interactions
  GET    /api/interactions/
  POST   /api/interactions/create/
  PUT    /api/interactions/<pk>/update/
  DELETE /api/interactions/<pk>/delete/

Reminders
  GET    /api/reminders/
  POST   /api/reminders/create/
  PUT    /api/reminders/<pk>/update/
  DELETE /api/reminders/<pk>/delete/

Export (returns .xlsx binary)
  GET /api/export/sales/
  GET /api/export/sales/filtered/
  GET /api/export/interactions/
  GET /api/export/interactions/filtered/

Import (multipart .xlsx upload)
  POST /api/import/sales/
  POST /api/import/interactions/

Misc
  GET /api/health/
  GET /api/protected/
```

This table alone can drive the entire `ApiService` class — no guesswork needed there.

---

## 4. Target Flutter Architecture

**Recommended stack:**

| Concern | Package | Why |
|---|---|---|
| State management | `flutter_riverpod` | Testable, scales well for an app with auth state + several independent CRUD feature areas |
| Routing / role-guarded nav | `go_router` | Replaces Next.js file-based routing + the manual `router.push` / login-redirect checks in `AuthContext` |
| HTTP client | `dio` | Interceptors give a clean 1:1 replacement for `apiFetch`'s auth-header injection + 401 handling + token refresh |
| Secure token storage | `flutter_secure_storage` | Replaces `localStorage.setItem('accessToken', ...)` |
| Non-sensitive prefs (e.g. sticky notes draft) | `shared_preferences` | Replaces misc `localStorage` usage |
| JSON models | `json_serializable` + `freezed` (or hand-written) | Matches the DRF serializer shapes 1:1 |
| Icons | `lucide_icons` (Flutter port) | Same icon family as the current `lucide-react` usage, avoids a visual redesign |
| Toasts | `fluttertoast` or built-in `ScaffoldMessenger` SnackBar | Replaces `react-hot-toast` |
| Excel import | `file_picker` | Replaces the browser `<input type=file>` for `.xlsx` upload |
| Excel export (download the binary the backend returns) | `dio` (download) + `path_provider` + `share_plus` / `open_filex` | Save/share the exported `.xlsx` on-device |
| Avatar image display/upload | `image_picker` + `cached_network_image` | Employee avatar upload + display |
| Forms | Native `Form` + `TextFormField`, `showDatePicker`, `showTimePicker` | Everything here is standard form fields — no exotic pickers were found in the original |

**Not needed:** no charting package (dashboard has no charts), no complex date-range picker library (native pickers cover it).

**Suggested folder structure:**
```
lib/
  main.dart
  core/
    api/
      api_client.dart          # Dio instance + interceptors (auth header, 401 handling, refresh)
      endpoints.dart           # const strings, mirrors utils/api.ts endpoints{}
    storage/
      token_storage.dart       # flutter_secure_storage wrapper
    router/
      app_router.dart          # go_router config + role-based redirect guards
    theme/
      app_theme.dart           # replaces globals.css / Tailwind tokens
  models/
    employee.dart
    client.dart
    sale.dart
    interaction.dart
    reminder.dart
    user.dart                  # the login-response `user` object
  features/
    auth/
      login_screen.dart
      auth_provider.dart       # replaces AuthContext.tsx
    dashboard/
      dashboard_screen.dart
      todo_widget.dart
      reminder_card.dart
    employees/
      employees_list_screen.dart
      employee_detail_screen.dart
      widgets/add_employee_modal.dart
    sales/
      sales_screen.dart
      widgets/add_sale_modal.dart
    interactions/
      interactions_screen.dart
      widgets/add_interaction_modal.dart
    reminders/
      widgets/add_reminder_modal.dart
    info_portal/
      info_portal_screen.dart  # tabbed sales/interactions admin view
    profile/
      profile_screen.dart
  shared/
    widgets/
      app_navbar.dart
      app_sidebar.dart
      data_table_scaffold.dart # shared table+filter+search chrome (sales/interactions/info-portal all reuse this pattern)
```

---

## 5. Screen-by-Screen Migration Map

| Next.js source | Flutter target | Notes |
|---|---|---|
| `app/page.tsx` + `components/Login.tsx` | `features/auth/login_screen.dart` | Check stored token on app start via a splash/redirect in `go_router`, not a `useEffect` |
| `context/AuthContext.tsx` | `features/auth/auth_provider.dart` (Riverpod `Notifier`) | Same responsibilities: hold `user`/`token`, `login()`, `logout()`, restore from secure storage on boot |
| `app/dashboard/page.tsx` | `features/dashboard/dashboard_screen.dart` | Fetch sales/interactions/reminders on load; sticky notes → local `shared_preferences` |
| `components/TodoWidgets.tsx` | `features/dashboard/todo_widget.dart` | |
| `components/Remiander.tsx` | `features/dashboard/reminder_card.dart` | Card with status pill (upcoming/in-progress/completed) |
| `app/employees/page.tsx` | `features/employees/employees_list_screen.dart` | List + search; admin-only create/delete actions gated by `user.role` |
| `app/employees/[id]/page.tsx` | `features/employees/employee_detail_screen.dart` | Route param `id` via `go_router` path param |
| `components/AddEmployeeModal.tsx` | `features/employees/widgets/add_employee_modal.dart` | Includes avatar upload (multipart) |
| `app/sales/page.tsx` | `features/sales/sales_screen.dart` | Table/list + filters + import/export buttons |
| `components/AddSalesModal.tsx` | `features/sales/widgets/add_sale_modal.dart` | Product & frequency dropdowns map directly to the Django `choices` enums |
| `app/interactions/page.tsx` | `features/interactions/interactions_screen.dart` | Same pattern as Sales |
| `components/AddInteractionsModal.tsx` | `features/interactions/widgets/add_interaction_modal.dart` | Validate `follow_up_date >= date` client-side too (mirrors the DRF serializer's `validate()`) |
| `components/AddReminderModal.tsx` | `features/reminders/widgets/add_reminder_modal.dart` | Repeat-type + repeat-days selector |
| `app/info-portal/page.tsx` | `features/info_portal/info_portal_screen.dart` | Tabbed (Sales/Interactions) admin table with search/filter/edit/delete — biggest single screen, budget extra time |
| `app/profile/page.tsx` | `features/profile/profile_screen.dart` | |
| `components/Navbar.tsx` / `components/Sidebar.tsx` | `shared/widgets/app_navbar.dart` / `app_sidebar.dart` | Consider `NavigationRail` on wide/desktop layouts, drawer on mobile |
| `app/not-found.tsx` | `go_router`'s `errorBuilder` | |

---

## 6. Migration Phases

**Phase 0 — Setup (0.5–1 day)**
- Scaffold Flutter project, add packages above, set up `flutter_lints`
- Stand up `ApiClient` (Dio) pointed at the existing Django backend (confirm dev/staging URL + CORS allows the Flutter web build's origin if targeting web)

**Phase 1 — Core plumbing (2–3 days)**
- Models for Employee/Client/Sale/Interaction/Reminder/User + JSON (de)serialization
- `AuthProvider` + token refresh interceptor + secure storage
- `go_router` setup with auth + role-based redirect guards (mirrors the `useEffect` checks scattered across the Next.js pages)
- Theme (colors/typography) to approximate the current Tailwind design tokens from `globals.css`

**Phase 2 — Auth + Dashboard (2–3 days)**
- Login screen
- Dashboard screen + TodoWidget + reminder cards

**Phase 3 — Employees (2–3 days)**
- List, detail, add/edit modal (with avatar upload), delete

**Phase 4 — Sales & Interactions (4–6 days)**
- Both CRUD screens, shared filter/search/table scaffold
- Excel export (download) and import (file pick + multipart upload)

**Phase 5 — Reminders + Info Portal (3–4 days)**
- Reminder modal + repeat logic
- Info Portal's tabbed combined admin view (reuses Phase 4's table scaffold)

**Phase 6 — Profile + polish (2–3 days)**
- Profile/settings screen, password change/forgot flows
- Empty/error/loading states, responsive layout pass (phone vs tablet/desktop/web)

**Phase 7 — QA + platform builds (2–3 days)**
- Manual test pass against the real backend for every endpoint in §3
- Android + iOS builds; Web build if needed (confirm Django CORS/static config supports it)

**Total: ~3–4.5 weeks** for one developer at a steady pace, before design polish beyond "matches current app."

---

## 7. Open Questions to Confirm Before Starting

1. **Target platforms** — phone-only, or also tablet/web/desktop? (Affects whether Sidebar becomes a `Drawer` or a permanent `NavigationRail`, and how much the data-heavy tables need a responsive redesign.)
2. **Design fidelity** — pixel-match the existing Tailwind UI, or "same features, clean native Flutter look"? This significantly changes the theming effort.
3. **Backend URL/environment** — is there a staging API URL, or should this initially point at `http://127.0.0.1:8000` like the current `.env` default?
4. **Avatar/image hosting** — confirm the Django `MEDIA_URL` will be reachable from mobile devices (not just `127.0.0.1`) once this leaves local dev.
5. **Excel import/export UX on mobile** — exporting a file on a phone means "save to Downloads" or "share sheet" rather than a browser download; confirm which is preferred.

---

## 8. Package Cheat-Sheet (React/Next → Flutter)

| React/Next concept | Flutter equivalent |
|---|---|
| `next/navigation` (`useRouter`, `usePathname`) | `go_router` (`context.go()`, `GoRouterState`) |
| React Context (`AuthContext`) | Riverpod `Notifier`/`StateNotifier` |
| `fetch` + manual header injection (`utils/api.ts`) | `dio` + `Interceptor` |
| `localStorage` | `flutter_secure_storage` (tokens) / `shared_preferences` (everything else) |
| `react-hot-toast` | `fluttertoast` or `ScaffoldMessenger.showSnackBar` |
| `lucide-react` | `lucide_icons` |
| Tailwind utility classes | `ThemeData` + reusable `BoxDecoration`/`TextStyle` constants |
| `next/image` | `Image.network` / `cached_network_image` |
| HTML `<input type=file>` (Excel import) | `file_picker` |
| Browser file download (Excel export) | `dio` download + `path_provider` + `share_plus` |

---

*Prepared from a direct read of `server/core/models.py`, `server/backend/urls.py`, `server/core/serializers.py`, `server/core/views.py`, and all files under `client/src/`.*
