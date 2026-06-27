#!/usr/bin/env bash
set -euo pipefail

tar -tzf LogicProMCP-macOS-universal.tar.gz > tarball-listing.txt
echo "Tarball listing:"
cat tarball-listing.txt

paths=$(sed -nE 's/^[[:space:]]*(pkgshare|bin)\.install "([^"]+)".*/\2/p' Formula/logic-pro-mcp.rb)
if [ -z "$paths" ]; then
  echo "::error::Parsed no install paths from Formula/logic-pro-mcp.rb — parser or Formula layout drifted"
  exit 1
fi

fail=0
while IFS= read -r path; do
  if grep -Fxq "$path" tarball-listing.txt; then
    echo "OK: $path"
  else
    echo "::error::Formula installs '$path' but it is missing from LogicProMCP-macOS-universal.tar.gz"
    fail=1
  fi
done <<< "$paths"

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "Formula install paths verified against the built tarball."
