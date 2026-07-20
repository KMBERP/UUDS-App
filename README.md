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

Photos are saved on-device in two places:
```
Private working copy (always reliable, used by the app itself):
  Android/data/com.uudsaero.uuds_parts_app/files/UUDS/[Aircraft Reg]/[Receiving or Dispatch]/[Part Location]/IMG_....jpg

Public Gallery copy (visible in Photos/Gallery app and any file manager):
  Pictures/UUDS/[Aircraft Reg]/[Receiving or Dispatch]/[Part Location]/IMG_....jpg
```
The public copy is written using Android's MediaStore API, so no special
"All files access" permission is needed — just the normal camera permission.

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

## Update 7 (auto-logout robustness, Gallery Receiving/Dispatch tabs, splash icon pause)
1. **Auto-logout after 10 minutes, made more robust.** Rebuilt the inactivity check to compare
   real timestamps on a recurring 15-second check (and again the instant the app returns to
   the foreground), instead of relying on a single delayed timer - Android can quietly delay
   or drop a lone timer like that when the screen locks or the app sits in the background,
   which is the most likely reason it wasn't firing reliably before. If it still doesn't log
   out after 10 real minutes of no screen touches once this build is installed, that's a sign
   this specific update didn't make it into the APK - worth double-checking the GitHub Actions
   build picked up this exact file (`utils/inactivity_guard.dart`).
2. **Gallery now opens into an aircraft picker first**, then a **Receiving / Dispatch tabbed
   view** for whichever aircraft you tap - each tab shows just that inspection type's photos,
   grouped by location, same as before. Backup and search-by-registration stay on the aircraft
   picker screen; select-and-share and delete stay on the per-aircraft tabbed view.
3. **Splash screen aircraft icon** - tapping it now pauses the icon exactly where it is (and
   holds off the automatic move to Home) until tapped again to resume. Tapping anywhere else
   on the splash screen still does nothing, so this is now a deliberate, precise interaction
   rather than the screen reacting unpredictably to any tap.

## Update 6 (import existing photos from gallery)
You can now add a photo you already have (taken earlier, or received via WhatsApp/email) to
any aircraft/inspection type/location, instead of only being able to use a freshly-taken
camera photo. On the camera screen, tap the new gallery icon in the top-right of the app bar,
pick one or more existing photos, and they're filed exactly like a live photo would be — same
private working copy, same public Gallery mirror folder, same database record, and they show
up in the same "Finish" summary and thumbnail strip as anything taken with the camera.

## Update 5 (fixed: reinstalling wouldn't update the app)
**Root cause:** every CI build was signing the release APK with a random, throwaway debug
key that GitHub's build server generates fresh on every single run (nothing persists it
between runs). Android treats an app signed with a different key as a different app, so it
refused to install "as an update" over the one already on the phone — the only way in was to
uninstall the old one first.

**Fix:** generated one permanent signing key (`signing/uuds-release.keystore.jks`, committed
to the repo, valid 30 years) and wired it into the build so every future build — no matter
how many times CI runs — signs with the exact same key. From this build onward, installing a
newer APK over the current one will update it in place, no uninstall needed.

**⚠️ Important — do not delete the `signing/` folder from the repo.** It's the one and only
copy of the signing key. If it's ever lost, every future build would need a brand-new key
again, meaning one more forced uninstall to move to it (and there's no way to recover
anything signed with the lost key). Since this file now lives in your GitHub repo, GitHub
itself is your backup — just don't delete or overwrite that folder.

Note: today's update to fix this is itself a one-time exception — installing today's APK
over your current one will still need one uninstall (since today's is the first build using
the new permanent key, and it doesn't match whatever key your currently-installed copy has).
Every build after today should update normally.

## Update 4 (admin rights, bulk delete, splash tap fix)
1. **Staff ID 476 (Khurram Munir) is now an admin.** Admin status unlocks bulk-delete on the
   Aircraft and Part Location screens (a delete-multiple icon appears in the app bar only for
   this account). To add more admins later, it's a one-line change in `utils/session.dart`.
2. **Bulk delete for aircraft and locations** — tap the new icon in the app bar to enter
   selection mode, check off as many aircraft/locations as you like, then confirm to delete
   them all at once. Past photo records are always kept regardless.
3. **Splash screen no longer reacts to taps at all** — previously a tap on the splash screen
   could interrupt/pause it, needing a second tap to move on. It now ignores all touch input,
   so it always finishes its animation and moves to Home on its own after 5 seconds no matter
   what's tapped.

## Update 3 (auto-logout, per-aircraft locations, roster cleanup)
1. **Auto-logout after 10 minutes of inactivity** — if nobody taps, scrolls, or otherwise
   touches the screen for 10 minutes, the signed-in inspector is automatically logged out
   app-wide (same end state as the manual double-back-press logout on Home) and the app
   lands back on a fresh Home screen with no inspector selected.
2. **Part locations are now independent per aircraft** — previously all aircraft shared one
   single list of locations behind the scenes, so adding, renaming, or deleting a location
   while working on one aircraft silently changed the list for every other aircraft too.
   Each aircraft now gets its own copy of the standard location list the moment it's added,
   and from then on every add/edit/delete only ever affects that one aircraft. Existing
   installs are migrated automatically (each aircraft you already had keeps a copy of
   whatever was in the old shared list — nothing is lost).
3. **Removed Paresh Abraham from the inspector roster** — he no longer appears as a
   selectable inspector on already-installed devices once they update (existing photo
   records already logged under his name are left untouched, as a historical record).

## Production fixes (previous update)
1. **Splash screen aircraft icon** — was climbing diagonally up-and-right at 45°; now flies
   fully horizontal, nose pointing straight right, and is noticeably larger.
2. **Public Gallery folder structure** — photos are now mirrored into the device's Photos/
   Gallery app via Android's MediaStore API, correctly nested as
   `Pictures/UUDS/[Aircraft]/[Receiving or Dispatch]/[Part Location]/...`. This replaces the
   old "All files access" permission approach, which Android often silently refused to grant
   (so photos quietly fell back to a private folder and never appeared in the Gallery). The
   new approach needs no special permission at all, and is compliant with Play Store policy.
3. **Inspector "logout" when switching tabs** — tapping Gallery/Reports and back to Home no
   longer clears the selected inspector. The signed-in inspector is now held in memory for
   the whole app session and only clears on the intentional double-back-press logout on Home
   (or if the app process is fully killed and relaunched).
4. **Finish button save summary** — the dialog shown after tapping Finish in the camera
   screen now always states how many photos were saved, the inspector/aircraft/type/location,
   the exact on-device folder, and whether each photo was also mirrored to the Gallery.
