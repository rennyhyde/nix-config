#!/usr/bin/env bash

# Run this on a fresh installation to copy over non-nix fonts

FONT_DIR="$HOME/Library/Fonts"
mkdir -p "$FONT_DIR"

echo "Downloading IBM Plex Sans..."
tmp=$(mktemp -d)

curl -sSL "https://github.com/IBM/plex/releases/download/%40ibm%2Fplex-sans%401.1.0/ibm-plex-sans.zip" -o "$tmp/ibm-plex-sans.zip"
unzip -q "$tmp/ibm-plex-sans.zip" -d "$tmp/extracted"

find "$tmp/extracted" -name "*.ttf" | xargs -I {} cp {} "$FONT_DIR/"

rm -rf "$tmp"
echo "IBM Plex Sans installed to $FONT_DIR"

# Other fonts which were not scriptable:
#
#
#