# NovaTap ⚡ Enterprise Live Engagement Engine for iOS

`NovaTap.dylib` is an enterprise-grade, crash-proof, PAC-resilient native dynamic library engineered for automated TikTok Live engagement. It is optimized specifically for Apple Silicon hardware (A15 Bionic ARM64e with Pointer Authentication Codes) and ProMotion 120Hz displays.

---

## 🏗️ Architecture & Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                 TikTok Runtime Process Space                │
│                                                             │
│  ┌──────────────────────┐        ┌───────────────────────┐  │
│  │   BHTikTok.dylib     │        │     NovaTap.dylib     │  │
│  └──────────────────────┘        └───────────┬───────────┘  │
│                                              │              │
│       ┌──────────────────────────────────────┴───────────┐  │
│       │                                                  │  │
│  ┌────▼─────────────────┐            ┌───────────────────▼┐ │
│  │   NovaTapHUD (UI)    │            │  NovaTapEngine     │ │
│  │ • Pure UIKit Overlay │            │ • Serial BG Queue  │ │
│  │ • Glassmorphism      │            │ • Box-Muller Jitter│ │
│  │ • Arabic Controls    │            │ • Dwell Simulator  │ │
│  │ • Draggable / Pill   │            │ • Quota Engine     │ │
│  └──────────────────────┘            └───────────┬────────┘ │
│                                                  │          │
│                      Dual Dispatch Barrier       ▼          │
│             ┌─────────────────────────────────────────┐     │
│             │ Strategy 1: UITapGestureRecognizer Target│     │
│             │ Strategy 2: Responder touchesEnded Chain│     │
│             │ Collision Safety: UIPan Transition Check│     │
│             └─────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## 1. Zero-Crash & PAC-Resilience Guarantee
- **Dynamic Introspection:** Zero hardcoded memory offsets. Dynamic lookup via `objc_getClass("IESLiveRoomViewController")` and target action selectors.
- **ARM64e / PAC Safety:** Pure ABI-compliant invocations wrapped in `@try ... @catch` barriers.
- **Gesture Collision Guard:** Continually polls the container's `UIPanGestureRecognizer`. When a vertical swipe begins (`UIGestureRecognizerStateBegan` / `Changed`), tapping instantly freezes to prevent deadlocks and dangling pointers.
- **Viewport Safe Zone:** Automatically clamps coordinates to the center-right viewport (55%–82% X, 25%–72% Y), strictly avoiding the bottom 20% (gifts/chat) and top 15% (profile/exit).
- **ProMotion 120Hz & Thermal Guard:** All calculations, Box-Muller transforms, and cadence sleeps run on `com.novatap.bgqueue`. Only the single synthetic dispatch touches the Main Thread.
- **Audio & Lifecycle Observers:**
  - Disables screen sleep during active runs (`idleTimerDisabled = YES`).
  - Auto-pauses on `UIApplicationDidEnterBackgroundNotification`.
  - Gracefully handles phone calls and AirPods disconnects via `AVAudioSessionInterruptionNotification`.

---

## 2. Advanced Anti-Detection Biometrics
1. **Touch Dwell Duration:** Emulates real capacitive screen contact physics (35ms–70ms between TouchDown and TouchUp).
2. **2D Bivariate Gaussian Jitter:** Uses Box-Muller transformation ($\sigma \approx 12\text{px}$, clamped to $\pm 26\text{px}$) to emulate physiological human thumb inaccuracy.
3. **Fatigue Cadence & Micro-Drifts:**
   - Bursts of 25–40 taps followed by 2.0s–4.0s breathing rest.
   - Macro-rest (8s–14s) every 450–600 cumulative taps.
   - Strict rate ceiling: 6–7 taps/second max.
   - Automatic pause and completion alert upon reaching target quota (e.g., 10,000 taps).

---

## 3. Minimalist Embedded HUD (Arabic Interface)
- **Zero Asset Dependencies:** Rendered 100% via programmatic UIKit and native Apple SF Symbols. No external `.bundle` files.
- **Palette:** Deep Midnight Navy (`#0A1128`), Deep Maroon (`#5C061C`), and Crisp White.
- **Controls:**
  - `تشغيل / إيقاف مؤقت` (Play / Pause)
  - `العداد اللحظي والنسبة المئوية` (Progress / Target Quota)
  - `وضع السرعة (آمن 🛡️ / قياسي 🚀)`
  - `إعادة ضبط العداد ↺`
  - `تصغير إلى فقاعة جانبية ⚡` (Draggable floating badge)
- **Haptic Discipline:** Restricted to session start and quota completion only.

---

## 4. GitHub Actions CI/CD Setup

