PowerBar
===============

Pandora radio on a PowerPC Mac. PowerBar is a small native Cocoa player for
**Mac OS X 10.4 Tiger and 10.5 Leopard** on G3, G4 and G5 Macs, built around
[pianobar](https://github.com/PromyLOPh/pianobar), the console Pandora client.

- One universal PowerPC app: a separate build for each of G3, G4 and G5 (AltiVec on
  G4/G5), and the Mac picks the right one.
- Modern, verified HTTPS (OpenSSL 3 + curl, bundled), so it works with today's
  Pandora servers on a 2005 Mac.
- Your password is kept in your Keychain.

Using it
--------

Open the app and sign in with your Pandora account once. After that it signs in by
itself and picks up on the station you last played.

| | |
|---|---|
| Play/Pause | Space (or ⌘P) |
| Next song | → (or ⌘→), or Next on the "Up next" bar |
| Love / Ban / Tired | ⌘L / ⌘B / ⌘T |
| Change station | the menu at the top of the window |
| Time remaining / elapsed | click the time |

The Dock icon's menu has the same controls. Audio quality (Controls > Audio Quality)
defaults to High and drops to Medium by itself if your account doesn't offer High.

**Volume:** use the Mac's own volume. The app plays at a fixed level with a little
headroom and no per-song boost, so loud songs never distort.

**Everything else pianobar can do** is under the **Actions** button and the **Song**
and **Station** menus, each in its own small window:

- **Song:** why this song is playing, bookmark the song or artist, history (love,
  ban, tire or bookmark songs you've heard).
- **Station:** new station (search, from this song or artist, by genre, or a shared
  station's ID), add music, rename, delete.
- **Station Mode** (also the **Mode…** button): how Pandora picks songs for the
  station: My Station, Crowd Faves, Deep Cuts, Discovery and so on.
- **Station Seeds:** the artists, songs and stations a station was built from.
  Removing one stops Pandora from basing the station on it.
- **Thumbs Up & Down:** your ratings on the station. Removing one takes it back.
- **Shuffle Stations:** Shuffle (Pandora's old name: QuickMix) is a station of its own
  that mixes songs from the stations you check.
- **Explicit Content** (PowerBar menu): on or off for your Pandora account.

Cancel always closes the window and changes nothing.

Dashboard widget
----------------

**PowerBar › Install Dashboard Widget…** adds a small player to Dashboard: cover art,
song, artist and album, time left, and play/pause, next, love, ban and tired
buttons. Close the main window, press F12 (or your Dashboard key), and it's there.
It talks to the app in the background, so Dashboard stays open while you use it.
If PowerBar isn't running, the widget offers to open it.

Settings live in `~/Library/Application Support/PowerBar/` (pianobar's config
and state). PowerBar > Sign Out removes the saved password.

Updates
-------

**PowerBar › Check for Updates…** looks for a new version. The second time you open
PowerBar, it asks whether to check by itself once a day. When there's an update, it
shows what's new, then downloads, installs and reopens PowerBar for you. Updates
come from https://github.com/cmstuberg/PowerBar over verified HTTPS, and each one is
signed: PowerBar checks the signature before installing and refuses anything that
doesn't match. An installed Dashboard widget is brought up to date when the new
version starts. (Updates arrive this way from 0.7 on; 0.6 has to be replaced by hand.)

How it works
------------

The app runs pianobar (inside the bundle) and drives it through a private pipe: key
commands go in on its stdin, and its events and status come back on its stdout. See
`pianobar/README.md` and `powerbar/src/PPBEngine.h` in the source repository.

Licences
--------

PowerBar's own code is MIT licensed. It includes pianobar (MIT), Sparkle 1.5 (MIT;
the updater), ffmpeg (LGPL 2.1+, as replaceable dylibs in Contents/Frameworks),
OpenSSL (Apache 2.0), curl, zlib and json-c. Their licences are in
Contents/Resources/Licenses. Source: https://github.com/cmstuberg/PowerBar

PowerBar is not affiliated with, endorsed by or sponsored by Pandora Media.
Pandora is a trademark of Pandora Media, LLC.
