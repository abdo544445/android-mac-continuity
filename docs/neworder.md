Without a paid **$99/year Apple Developer ID** for notarization, macOS will always attach a quarantine flag to files downloaded through a web browser. However, **regular Mac users never need to use Terminal or build from source**—you can change how you package `ContinuityCompanion` so non-technical users can install and open it using only a few mouse clicks.

---

## 1. Distribute a `.zip` Instead of a `.dmg` (Cuts Security Popups in Half)

Because you are currently distributing `ContinuityCompanion-macOS-v1.0.3.dmg`, non-technical users get hit by Gatekeeper **twice**:

1. First, macOS blocks `ContinuityCompanion-macOS-v1.0.3.dmg` itself when they double-click it.


2. Second, after they bypass that and mount the disk image, macOS blocks `ContinuityCompanion.app` *again* when they try to launch it.



**The Free Fix:** Package the release as a **`.zip`** file instead of (or alongside) the `.dmg` in `scripts/release.sh` and `.github/workflows/ci.yml`:

* macOS's built-in **Archive Utility** unzips `.zip` files **without triggering Gatekeeper on the archive** (and Safari unzips `.zip` downloads automatically).
* Users can drag `ContinuityCompanion.app` straight to `/Applications` without any error popup, and only have to approve the app **once** on first launch.



Update `scripts/bundle_macos_app.sh` / `scripts/release.sh` to ad-hoc sign the app bundle and compress it with `ditto`:

```bash
# 1. Ad-hoc sign the app so Apple Silicon doesn't report it as "Damaged"
codesign --force --deep --sign - "ContinuityCompanion.app"

# 2. Package as a .zip (preserves macOS permissions and bundle metadata)
ditto -c -k --keepParent "ContinuityCompanion.app" "ContinuityCompanion-macOS-v1.0.3.zip"

```

---

## 2. Give Users a 1-Click Button to the GUI "Open Anyway" Setting

For non-technical users on macOS, the standard no-Terminal way to open an unsigned app takes 3 clicks:

1. Click **Done** on the `"Not Opened"` popup (not **Move to Trash**).


2. Open **System Settings** → **Privacy & Security**, scroll to the bottom, and click **Open Anyway**.
3. Authenticate with Touch ID or their Mac password (only required once; the app opens normally forever after).

### Make It Effortless: Bundle a `How to Open.html` Helper

Unlike `.app`, `.dmg`, or `.command` files (`scripts/Install-macOS.command`), **`.html` files are never blocked by Gatekeeper** when double-clicked. You can include a small `How to Open.html` file inside your `.zip` next to `ContinuityCompanion.app` with a button that opens **System Settings → Privacy & Security** directly:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>How to Open ContinuityCompanion</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 520px; margin: 40px auto; line-height: 1.5; color: #1d1d1f; }
    .btn { display: inline-block; background: #0071e3; color: #fff; padding: 12px 20px; border-radius: 8px; text-decoration: none; font-weight: 600; margin-top: 10px; }
    .card { background: #f5f5f7; padding: 20px; border-radius: 12px; margin-top: 16px; }
  </style>
</head>
<body>
  <h2>Opening ContinuityCompanion (First Time Only)</h2>
  <div class="card">
    <ol>
      <li>Drag <strong>ContinuityCompanion</strong> to your <strong>Applications</strong> folder and double-click it.</li>
      <li>When macOS shows the <em>"Not Opened"</em> popup, click <strong>Done</strong>.</li>
      <li>Click the button below to jump straight to <strong>Privacy &amp; Security</strong> settings, then click <strong>Open Anyway</strong> at the bottom:</li>
    </ol>
    <a class="btn" href="x-apple.systempreferences:com.apple.preference.security">
      Open Privacy &amp; Security Settings
    </a>
  </div>
</body>
</html>

```

When the user clicks **Open Privacy & Security Settings**, macOS jumps straight to the exact settings pane where the **Open Anyway** button is waiting.

---

## 3. Optional: Create a 1-Click "Apple Shortcut" Installer (Zero Gatekeeper Popups)

Every modern Mac comes with Apple's **Shortcuts** app pre-installed, and Apple allows you to share Shortcuts via an **iCloud link** signed for free with a standard Apple ID:

1. Open the **Shortcuts** app on your Mac and create a new Shortcut named **Install ContinuityCompanion**.


2. Add a **Run Shell Script** action containing:
```bash
curl -L "https://github.com/abdo544445/android-mac-continuity/releases/latest/download/ContinuityCompanion-macOS-v1.0.3.dmg" -o /tmp/ContinuityCompanion.dmg
hdiutil attach /tmp/ContinuityCompanion.dmg -nobrowse -quiet
cp -R "/Volumes/ContinuityCompanion/ContinuityCompanion.app" /Applications/
hdiutil detach "/Volumes/ContinuityCompanion" -quiet
xattr -cr /Applications/ContinuityCompanion.app
open /Applications/ContinuityCompanion.app

```


3. Share the Shortcut as an **iCloud Link** and put an **"Install via Apple Shortcuts"** button on your GitHub README.
(Note: Users only need to have "Allow Running Scripts" enabled once in **Shortcuts → Settings → Advanced**, and the Shortcut will download, install, unquarantine, and launch `ContinuityCompanion.app` with a single click and no Terminal window.)



Would you like me to update your `scripts/bundle_macos_app.sh` and `.github/workflows/ci.yml` so your GitHub Releases automatically build and publish this ready-to-use `.zip` package with the `How to Open.html` launcher included?
