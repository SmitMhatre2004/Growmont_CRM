# Growmont CRM — Flutter App

Flutter client for the Growmont Employee Portal. Connects to the existing Django REST API in `../server/` unchanged.

## Prerequisites

- Flutter SDK 3.12+
- Django backend running (default: `http://127.0.0.1:8000`)

## Setup

```bash
cd flutter_app
flutter pub get
```

## Run

```bash
# Default API: http://127.0.0.1:8000
flutter run

# Custom API URL
flutter run --dart-define=API_URL=https://your-api.example.com
```

## Features

| Screen | Route | Description |
|--------|-------|-------------|
| Login | `/` | JWT auth with secure token storage |
| Dashboard | `/dashboard` | Follow-ups, recent sales, reminders, sticky notes |
| Sales | `/sales` | CRUD, product filter, Excel import/export |
| Interactions | `/interactions` | CRUD, search, Excel import/export |
| Employees | `/employees` | Admin-only list, create/edit/delete |
| Employee Detail | `/employees/:id` | Profile, clients, sales |
| Info Portal | `/info-portal` | Admin tabbed sales/interactions view |
| Profile | `/profile` | User info, tabs for sales/interactions/reminders |

## Architecture

- **State:** `flutter_riverpod`
- **Routing:** `go_router` with auth + role guards
- **HTTP:** `dio` with JWT interceptors and 401 handling
- **Storage:** `flutter_secure_storage` (tokens), `shared_preferences` (sticky notes)

## Backend CORS

If targeting Flutter web, ensure Django `CORS_ALLOWED_ORIGINS` includes your web app's origin.
