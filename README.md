# UUDS Aircraft Parts Inspection App

Offline Android app for UUDS Aero DWC L.L.C. — photograph parts on Receiving/Dispatch
inspection and auto-organize them by Aircraft Reg No → Receiving/Dispatch → Part Location.
All data (photos + database) stays on the device. No internet needed to use the app.

## How to get the installable APK (takes ~5 minutes, no coding needed)

1. **Create a new GitHub repository** (e.g. `uuds-parts-app`) — you already have a GitHub
   account (`khurrammunir377-dot`) from the Ecostruct project, so use the same one.
2. Upload **all files and folders in this package** to that repo, keeping the same structure:
   ```
   source/           <- app code
   .github/workflows/build-apk.yml   <- auto-build robot
   README.md
   ```
   Easiest way: on github.com, create the repo, then use "Add file → Upload files" and drag
   this whole folder in (make sure the `.github` folder uploads too — GitHub sometimes hides
   dot-folders in the drag-drop UI; if it does, use `git` instead, see note below).
3. Once pushed, go to the **"Actions"** tab of your repo. A workflow called
   **"Build UUDS Parts Inspection APK"** will start automatically (takes ~5-8 minutes).
4. When it finishes (green check ✅), click into that run → scroll to **"Artifacts"** →
   download **UUDS-Parts-Inspection-APK.zip**. Unzip it — inside is `app-release.apk`.
5. Transfer that APK to your Android phone/tablet (email it to yourself, or USB, or
   Google Drive) and tap it to install. You'll need to allow "Install unknown apps" for
   that once (Android will prompt you automatically).

### If "Add file → Upload files" doesn't pick up the `.github` folder
Use git from a command line instead (or ask me and I'll give you exact commands for your
machine):
```
git init
git add .
git commit -m "Initial UUDS Parts Inspection app"
git branch -M main
git remote add origin https://github.com/khurrammunir377-dot/uuds-parts-app.git
git push -u origin main
```
The push itself triggers the build automatically.

## App Flow
1. **Select Employee** (inspector) performing the inspection — add new if not listed.
2. **Receiving Parts Inspection** or **Dispatching Parts Inspection**.
3. **Select Aircraft** — pick existing, or add new (enter 3 letters, auto becomes `A6-XXX`).
4. **Select Part Location** — pick existing, or add new.
5. **Camera opens** — tapping the shutter button **instantly captures and auto-saves** the
   photo (no separate "Save" step). Take as many photos as needed, then tap **Finish**.

Photos are saved on-device at:
```
UUDS_Aero_Photos/[Aircraft Reg]/[Receiving or Dispatch]/[Part Location]/IMG_....jpg
```

## Reports
From the Home screen → Reports: generate PDF reports (Photo Log, Aircraft-wise Summary,
Part Location Report), optionally filtered by date range, and share via WhatsApp/Email/
Bluetooth/USB — all offline, sharing just uses whatever app you pick.

## Notes / things you may want to tweak later
- App icon is currently the Flutter default — I can add your company logo as the app icon
  if you send me the image.
- No PIN/login is set up (single shared device assumption). Say the word if you want a
  simple PIN lock.
- Minimum Android version supported: Android 7.0 (covers virtually all work devices).
