#!/bin/sh
# release.sh: publish a PowerBar release to its public repo, cmstuberg/PowerBar.
#
#   powerbar/release.sh --dry-run   everything up to and including the release commit,
#                                   nothing pushed or uploaded; see ~/release/PowerBar-<v>/
#   powerbar/release.sh             the real thing
#   --skip-tests                    don't run Sparkle's and PowerBar's test suites first
#
# The version comes from powerbar/Info.plist (CFBundleShortVersionString and the build
# number CFBundleVersion); the release notes from powerbar/release/notes/<version>.html.
#
#  1. checks: PPC-Projects committed and pushed; the version isn't released yet and its
#     build number is higher than any in the appcast; the signing key matches
#     SUPublicEDKey; key and GitHub token are mode 600
#  2. tests: make test in sparkle/ and powerbar/
#  3. build: a clean `make dist` (ditto zip), unzipped again to check the version, that
#     every Mach-O has its g3/g4/g5 slices, and that framework symlinks survived
#  4. sign the zip (sparkle/bin/sign_update)
#  5. source snapshot: the public repo's files are replaced with `git archive HEAD` of
#     what PowerBar builds from, plus LICENSE and the public README (the appcast is
#     kept). Stops if the snapshot has a private key, the private repo's email address,
#     a home directory path or a LAN address in it.
#  6. commit and tag v<version> there, as the public (noreply) identity
#     -- --dry-run stops here --
#  7. push; GitHub release as a draft, upload the zip, publish, download it back from
#     the public URL and compare
#  8. add the release to appcast.xml, commit, push (only now can apps see it)
#  9. check it the way an app will: SparkleTest, set up as PowerBar's previous build with
#     PowerBar's key, runs Sparkle's update driver against the live appcast. It must
#     download, verify and unpack the new build. GitHub may serve the old appcast for a
#     few minutes, so this retries for up to 10 minutes.
#
# Secrets stay outside every repo: the Ed25519 key in ~/.sparkle-keys (keep a backup
# somewhere else) and the GitHub token in ~/.config/ppc. The token is only ever
# handed to curl on stdin, never on a command line.
set -eu
PATH=/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/.." && pwd)
APP=PowerBar
REPO=cmstuberg/PowerBar
GIT_URL=git@github.com:$REPO.git
REPO_URL=https://github.com/$REPO
FEED=https://raw.githubusercontent.com/$REPO/main/appcast.xml
KEY=$HOME/.sparkle-keys/PowerBar-ed25519.pem
TOKEN_FILE=$HOME/.config/ppc/github-token-PowerBar
AUTHOR_NAME="Chris Stuberg"
AUTHOR_EMAIL=360036176+cmstuberg@users.noreply.github.com
EXPORT=".gitignore LICENSE mk tools tls av json-c pianobar sparkle powerbar"
PB=/usr/libexec/PlistBuddy
PY=/opt/local/bin/python2.7

DRY=0; TESTS=1
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --skip-tests) TESTS=0 ;;
    *) echo "usage: release.sh [--dry-run] [--skip-tests]" >&2; exit 2 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
die() { echo "release: $*" >&2; exit 1; }
plist() { $PB -c "Print :$1" "$HERE/Info.plist"; }

VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
PUBKEY=$(plist SUPublicEDKey)
MINOS=$(plist LSMinimumSystemVersion)
NOTES=$HERE/release/notes/$VERSION.html
W=$HOME/release/$APP-$VERSION
P=$W/public
ZIP=$APP-$VERSION.zip
ASSET_URL=$REPO_URL/releases/download/v$VERSION/$ZIP

# --- 1 ----------------------------------------------------------------------------
say "1. checks: $APP $VERSION (build $BUILD)$( [ $DRY = 1 ] && echo ', dry run')"
case $BUILD in ''|*[!0-9]*) die "CFBundleVersion must be a whole number, not '$BUILD'" ;; esac
[ -f "$NOTES" ] || die "no release notes at $NOTES"
cd "$TOP"
[ -z "$(git status --porcelain)" ] || die "PPC-Projects has uncommitted changes"
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "PPC-Projects HEAD isn't what's pushed to origin/main"
for f in "$KEY" "$TOKEN_FILE"; do
  [ -f "$f" ] || die "missing $f"
  case $(ls -l "$f" | cut -c1-10) in -rw-------) ;; *) die "$f must be mode 600" ;; esac
done
[ "$("$TOP/sparkle/bin/generate_keys" -p "$KEY")" = "$PUBKEY" ] \
  || die "the signing key doesn't match SUPublicEDKey in powerbar/Info.plist"
if git ls-remote --tags "$GIT_URL" "refs/tags/v$VERSION" | grep -q .; then
  die "$REPO already has a tag v$VERSION"
