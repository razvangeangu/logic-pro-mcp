#!/bin/zsh
# v3.1.8 Issue #7 live verification harness
#
# Run this AFTER opening Lofi-Dreamscape-80.logicx (or any saved project) in
# Logic Pro 12.x. It prints the values that the new tier-merged
# `logic://project/info` resource would surface.
#
# Expected for Lofi-Dreamscape-80: BPM 80, timesig 4/4, trackCount 31.

set -euo pipefail

DOC=$(osascript -e 'tell application "Logic Pro" to return path of front document as text' 2>/dev/null || echo "")
if [[ -z "$DOC" ]]; then
  echo "FAIL: no open Logic document"
  exit 1
fi

LEAF="$DOC/Alternatives/000/MetaData.plist"
if [[ ! -f "$LEAF" ]]; then
  echo "FAIL: MetaData.plist not found at $LEAF"
  exit 1
fi

echo "DOCUMENT: $DOC"
echo "MTIME: $(stat -f '%Sm' "$LEAF")"
echo "BYTES: $(stat -f '%z' "$LEAF")"
echo
echo "PROJECT FILE METADATA (= what v3.1.8 LogicProjectFileReader reads):"
plutil -p "$LEAF" | grep -E "BeatsPerMinute|NumberOfTracks|SongSignatureNumerator|SongSignatureDenominator"
echo
echo "Compare with current MCP server response (logic://project/info)"
echo "If running v3.1.7: tempo will be 120, trackCount 0 (broken)"
echo "If running v3.1.8: tempo and trackCount will match the values above"
