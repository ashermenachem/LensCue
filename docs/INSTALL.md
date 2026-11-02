# Install LensCue

[← Back to LensCue](../README.md)

## The easy way

1. Open [Releases](https://github.com/ashermenachem/LensCue/releases/latest).
2. Under **Assets**, download **LensCue-macOS-AppleSilicon.zip**. This is the app download; “Source code” is for developers.
3. Double-click the ZIP in Finder. Drag **LensCue.app** to **Applications**.
4. Open **Applications → LensCue**.
5. Paste a script, leave **Follow my words** selected, then click **Start presenting**.
6. Allow Microphone and Speech Recognition. The editor hides and the words appear below the camera. Speak naturally.

**Requirements:** Apple silicon Mac (M1 or newer), macOS 14+. Intel downloads are not provided yet. A physical notch is optional.

## macOS says the developer cannot be verified

The release is ad-hoc signed, not notarized by Apple. A downloaded copy may trigger a first-launch warning.

If you trust this release, first try opening the app normally. Then open **System Settings → Privacy & Security** and look for the LensCue message. Click **Open Anyway** and confirm **Open**. The exact wording varies by macOS version. See [Apple’s first-launch guidance](https://support.apple.com/en-us/102445). Do not turn off Gatekeeper. If your Mac is managed by a school or employer, its administrator may restrict opening unsigned apps.

Building the source locally is another option; see the [README](../README.md#build-it-yourself).

## The script does not move

- Confirm that you pressed **Start presenting**, and that your pointer is away from the overlay. Hovering pauses it.
- In **System Settings → Privacy & Security**, check **Microphone** and **Speech Recognition** for LensCue. Quit and reopen after changing permissions.
- **Follow my words** needs English on-device speech recognition. If the app reports an unavailable offline model, try **Voice activity**. LensCue does not send audio to a cloud recognizer as a fallback.
- Read the written script, or click a word in the overlay to resume from a different place.
- For **Voice activity**, lower the microphone threshold before starting if your voice is too quiet to trigger it. Increase it if background sound causes scrolling.

## Bring back the editor

Double-click the overlay. Or choose **Edit script** from the LensCue menu bar icon. Clicking the LensCue Dock icon also brings back the editor. `⌘ E` works while LensCue is the active app.

## Keyboard shortcuts do not work in another app

Use the LensCue menu bar icon. Global shortcut detection can depend on macOS input-monitoring permissions. You do not need to grant Accessibility access just to use the editor and menu bar controls.

## Where does my script go?

LensCue stores the current script and settings in local app preferences under `com.ashermenachem.lenscue`. It does not sync them to an account. Import supports plain UTF-8 text files.

## Updating

Quit LensCue. Download and unzip the newer release. Replace the app in Applications and reopen it. Your script and preferences use the same bundle identifier and are kept separately from the app.

## Verify the download (optional)

Download `SHA256SUMS.txt` beside the ZIP. Put both files in the same folder, open Terminal there, then run:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

This detects an accidental mismatch; a checksum from the same release is not an independent security guarantee.