fi
rm -rf "$W"; mkdir -p "$W"
git clone -q "$GIT_URL" "$P"
NEWEST=$($PY "$HERE/release/appcast.py" newest "$P/appcast.xml")
[ "$BUILD" -gt "$NEWEST" ] || die "build $BUILD isn't newer than the appcast's newest ($NEWEST)"
echo "ok: committed and pushed, key matches, v$VERSION is new, build $BUILD > $NEWEST"

# --- 2 ----------------------------------------------------------------------------
if [ $TESTS = 1 ]; then
  say "2. tests (logs in $W)"
  make -C sparkle test > "$W/sparkle-test.log" 2>&1 || die "Sparkle's tests failed: $W/sparkle-test.log"
  grep -E '^nettest: [0-9]+ passed' "$W/sparkle-test.log" | sed 's/^/ok: /'
  make -C powerbar test > "$W/powerbar-test.log" 2>&1 || die "PowerBar's tests failed: $W/powerbar-test.log"
  grep -E '^uitest: [0-9]+/|^selftest:' "$W/powerbar-test.log" | sed 's/^/ok: /'
else
  say "2. tests skipped (--skip-tests)"
fi

# --- 3 ----------------------------------------------------------------------------
say "3. build"
make -C powerbar clean > /dev/null
make -C powerbar dist > "$W/build.log" 2>&1 || die "the build failed: $W/build.log"
cp "powerbar/build/$ZIP" "$W/$ZIP"
mkdir "$W/unzipped"
ditto -x -k "$W/$ZIP" "$W/unzipped"
U=$W/unzipped/$APP.app
[ "$($PB -c 'Print :CFBundleVersion' "$U/Contents/Info.plist")" = "$BUILD" ] || die "the zip holds the wrong build"
n=0
find "$U" -type f > "$W/files.txt"
while read -r f; do
  archs=$(lipo -info "$f" 2>/dev/null | sed 's/.*: //') || continue
  [ -n "$archs" ] || continue
  case $archs in *ppc750*ppc7400*ppc970*) n=$((n + 1)) ;;
    *) die "${f#$U/} has slices '$archs', not g3/g4/g5" ;; esac
done < "$W/files.txt"
for l in Versions/Current Sparkle Resources Headers; do
  [ -L "$U/Contents/Frameworks/Sparkle.framework/$l" ] || die "Sparkle.framework/$l isn't a symlink in the zip"
done
echo "ok: $ZIP, $(wc -c < "$W/$ZIP" | tr -d ' ') bytes, build $BUILD, $n binaries with g3/g4/g5 slices, symlinks kept"

# --- 4 ----------------------------------------------------------------------------
say "4. sign"
ATTRS=$("$TOP/sparkle/bin/sign_update" "$W/$ZIP" "$KEY")
SIG=$(echo "$ATTRS" | sed 's/.*edSignature="\([^"]*\)".*/\1/')
LEN=$(echo "$ATTRS" | sed 's/.*length="\([^"]*\)".*/\1/')
echo "ok: $ATTRS"

# --- 5 ----------------------------------------------------------------------------
say "5. source snapshot"
[ -f "$P/appcast.xml" ] && cp "$P/appcast.xml" "$W/appcast.xml.before"
find "$P" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git archive HEAD $EXPORT | tar -x -C "$P"
cp "$HERE/release/README.md" "$P/README.md"
[ -f "$W/appcast.xml.before" ] && cp "$W/appcast.xml.before" "$P/appcast.xml"
EMAIL=$(git config user.email)
(cd "$P" && find . -path ./.git -prune -o -type f -print) > "$W/snapshot-files.txt"
leak() { # what grep-args...: stop if any snapshot file matches
  what=$1; shift
  if (cd "$P" && tr '\n' '\0' < "$W/snapshot-files.txt" | xargs -0 grep -Il "$@") > "$W/leak.txt" 2>/dev/null; then
    cat "$W/leak.txt" >&2; die "the snapshot contains $what (files above)"
  fi
}
# (the patterns are split in two so this script doesn't match itself)
leak "a private key" -e "PRIVATE"" KEY-----"
leak "the private repo's email address" -F -e "$EMAIL"
leak "a home directory path" -e "/Users/""chrisstuberg"
leak "a LAN address" -E -e "192\.168\.[0-9]+\.[0-9]+|[A-Za-z0-9-]\.local([^A-Za-z0-9]|$)"
echo "ok: $(wc -l < "$W/snapshot-files.txt" | tr -d ' ') files from: $EXPORT"

