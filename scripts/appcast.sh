#!/bin/bash
# usage: appcast.sh vX.Y.Z build-number owner/repo  (needs DiskLens.dmg in cwd and $KEY = Sparkle private key)
set -euo pipefail
V=${1#v}; BUILD=$2; REPO=$3
SIGN=$(find build/SourcePackages/artifacts -name sign_update -path '*sparkle*' | head -1)
SIG=$(echo "$KEY" | "$SIGN" --ed-key-file - DiskLens.dmg)   # prints: sparkle:edSignature="..." length="..."
cat > site/appcast.xml <<X
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DiskLens</title>
    <item>
      <title>$V</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$V</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/v$V/DiskLens.dmg" type="application/octet-stream" $SIG/>
    </item>
  </channel>
</rss>
X
