# App Store Connect submission — I Can See!

Pre-filled metadata for App Store Connect. Copy each field into the
matching screen in App Store Connect. Square brackets `[ ]` mean the field
needs a decision from you before submission.

---

## App Information

| Field | Value |
|---|---|
| Name | `I Can See!` |
| Subtitle | `Camera color identifier` |
| Bundle ID | `com.jtrant.i-can-see` |
| SKU | `i-can-see-1` |
| Primary language | English (U.S.) |
| Primary category | Medical |
| Secondary category | Utilities |
| Content rights | Does **not** contain third-party content |
| Age rating | 4+ (see *Age Rating* section below) |

> **Why "Medical" primary?** The app is built for colorblindness — an
> accessibility/medical accommodation, not a photo utility. "Medical" is
> the closest fit and rewards discoverability for the affected audience.
> If you'd rather avoid medical-class regulatory scrutiny, switch to
> **Utilities** primary / **Medical** secondary.

---

## Pricing and Availability

| Field | Value |
|---|---|
| Price | **Free** |
| Availability | All countries/regions |
| App Distribution | Public (App Store) |
| Pre-orders | No |

---

## Version Information (1.0)

### Promotional Text (170 char max)
> Identify the color in front of you, instantly. Aim your camera or load a
> photo — I Can See! names what you're looking at. Built for colorblindness.

### Description (4000 char max)
> **I Can See!** turns your iPhone camera into a color identifier — built
> from the ground up for people with red/green, blue/purple, and other
> forms of color vision deficiency.
>
> Aim the camera at anything. A crosshair in the middle of the screen
> samples the color in real time, and the name appears in big, readable
> text underneath: *Red. Crimson. Olive. Teal. Lavender.* Tap once to
> freeze the reading so you can study it.
>
> No camera? Tap the photo button to load any image from your Photos
> library or Files. Drag the loupe to pick a specific pixel and see what
> color it really is — useful for shopping online, picking paint, or
> double-checking a chart.
>
> **What makes the naming useful**
> - 31 carefully chosen names — the ones people actually say out loud.
> - Distances are computed in CIE Lab color space, so dark navy is
>   correctly called *Navy* (not *Black*), and pale yellow is *Yellow*
>   (not *White*).
> - The palette deliberately separates the red/green and blue/purple
>   pairs that confuse most colorblind viewers.
>
> **Private by design**
> - The camera feed never leaves your phone.
> - No account. No cloud. No tracking of what you point at.
> - Anonymous, aggregate usage signals only (via TelemetryDeck).
>
> Requires iOS 17 or later.

### Keywords (100 char max, comma-separated)
> colorblind,color blind,daltonism,deuteranopia,protanopia,tritanopia,accessibility,color picker,color id

### Support URL
`https://[YOUR_DOMAIN_OR_GITHUB_PAGES]/icansee/support.html`

### Marketing URL (optional)
`https://[YOUR_DOMAIN_OR_GITHUB_PAGES]/icansee/`

### Privacy Policy URL (required)
`https://[YOUR_DOMAIN_OR_GITHUB_PAGES]/icansee/privacy.html`

### Copyright
`© [YEAR] Justin Trant`

### Version Release
[ ] Manually release after approval **(recommended for v1.0)**
[ ] Automatically release

### What's New in This Version (v1.0)
> First release. Point your camera at a color or load a photo from your
> library — I Can See! names what you're looking at.

---

## Build

| Field | Value |
|---|---|
| Marketing Version | `1.0` |
| Build Number | `1` |
| Minimum iOS | `17.0` |
| Device Family | iPhone (portrait only) |
| Encryption (ITSAppUsesNonExemptEncryption) | `false` (set in Info.plist) |

---

## App Review Information

| Field | Value |
|---|---|
| Sign-in required | **No** |
| Demo account | Not applicable |
| Contact First name | `Justin` |
| Contact Last name | `Trant` |
| Contact Phone | `[YOUR_PHONE]` |
| Contact Email | `justin.trant@me.com` |

