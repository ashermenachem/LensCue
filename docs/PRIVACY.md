# Privacy

[← Back to LensCue](../README.md)

LensCue has no account system, analytics SDK, advertising, backend, or third-party Swift dependencies.

## Script and settings

The current script and overlay settings are saved using macOS `UserDefaults`, under the app's bundle identifier `com.ashermenachem.lenscue`. Imported text is read from the file you choose. This information is not uploaded by LensCue. App preferences are local storage, not an encrypted vault; avoid putting secrets into scripts.

## Microphone

Voice modes request microphone permission. Audio buffers are used while presenting and are not saved to disk by LensCue. Pausing, finishing, or quitting stops its audio engine. Auto-scroll does not start a microphone session.

## Speech recognition

Word-following requests Apple's English `SFSpeechRecognizer`. The app checks `supportsOnDeviceRecognition` and explicitly sets `requiresOnDeviceRecognition = true`. If on-device support is unavailable, it shows an error instead of selecting a cloud recognizer. Model availability and downloads are managed by macOS.

Voice activity uses microphone sound levels rather than a speech recognizer. It can respond to other people and ambient noise; it does not identify the speaker.

## Screen capture

The app does not guarantee that its overlay is excluded from screen recording or sharing. If this matters, share only the relevant app window and check the audience's view before presenting.

## Project links

Opening GitHub links or downloading releases uses GitHub's services and privacy terms. Those links are separate from the native app's reading and voice-following functions.