# --- 6 ----------------------------------------------------------------------------
say "6. commit v$VERSION in the public repo"
cd "$P"
git checkout -q -B main
git add -A
git -c user.name="$AUTHOR_NAME" -c user.email="$AUTHOR_EMAIL" commit -q \
  -m "$APP $VERSION" -m "Source of the $APP $VERSION release (build $BUILD), as built for $ZIP."
git tag "v$VERSION"
git log -1 --format='ok: %h %an <%ae> %s'
cd "$TOP"

if [ $DRY = 1 ]; then
  say "dry run: stopping before anything leaves this machine"
  echo "zip:            $W/$ZIP"
  echo "public repo:    $P (commit + tag v$VERSION, not pushed)"
  echo "appcast entry:  $ATTRS"
  exit 0
fi

# --- 7 ----------------------------------------------------------------------------
say "7. publish v$VERSION"
api() { # METHOD URL CURL-ARGS... -> prints the HTTP status, body in $W/api.json
  m=$1; u=$2; shift 2
  printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github+json"\nheader = "X-GitHub-Api-Version: 2022-11-28"\n' \
    "$(tr -d ' \r\n' < "$TOKEN_FILE")" \
    | curl -s -K - -A "ppc-release" -X "$m" -o "$W/api.json" -w '%{http_code}' "$@" "$u"
}
json() { $PY -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$W/api.json" "$1"; }
git -C "$P" push -q origin main "refs/tags/v$VERSION"
$PY -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": sys.argv[2], "body": open(sys.argv[3]).read(), "draft": True}))' \
  "v$VERSION" "$APP $VERSION" "$NOTES" > "$W/release.json"
st=$(api POST "https://api.github.com/repos/$REPO/releases" -H "Content-Type: application/json" --data-binary "@$W/release.json")
[ "$st" = 201 ] || die "creating the release: HTTP $st $(cat "$W/api.json")"
RID=$(json id)
st=$(api POST "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=$ZIP" \
  -H "Content-Type: application/zip" --data-binary "@$W/$ZIP")
[ "$st" = 201 ] || die "uploading $ZIP to draft release $RID: HTTP $st $(cat "$W/api.json")"
st=$(api PATCH "https://api.github.com/repos/$REPO/releases/$RID" -H "Content-Type: application/json" --data '{"draft":false}')
[ "$st" = 200 ] || die "publishing release $RID: HTTP $st $(cat "$W/api.json")"
echo "ok: $(json html_url)"
i=0
until curl -sfL -o "$W/downloaded.zip" "$ASSET_URL" && cmp -s "$W/$ZIP" "$W/downloaded.zip"; do
  i=$((i + 1)); [ $i -lt 6 ] || die "$ASSET_URL doesn't give back the zip we uploaded"
  sleep 10
done
echo "ok: $ASSET_URL gives back the same bytes"

# --- 8 ----------------------------------------------------------------------------
say "8. appcast"
$PY "$HERE/release/appcast.py" add "$P/appcast.xml" --app "$APP" --link "$REPO_URL" \
  --title "$APP $VERSION" --version "$BUILD" --short "$VERSION" --minos "$MINOS" \
  --url "$ASSET_URL" --sig "$SIG" --length "$LEN" --notes "$NOTES"
git -C "$P" add appcast.xml
git -C "$P" -c user.name="$AUTHOR_NAME" -c user.email="$AUTHOR_EMAIL" commit -q -m "Appcast: $APP $VERSION"
git -C "$P" push -q origin main
echo "ok: $FEED now lists build $BUILD"

# --- 9 ----------------------------------------------------------------------------
say "9. check it the way an app will"
T=$TOP/sparkle/test/build/SparkleTest.app
[ -d "$T" ] || make -C sparkle/test build/SparkleTest.app > /dev/null
C=$W/check/SparkleTest.app
mkdir -p "$W/check"; cp -R "$T" "$C"
$PB -c "Set :CFBundleVersion $((BUILD - 1))" -c "Set :SUPublicEDKey $PUBKEY" -c "Set :SUFeedURL $FEED" "$C/Contents/Info.plist"
i=0
while :; do
  out=$("$TOP/tools/gui-run" -t 200 /usr/bin/env PPC_TLS_CAFILE= "$C/Contents/MacOS/SparkleTest" --driver "$FEED" 2>&1 \
        | grep '^driver:' || true)
  case $out in *"INSTALL: version $BUILD"*) break ;; esac
  i=$((i + 1)); [ $i -lt 20 ] || die "the live appcast didn't lead to build $BUILD: $out"
  echo "   not yet ($out); GitHub may still be serving the old appcast. Retrying in 30 s."
  sleep 30
done
echo "ok: an app at build $((BUILD - 1)) with PowerBar's key finds, downloads, verifies and unpacks build $BUILD"

say "released $APP $VERSION: $REPO_URL/releases/tag/v$VERSION"
