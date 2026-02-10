# CikguAI Project Setup (New Location)

## Prerequisites
1. **Python 3.9+** (for Backend)
2. **Flutter 3.0+** (for Frontend)
3. **Firebase Project** (Firestore, Auth, Storage enabled)
4. **Google Cloud Project** (Gemini API enabled)

## Step 1: Backend Setup
1. Navigate to `cikgu_ai_app/backend/`.
2. Place your Firebase service account key as `backend/serviceAccountKey.json`.
3. Create a `.env` file or set environment variable `GOOGLE_API_KEY` with your Gemini API Key.
4. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
5. Run the server:
   ```bash
   uvicorn backend.main:app --reload
   ```
   Server will run at `http://127.0.0.1:8000`.

## Step 2: Frontend Setup
1. Navigate to `cikgu_ai_app/frontend/`.
2. Open `lib/main.dart` and replace `firebaseOptions` with your web app configuration from Firebase Console.
3. Run the app:
   ```bash
   flutter run -d chrome
   ```

## Troubleshooting
- **CORS Error**: Ensure FastAPI has `CORSMiddleware` configured (already included).
- **Firebase Auth**: Ensure "Google Sign-In" is enabled in Firebase Console authentication providers.
- **Connection Refused**: On web, `localhost` works, but if testing on Android Emulator, use `10.0.2.2` instead of `127.0.0.1`.
