**Starlite for iPhone 0.3.7**

- **The widget plays through your queue by itself:** it knows the next six songs (with covers) and moves on when each one ends, without Starlite having to ask iOS for a refresh (iOS allows only a few of those a day while Starlite is in the background).
- If Starlite was closed while playing, the widget shows the song stopped instead of a timer that keeps running.

- **The widget follows what the player really does:** its bar starts when the song really starts (after loading), stops while it loads more, and stops when you pause, from anywhere. It also follows the playback speed.

- **The widget shares a folder with the app again when sideloaded:** Feather, Sideloadly and AltStore rename the App Group when they sign the app; Starlite now reads the real name out of its own signature (and the names they leave behind), so the widget reads the song, the covers and its settings straight from the app's files. It moves on by itself when a song ends, and follows play / pause, jumps in the song and likes.
- The cover stays in full colour on Clear and Tinted home screens.
- Starlite only asks the widget to refresh when something you can see changes.
- **Widget Log** (Settings → Widget): what the app and the widget did, step by step, with Copy and Share.
- The time left sits at the right edge of the widget.

**Install:** needs iOS 26. The IPA isn't signed: install it with Feather, AltStore or Sideloadly.