The workflow in `.github/workflows/build.yml` compiles `NovaTap.dylib` for both `arm64` and `arm64e`, sanitizes the target IPA, and injects the dynamic library.

### Triggering the Workflow:
1. Push this repository to GitHub.
2. Go to **Actions** -> **NovaTap Enterprise CI/CD Pipeline**.
3. Click **Run workflow**.
4. *(Optional)* Provide a direct download link (`ipa_url`) to your decrypted BHTikTok / TikTok IPA.
5. The pipeline automatically:
   - Compiles `NovaTap.dylib` using Apple's Clang with `-arch arm64 -arch arm64e`.
   - **Strips `PlugIns/`, `Watch/`, and `Extensions/`** from the IPA. This is critical for free Apple IDs to avoid exhausting the 10 App ID weekly quota in SideStore!
   - Injects `NovaTap.dylib` into the Mach-O binary using `insert_dylib`.
   - Produces `TikTok_BHTikTok_NovaTap.ipa` as an artifact.

---

## 5. Turnkey Deployment Guide: Windows 11 to iPhone 13 Pro Max (SideStore)

### Step 1: Install Prerequisites on Windows 11
1. Install **iTunes (Direct Apple Installer, NOT Microsoft Store version)**:
   - Download iTunes x64 from Apple.
2. Install **iCloud for Windows (Direct Apple Installer)**:
   - Download the standalone installer and log into your Apple ID.
3. Install **SideServer** or **Sideloadly** on Windows 11.

### Step 2: Install SideStore on iPhone 13 Pro Max
1. Connect your iPhone 13 Pro Max to your PC via USB cable.
2. Open Sideloadly or SideServer.
3. Select `SideStore.ipa` and enter your burner Apple ID credentials.
4. Once installed on your device:
   - Go to **Settings -> General -> VPN & Device Management**.
   - Tap your Apple ID and select **Trust**.
   - On iOS 16+, enable **Developer Mode** under **Settings -> Privacy & Security -> Developer Mode** (Device will reboot).

### Step 3: Configure WireGuard Loopback VPN (100% On-Device Signing)
SideStore requires a local VPN loopback to communicate with the local pairing file without a computer:
1. Install **WireGuard** from the official App Store.
2. In SideStore, export the `SideStore.conf` WireGuard profile.
3. Open WireGuard, import the profile, and activate the tunnel.
4. Verify SideStore can refresh itself without connecting to your PC.

### Step 4: Install the Injected IPA via SideStore
1. Download `TikTok_BHTikTok_NovaTap.ipa` from your GitHub Actions artifacts onto your iPhone (via Safari or iCloud Drive).
2. Ensure WireGuard VPN is **ON**.
3. Open **SideStore** -> tap the **+** icon in the top-left corner.
4. Select `TikTok_BHTikTok_NovaTap.ipa`.
5. SideStore will sign and install the app seamlessly. Because `PlugIns/` were removed by our CI pipeline, only 1 App ID will be consumed!

### Step 5: Background Refresh Automation (Never Expire)
To keep the 7-day certificate automatically renewed:
1. Open the Apple **Shortcuts** app on your iPhone.
2. Go to the **Automation** tab -> tap **+** -> **Create Personal Automation**.
3. Select **Time of Day** (e.g., Daily at 3:00 AM).
4. Set action:
   - Turn WireGuard VPN **On**.
   - **Refresh Apps in SideStore**.
   - Wait 30 seconds.
   - Turn WireGuard VPN **Off**.
5. Disable "Ask Before Running". Your apps will now refresh automatically in the background.

---

## 6. Sideloaded Account Security & Burner Testing Protocol

### Recommended Login Authentication
When using sideloaded or tweaked TikTok clients:
- **Avoid:** "Sign in with Apple" or "Sign in with Google" (these can fail due to missing entitlements or bundle ID mismatches).
- **Recommended:** **Username + Password** or **Registered Email + Password**, with 2-Factor Authentication via SMS or Authenticator App.

### Burner Account Verification Protocol
1. **Initial Verification:**
   - Log in using a secondary/burner account.
   - Join any active live stream.
   - The NovaTap HUD will appear in the top-right corner.
2. **Observe Behavioral Engagement:**
   - Tap **▶ تشغيل التكبيس**.
   - Observe the live heart animation counter incrementing smoothly.
   - Confirm that the HUD counter tracks taps in real-time.
3. **Safety & Collision Verification:**
   - Swipe up/down to switch rooms while NovaTap is running.
   - Confirm the gesture collision guard activates and the app transitions cleanly with zero stutter or crashes.
4. **Thermal & Memory Check:**
   - Let NovaTap run for a 1,000-tap burst.
   - Check device temperature. The serial background queue execution ensures zero thermal throttling on the A15 Bionic 120Hz ProMotion display.
