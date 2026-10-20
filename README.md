# NutriLens AI

A personal Flutter app to track daily meals (breakfast/lunch/dinner/snack), scan food with AI, search nutrition via Gemini with Google Search grounding, and keep a local history of calories/macros.

## Features
- Log meals with meal type tagging
- Search any food/brand/dish with portion weight
- Plate photo scan (camera/gallery) using Gemini Vision
- Google Search grounding with source links
- Local SQLite diary with edit/delete
- History view by date
- Dark theme UI

## Setup
```bash
flutter pub get
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY --dart-define=GEMINI_MODEL=gemini-2.5-flash
```

## Build APK
```bash
flutter build apk --release --dart-define=GEMINI_API_KEY=YOUR_API_KEY
```

## Notes
For personal use only. API key passed via --dart-define.
