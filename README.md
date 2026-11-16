# iverson.io

Speak Sound Names numbers (or glyph names like `plus`, `rho`) on your iPhone or Mac. Linked computers receive them over Bluetooth and type the matching glyphs.

## Link to a computer

1. Assign numbers to glyphs in the **iverson.io** desktop companion web UI (`../iverson-io`, Sound Names). See that README for full setup.
2. Build and run **iverson.io** (`Iverson.xcodeproj` in this folder) on iPhone or Mac.
3. Tap **Link** — a 4-digit code appears on screen.
4. On the computer (from the companion package):

```sh
cd ../iverson-io
pixi install -e app
pixi run receive --code 4821
# or: pip install 'iverson[app]' && iverson-receive --code 4821
```

Use the code shown in the app (example above uses `4821`).

5. In the companion **Sound Keyboard** page, choose a **Talk key** (Control, Option, …).
6. Focus a text field on the computer.
7. **Hold the Talk key**, speak a **3-digit** code in iverson.io (e.g. zero zero one), then **release** — the glyph is typed when all three digits are in.

Keep iverson.io in the foreground while Link is on.

## Bluetooth

Advertises as `iverson-XXXX` with the same GATT service as `iverson.bt` (`6e616461-6b69-7400-4b42-000000000001`).

## App Store Connect

| Field | Value |
| --- | --- |
| Name | iverson.io |
| Bundle ID | `io.iverson.app` |
| Version | 1.0 (build 1) |
| Category | Productivity |
| Platforms | iOS / iPadOS 26+, macOS 26+ |
| Encryption | Standard encryption only (`ITSAppUsesNonExemptEncryption = NO`) |
| Subtitle | Speak codes. Type glyphs. |

### Description (paste into App Store Connect)

```
iverson.io turns spoken Sound Names into text on your computer.

Speak a 3-digit code on your iPhone. When linked over Bluetooth, your Mac receives it and types the matching glyph into whatever app you’re using — editors, terminals, notes, chat.

How it works
1. Open iverson.io and tap Link. A 4-digit code appears.
2. On your Mac, run the iverson companion receiver with that code.
3. Hold your Talk key, speak three digits (for example “zero zero one”), then release.
4. The glyph is typed into the focused field.

Built for Sound Names
• Map numbers to glyphs in the iverson Sound Names UI on your Mac
• Speak digit codes or glyph names like “plus” or “rho”
• On-device speech recognition — audio stays on your phone
• Local Bluetooth link — no account, no cloud upload

Keep iverson.io in the foreground while Link is on. Requires a Mac running iverson-receive and a Talk key set in Sound Keyboard.

Simple voice input for the symbols you actually type.
```

### Privacy Nutrition Label (suggested answers)

Speech stays **on-device** (SpeechAnalyzer). BLE only sends **3-digit codes / glyph names** to a computer the user links — nothing is uploaded to your servers.

- **Data Not Collected** — if you do not transmit audio, identifiers, or analytics off-device.
- If App Review asks: microphone audio is processed on device for transcription; Bluetooth shares short text codes with the user’s nearby computer only.

Usage strings already in the binary:

- Microphone — spoken numbers / glyph names
- Bluetooth — link to computer for typing

### Before you upload

1. Open `Iverson.xcodeproj` in Xcode 26+.
2. Signing & Capabilities → select your Team (currently `AL57H9UVU5`).
3. Confirm App Icon shows in Assets (1024 marketing + Mac sizes).
4. Product → Archive (Any iOS Device / My Mac as needed).
5. Distribute App → App Store Connect.
6. In Connect, add:
   - Subtitle / description / keywords
   - Support URL + Privacy Policy URL (required)
   - Screenshots (6.7" and 6.5" iPhone; 13" iPad if shipping iPad; Mac if shipping Mac)
   - Review notes: “Hold Link, speak a 3-digit Sound Names code; optional Mac receiver uses `iverson-receive --code XXXX`.”
7. Answer export compliance: **No** (exempt / standard encryption only).

### Support & privacy (GitHub Pages)

Static pages live in `docs/`:

- Support: `https://alix559.github.io/iverson-ios/`
- Privacy: `https://alix559.github.io/iverson-ios/privacy.html`

Publish once:

```sh
cd iverson-ios
gh auth login   # if needed
gh repo create alix559/iverson-ios --public --source=. --remote=origin --push
gh api -X POST repos/alix559/iverson-ios/pages -f build_type=legacy -f source[branch]=main -f source[path]=/docs
```

In App Store Connect use Support URL `https://alix559.github.io/iverson-ios/` (and the same or the privacy URL for App Privacy if asked).
