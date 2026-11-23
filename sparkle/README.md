# Sparkle 1.5 for PowerPC Mac OS X

A working copy of [Sparkle](https://github.com/sparkle-project/Sparkle), the app
updater that Tiger- and Leopard-era Mac apps shipped with. Sparkle 1.5 is the last
version that runs on PowerPC and Mac OS X 10.4, but it downloads through the
system's networking, and today's HTTPS servers (GitHub included) refuse that.
This build fixes that and brings its security up to date:

- **It works with modern HTTPS.** Sparkle's downloads (the appcast, the update and
  the release notes) go through a bundled curl + OpenSSL 3 with its own CA list,
  instead of the system's networking.
- **Ed25519 signatures,** in the same format as Sparkle 2 (`SUPublicEDKey`,
  `sparkle:edSignature`). Old DSA keys still work.
- **Every update must be signed.** Stock 1.5 skipped the check when the appcast
  and the update both came over HTTPS; this build never does.
- One fat `Sparkle.framework` with G3, G4 and G5 code, for Mac OS X 10.4 and later.
  Your app uses it exactly like stock Sparkle 1.5.

The framework is self-contained: it needs nothing from the system's OpenSSL or
networking, and nothing else installed. Each app ships its own copy.

Version: `1.5-ppc.1` (the framework's `CFBundleShortVersionString`).

## Contents

1. [Add it to your app](#add-it-to-your-app)
2. [Make your signing key](#make-your-signing-key)
3. [Publish an update](#publish-an-update)
4. [Appcast reference](#appcast-reference)
5. [Troubleshooting](#troubleshooting)
6. [Building and testing this framework](#building-and-testing-this-framework)
7. [Changes from upstream Sparkle 1.5](#changes-from-upstream-sparkle-15)

## Add it to your app

**1. Embed the framework.** Copy `Sparkle.framework` into your app's
`Contents/Frameworks/`, keeping its symlinks (`cp -R` or `ditto`, not a copy that
follows links). In Xcode, add a Copy Files build phase with destination
Frameworks. With a Makefile:

    mkdir -p MyApp.app/Contents/Frameworks
    cp -R path/to/Sparkle.framework MyApp.app/Contents/Frameworks/

**2. Link it:** `-F path/to/dir/with/framework -framework Sparkle`. The
framework's install name is `@loader_path/../Frameworks/...`, so nothing else is
needed.

**3. Add the Info.plist keys:**

| Key | Value | |
|---|---|---|
| `SUFeedURL` | `https://...appcast.xml` | Required. Where your appcast lives. |
| `SUPublicEDKey` | the public key from `generate_keys` | Required. Without it every update is refused, and Sparkle shows a "signing key missing" alert at launch. |
| `CFBundleVersion` | a build number, e.g. `7` | Required, and must go up with every release. This is what Sparkle compares. |
| `CFBundleShortVersionString` | e.g. `0.7` | What people see. |
| `SUEnableAutomaticChecks` | `true` / `false` | Optional. Set it to skip the "check automatically?" question. |
| `SUScheduledCheckInterval` | seconds, e.g. `86400` | Optional. Default one day, minimum one hour. |
| `SUShowReleaseNotes` | `false` | Optional. Hides the release notes in the update window. |
| `SUAllowsAutomaticUpdates` | `false` | Optional. Hides "Automatically download and install updates". |
| `SUPublicDSAKey` / `SUPublicDSAKeyFile` | DSA public key (PEM), or its file name in Resources | Legacy apps only. If `SUPublicEDKey` is present, DSA is ignored. |

**4. Start the updater and add a menu item.** With a nib, add an `SUUpdater`
object and connect "Check for Updates..." to its `checkForUpdates:` action, as for
stock Sparkle. Without a nib, create it at launch:

    #import <Sparkle/Sparkle.h>

    - (void)applicationDidFinishLaunching:(NSNotification *)note {
        SUUpdater *updater = [SUUpdater sharedUpdater];  // starts the scheduled checks
        // appMenu: your application menu (the one with About and Quit)
        NSMenuItem *item = [appMenu insertItemWithTitle:@"Check for Updates..."
            action:@selector(checkForUpdates:) keyEquivalent:@"" atIndex:1];
        [item setTarget:updater];
    }

On the first launch Sparkle stays quiet. On the second launch it asks whether to
check automatically, unless `SUEnableAutomaticChecks` is set. Checks run in the
background and never block the app. When there's no network, a scheduled check
fails silently.

## Make your signing key

Each app (or each developer) has one Ed25519 key pair. The public key goes into the
app, and the private key signs every update.

    sparkle/bin/generate_keys ~/keys/MyApp-sparkle.pem

It writes the private key (mode 600) and prints the public key, a 44-character
string such as `PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw=`. Put that in
Info.plist as `SUPublicEDKey`. `generate_keys -p KEY.pem` prints it again later.

**Keep the private key safe:**

- Keep it **out of your source repository.** Anyone who has it can sign an update
  that your users' copies will install.
- **Back it up.** If you lose it, the copies people already have can't take updates
  from you any more. They would have to download a new version by hand.
- If it leaks, ship a release with a new `SUPublicEDKey` as soon as you can,
  signed with the *old* key so existing copies accept it. Then sign everything
  after that with the new key.

The tools need OpenSSL 3 or later. They look for it in this repo's
`tls/dist/bin`, MacPorts (`sudo port install openssl3`), Homebrew, and
`/usr/bin`. Set `OPENSSL=/path/to/openssl` to choose one. On a modern Mac,
Sparkle 2's own `generate_keys` and `sign_update` produce the same format
(they keep the key in the Keychain), so either set of tools works.

## Publish an update

**1. Raise the version.** Increase `CFBundleVersion` (Sparkle compares this) and
set `CFBundleShortVersionString`. Sparkle only offers an update whose
`sparkle:version` is newer than the running app's `CFBundleVersion`, and never
offers a downgrade.

**2. Archive the app with `ditto`:**

    ditto -c -k --keepParent MyApp.app MyApp-0.7.zip

Don't use plain `zip`. It can break the symlinks inside frameworks
(`Sparkle.framework` included), and the updated app then won't launch. `.tar.gz`,
`.tar.bz2` and `.dmg` also work.

**3. Sign the exact file you'll upload:**

    sparkle/bin/sign_update MyApp-0.7.zip ~/keys/MyApp-sparkle.pem
    sparkle:edSignature="Vn0r...Ag==" length="15728640"

If the file changes in any way after this (re-zipped, renamed inside, touched by an
upload tool), sign it again. A signature belongs to one exact file.

**4. Upload the archive.** Any HTTPS host works. With GitHub Releases:

    gh release create v0.7 MyApp-0.7.zip --title "MyApp 0.7" --notes "..."

The download URL is then
`https://github.com/OWNER/REPO/releases/download/v0.7/MyApp-0.7.zip`. GitHub
redirects it to its storage servers; that's fine. Keep the file name in that URL
ending in `.zip`, because Sparkle names the download after it.

**5. Add the release to your appcast,** newest first, with the two attributes from
step 3:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MyApp</title>
    <item>
      <title>MyApp 0.7</title>
      <pubDate>Mon, 23 Nov 2026 12:00:00 +0000</pubDate>
      <sparkle:minimumSystemVersion>10.4</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://example.com/myapp/notes-0.7.html</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/OWNER/REPO/releases/download/v0.7/MyApp-0.7.zip"
                 sparkle:version="7" sparkle:shortVersionString="0.7"
                 type="application/octet-stream"
                 sparkle:edSignature="Vn0r...Ag==" length="15728640" />
    </item>
  </channel>
</rss>
```

**6. Publish the appcast** at the URL in `SUFeedURL`. A file in your repository
works (`https://raw.githubusercontent.com/OWNER/REPO/main/appcast.xml`; GitHub
caches it for a few minutes), and so does GitHub Pages or any HTTPS server.

**7. Check it with an older copy** of your app: "Check for Updates..." should offer
the new version, show the release notes, download, install and relaunch. If
anything is wrong with the signature, Sparkle refuses the update and logs why to
Console (see Troubleshooting).

## Appcast reference

| Where | Name | Meaning |
|---|---|---|
| `<enclosure>` | `url` | The archive. HTTPS. |
| `<enclosure>` | `sparkle:version` | The update's `CFBundleVersion`. Required. |
| `<enclosure>` | `sparkle:shortVersionString` | The update's `CFBundleShortVersionString`, shown to people. |
| `<enclosure>` | `sparkle:edSignature` | From `sign_update`. Required for apps with `SUPublicEDKey`. |
| `<enclosure>` | `length` | Archive size in bytes, from `sign_update`. |
| `<enclosure>` | `sparkle:dsaSignature` | Legacy DSA signature, only for apps without `SUPublicEDKey`. |
| `<item>` | `<sparkle:minimumSystemVersion>` | e.g. `10.5`: Macs on an older system aren't offered this update. |
| `<item>` | `<sparkle:releaseNotesLink>` | An HTML page shown in the update window. |
| `<item>` | `<description>` | Inline HTML release notes, if there's no link (use `<![CDATA[ ... ]]>`). |
| `<item>` | `<title>`, `<pubDate>` | Shown and logged. |

Sparkle takes the first item it can use: newer than the running app, and allowed
on this system.

## Troubleshooting

When Sparkle refuses an update it shows "An error occurred while extracting the
archive" and logs the reason to Console:

| Console says | Fix |
|---|---|
| `Sparkle: refusing the update: The update has no EdDSA signature` | Add `sparkle:edSignature` to the `<enclosure>`. |
| `... The update's EdDSA signature is not valid.` | The archive changed after signing, or it was signed with another key. Sign the uploaded file again with the key that matches the app's `SUPublicEDKey`. |
| `... The app has no public key (SUPublicEDKey)` | Add `SUPublicEDKey` to the running app's Info.plist. Copies already out there without one can't be updated; their users have to install by hand. |
| Alert at launch: "Update signing key missing!" | Same: no `SUPublicEDKey` in Info.plist. |
| "You already have the newest version" | `sparkle:version` isn't higher than the app's `CFBundleVersion`. |
| An error about the server certificate | The server's certificate doesn't chain to a CA in the framework's `Resources/cacert.pem`. Each release of this framework carries a fresh CA list, so ship your app with a recent framework. |

## Building and testing this framework

This is part of the [PPC-Projects](../README.md) repository, and it builds with the
repo's PowerPC toolchain (gcc-4.0, the 10.4u SDK, `../mk/ppc.mk`), on a PowerPC Mac
running 10.5:

    ../tls/build.sh   # once: the bundled curl + OpenSSL 3
    make              # fetch + verify upstream, apply patches/, build build/Sparkle.framework
    make test         # test/: framework, network, signature and update-driver checks

`make test` runs in a logged-in GUI session (`../tools/gui-run`). `test/fwtest`
(SparkleTest.app, which embeds the framework) checks that the framework loads with
its resources, `SUUpdater` setup, version comparison and the update window.
`test/nettest.sh` starts a local HTTPS server (`test/https-server.py`) with a
throwaway CA and checks:

- **Networking:** the appcast over HTTPS and HTTP, a redirect to another host, an
  HTTPS-to-HTTP redirect (refused), 404s, an untrusted certificate, a refused
  connection, a server that never answers (gives up after 30 s; the main thread
  never stalls), a download through a redirect, and release notes with an image.
- **Signatures:** DSA and Ed25519 good / tampered / wrong key / garbage, the RFC
  8032 test vector, and `generate_keys` / `sign_update`.
- **Policy:** Sparkle's own update driver against an app with an Ed25519 key, one
  with only a DSA key, and one with no key. It installs signed updates and refuses
  tampered, unsigned (also over HTTPS), wrongly signed and DSA-only ones. It
  doesn't offer older versions.
- **Install and relaunch, for real:** a copy of the test app updates itself from 6
  to 7. The copy on disk becomes version 7, the app and the framework keep all three
  CPU slices and the framework's symlinks, and version 7 starts up afterwards.
- **The scheduled check:** its update window, "Skip This Version" (the skipped
  version stays quiet next time, a newer one is still offered), and no window at all
  when the server can't be reached.
- **GitHub, for real:** an appcast from raw.githubusercontent.com and a release
  download (`PPC_OFFLINE=1` skips these).

The fat app runs everything, and each CPU slice runs the core set.

## Changes from upstream Sparkle 1.5

| | |
|---|---|
| Upstream | `sparkle-project/Sparkle` commit `a5c8e0b1` (2010-07-27), pinned in `versions.sh`: the last commit built with gcc for ppc/10.4 (the next one moved to clang). It is Sparkle 1.5b6 (2008-09, what most Tiger/Leopard apps ship) plus two years of fixes. |
| Licence | MIT (Sparkle; `License.txt` in the framework). Bundled: OpenSSL (Apache 2.0), curl (MIT-style), zlib, in `Resources/Licenses/`. Our changes: MIT, like Sparkle. |

| Change | Where | Why |
|---|---|---|
| Networking through curl + OpenSSL 3 | `src-ppc/SUCurlURLProtocol.m`, patch 0001 | An NSURLProtocol that loads only Sparkle's own requests, with the framework's `cacert.pem`. Patch 0001 tags the appcast, archive and release-notes requests (and the notes' images etc.). NSURLDownload and WebView behave as before; the host app's networking is untouched. HTTPS may only redirect to HTTPS. HTTP errors are errors (stock 1.5 saved a 404 page as the "update"). |
| DSA on OpenSSL 3 | patch 0002 | The same check with the OpenSSL 3 API instead of the system's 0.9.7. Also fixes two reads past the end of a buffer (key and signature lacked a NUL terminator). |
| Ed25519, signatures always required | `src-ppc/SUEdDSAVerifier.m`, patch 0003 | `SUPublicEDKey` + `sparkle:edSignature` as in Sparkle 2. The download check requires Ed25519 when the app has that key, DSA when it has only a DSA key, and refuses updates when it has neither. The launch alert now warns about a missing key. |
| Signing tools | `bin/generate_keys`, `bin/sign_update` | Plain `sh` on OpenSSL 3, Sparkle 2's formats. |
| Delta updates left out | `src-ppc/SUNoBinaryDelta.m` | They need libxar, which Tiger lacks. Upstream reports them unsupported on 10.4 anyway, and 1.5b6 predates them. Full updates are unaffected. |
| Build | `Makefile` | Our own Makefile (fat g3/g4/g5, 10.4u SDK, `check-slices`) instead of the Xcode project. Only Sparkle's own symbols are exported; the bundled curl/OpenSSL/zlib stay private. |

**Size:** the bundled curl + OpenSSL make the framework about 16 MB (about 5 MB
per CPU slice, 6.6 MB zipped), against 1.8 MB for stock 1.5. That's the cost of
each app being self-contained.
