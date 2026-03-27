# Delivery Router

Optimizes multi-stop delivery routes using an exact Held-Karp TSP solver, then opens the result in Google Maps for turn-by-turn navigation.

**Live**: https://delivery-router-314185672280.australia-southeast1.run.app

## How it works

1. Set your warehouse (depot) address
2. Add up to 20 delivery stops via Google Places autocomplete
3. Hit **Optimize Route** — the app fetches driving times from Google's Distance Matrix API and solves the Travelling Salesman Problem exactly using Held-Karp dynamic programming
4. Opens the optimized route in Google Maps — on mobile, tap "Start" for voice-guided navigation

## Architecture

```
Flutter web app (frontend)
  |
  |-- /maps-proxy/* --> Dart shelf server --> Google Maps APIs
  |                     (injects API key server-side)
  |
  +-- SharedPreferences (localStorage) for address history + saved stops
```

- **Frontend**: Flutter web (Dart) — address search, stop management, route display
- **Backend**: Dart `HttpServer` — serves the Flutter build, proxies Google Maps API calls with the API key injected server-side so it never reaches the browser
- **TSP Solver**: Held-Karp algorithm — O(n^2 * 2^n) exact solver, feasible up to ~20 stops
- **Hosting**: Google Cloud Run (australia-southeast1)

## Google Maps APIs used

| API | Purpose |
|-----|---------|
| Places API | Address autocomplete |
| Distance Matrix API | Driving times between all stop pairs |
| Directions API | Route polylines |
| Maps JavaScript API | In-app map display (optional) |

## Local development

```bash
# Prerequisites: Flutter SDK, Dart SDK

# Install dependencies
flutter pub get

# Build the web app
flutter build web

# Copy test data page into build
cp web/setup.html build/web/setup.html

# Run the server (API key as env var)
GOOGLE_MAPS_API_KEY=your_key_here dart run bin/server.dart

# Open http://localhost:9090
# Or seed test data: http://localhost:9090/setup.html
```

## Deployment

Deploys automatically to Cloud Run on push to `main` via GitHub Actions.

Manual deploy:
```bash
gcloud run deploy delivery-router \
  --project=knowledge-graph-app-kg \
  --region=australia-southeast1 \
  --source=. \
  --allow-unauthenticated \
  --port=8080 \
  --memory=512Mi \
  --set-env-vars="GOOGLE_MAPS_API_KEY=your_key_here"
```

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GOOGLE_MAPS_API_KEY` | Yes | Google Maps API key with Places, Distance Matrix, and Directions APIs enabled |
| `PORT` | No | Server port (default: 9090 locally, 8080 on Cloud Run) |