### Notes for the Reviewer
> The app uses the rear camera to read the color at the center of the
> frame and display its closest human-readable name (e.g. "Red", "Teal").
> The crosshair on screen marks the exact pixels being sampled. Tap
> anywhere on the preview to freeze/unfreeze the reading.
>
> The photo button (top-right, photo icon) opens the system Photos picker
> or Files importer; load any image and drag the on-screen loupe to
> identify the color at any pixel.
>
> Camera access prompt: "I Can See uses the camera to identify colors in
> your surroundings."
>
> No account, no sign-in, no in-app purchase, no network calls except
> anonymous TelemetryDeck signals (App.launch, Camera.authorized,
> Reading.frozen). No user-generated content is ever transmitted.

---

## Age Rating questionnaire

All answers: **None**, except:

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Graphic Sexual Content and Nudity | None |
| Medical/Treatment Information | **None** (the app helps name colors; it does not give medical advice) |
| Unrestricted Web Access | No |
| Gambling | No |
| Gambling and Contests | No |
| User-generated Content / Social Networking | No |
| Made for Kids | No |

Expected resulting rating: **4+**.

---

## App Privacy ("Privacy Nutrition Label")

When asked "Does this app collect data?": **Yes — Diagnostics only.**

Then fill out the matrix below. Anything not listed = "Not Collected".

### Diagnostics → Crash Data / Performance Data / Other Diagnostic Data
- **Linked to user?** No
- **Used for tracking?** No
- **Purpose:** App Functionality, Analytics
- **What is sent?** Anonymous event signals only:
  - `App.launch`
  - `Camera.authorized` / `Camera.denied`
  - `Reading.frozen` / `Reading.resumed`
- TelemetryDeck hashes the device identifier with a salt; Anthropic
  receives no raw IDFA, IP, or reversible device ID.

Everything else (camera frames, sampled colors, hex values, photo
contents, location, contacts, health, financial, identifiers, usage,
purchases, search history, browsing history) = **Not Collected**.

---

## Third-party / SDK disclosures

| SDK | Purpose | Data collected |
|---|---|---|
| TelemetryDeck | Anonymous usage signals | Hashed device identifier + named events only. No PII. |

---

## Screenshots required

App Store Connect requires at least:

- **6.9" iPhone (iPhone 17 Pro Max / 16 Pro Max)** — 1320 × 2868 px, portrait
- **6.5" iPhone (iPhone XS Max)** — 1242 × 2688 px, portrait *(can be reused from 6.9 if you do not have an XS Max simulator handy)*

Recommended set (3–5 screenshots):

1. Live camera view aiming at a red apple → "Red" in the readout.
2. Live camera view on a green leaf → "Green".
3. Frozen reading with the swatch + hex code visible.
4. Photo-inspector mode with the loupe on a flower's petal.
5. The first-run welcome screen.

Quickest way: build to a simulator, use the iOS Photos library to load a
known-color photo, then ⌘S to save the screenshot to Desktop.

---

## Export Compliance

`ITSAppUsesNonExemptEncryption = false` is already in
[Info.plist](../ICanSee/Info.plist) — App Store Connect will not prompt
you for further encryption documentation.

---

## Submission checklist

- [ ] Update **Copyright** year above.
- [ ] Replace `[YOUR_DOMAIN_OR_GITHUB_PAGES]` in the three URLs.
- [ ] Publish `docs/index.html`, `docs/support.html`, `docs/privacy.html`
      to GitHub Pages (or your own host) and verify all three load.
- [ ] Add `[YOUR_PHONE]` to App Review contact info.
- [ ] Take screenshots (see above).
- [ ] Bump `MARKETING_VERSION` in `project.yml` if not 1.0.
- [ ] Archive in Xcode (Product → Archive → Distribute App → App Store
      Connect → Upload).
- [ ] In App Store Connect: attach build, paste in all of the above,
      submit for review.
