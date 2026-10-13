# Med Jars

An iPhone app for NFC-tagged pill and supplement jars. Tap a jar and its dose card opens: today's doses, what to avoid, absorption tips, a summary of what it does, and a one tap **Log dose** button.

## Features

- **Jars**: add, edit and delete medications and supplements, each with dose times, amounts, pill counts, how to take it, food rules, warnings, absorption tips and a summary.
- **Dose log**: every dose with date, time, amount and pill count. Undo, swipe to remove, export to CSV.
- **Double-dose guard**: warns before logging a dose that's already logged today.
- **Reminders**: a notification at each dose time with a Log dose button, skipped once you've logged it.
- **Widget**: Home Screen and Lock Screen widget showing the next dose (needs a certificate with App Groups).
- **Face ID lock**.
- **Shortcuts actions**: Open Jar and Log Next Dose, used by NFC automations.

All data stays on the phone in one JSON file. No accounts, no network.

## Install

Every push to `main` builds an unsigned `MedJars.ipa` on a GitHub Actions Mac and attaches it to the newest [release](../../releases/latest). Sign and install it with your certificate in Feather, ESign or Sideloadly.

## Link an NFC tag

1. Shortcuts app → Automation → **+** → **NFC** → **Scan**, then hold the phone to the jar.
2. Choose **Run Immediately**.
3. Add the Med Jars action **Open Jar** (or **Log Next Dose**) and pick the jar.

The app also opens links like `medjars://jar/<link-name>`.

## Build it yourself

```sh
brew install xcodegen
xcodegen generate
open MedJars.xcodeproj
```
