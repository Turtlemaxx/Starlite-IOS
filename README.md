<p align="center">
  <img src="Starlite/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="Starlite">
</p>

<h1 align="center">Starlite for iPhone</h1>

<p align="center">
  The iPhone version of <a href="https://github.com/Turtlemaxx/Starlite">Starlite</a>, the music player for your own server.<br>
  <a href="https://github.com/Turtlemaxx/Starlite-IOS/releases/latest"><b>Download the IPA</b></a>
</p>

Starlite plays your music from **Navidrome** or **Jellyfin**, and songs you keep on your iPhone. It looks like Starlite on the computer, with a bit of Apple Music: a Liquid Glass tab bar with the song you're playing on it, big covers, Play and Shuffle side by side.

## What's in it

- **Music Server:** your server's playlists and newest albums, and a search. Save any server playlist into your own playlists.
- **Playlists:** Liked Music and Downloaded Music at the top, then your playlists as big CD cases on shelves (or a list). Songs are a plain list: swipe to like, play next or remove, long press for more.
- **Now Playing:** the cover over its own colours, seek bar, volume, AirPlay, shuffle, repeat and what plays next. Keeps playing in the background, with the lock screen's controls.
- **Downloads:** download songs (or whole playlists) to play without a connection, or put music files in the Files app (On My iPhone → Starlite).
- **Settings**, as customizable as on the computer: themes (Dark, Light, Cherry Blossom, Stars, Bubbles, your own colours and picture), panels (Liquid Glass, frosted or solid), corners, accent (the theme's, the playing cover's or your own), text size, icon weight, motion, song rows, the CD shelf, streaming and download quality, haptics. Save a look and switch between your looks.

Server logins are kept in the Keychain as tokens, never as your password.

## Install

Needs iOS 26 or newer (for Liquid Glass).

The IPA on the [releases page](https://github.com/Turtlemaxx/Starlite-IOS/releases/latest) isn't signed (there's no App Store version). Install it with a sideloading tool that signs it with your own Apple ID, like [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io). With a free Apple ID, apps need signing again every 7 days.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen
xcodegen generate
open Starlite.xcodeproj
```

Needs Xcode 26. Every push is built on GitHub's Macs (`.github/workflows/ios.yml`), which also take screenshots in the simulator; a tag `v*` publishes the IPA as a release.

For screenshots, `-StarliteDemo YES` starts with made-up songs and playlists (nothing is saved, nothing goes over the network), and `-StarliteScreen playlists|playlist|nowplaying|server|settings|appearance|layout|light|bubbles` opens that screen.
