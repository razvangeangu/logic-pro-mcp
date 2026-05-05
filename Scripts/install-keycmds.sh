#!/bin/bash
# LogicProMCP Key Commands Installer (v3.1.6)
#
# Backs up existing key commands and stages the legacy MCP preset reference.
#
# IMPORTANT: Logic Pro 12.2+ no longer accepts plist-based Key Commands
# Import (the Import menu is gray on 12.2). The .plist file is retained
# only as a CC→command MAPPING REFERENCE — copy values from it during
# manual MIDI Learn in Logic. See docs/SETUP.md §MIDIKeyCommands for the
# step-by-step manual MIDI Learn flow.
#
# Most preset operations are now covered by logic_edit / logic_project /
# logic_navigate / logic_tracks / logic_transport without any binding.
# Manual MIDI Learn is only required for channel-only ops such as
# transport.capture_recording.
#
# Reference: PRD §6.3 (legacy) + PRD-issue1-keycmd-port-routing §3

set -euo pipefail

KEYCMD_DIR="${LOGIC_PRO_MCP_KEYCMD_DIR:-$HOME/Music/Audio Music Apps/Key Commands}"
BACKUP_DIR="$KEYCMD_DIR/backups"
PRESET_SRC="$(dirname "$0")/keycmd-preset.plist"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== LogicProMCP Key Commands Installer ==="
echo ""

# Verify preset file exists
if [ ! -f "$PRESET_SRC" ]; then
    echo "ERROR: Preset file not found: $PRESET_SRC"
    exit 1
fi

# Create directories
mkdir -p "$KEYCMD_DIR"
mkdir -p "$BACKUP_DIR"

# Backup existing key commands
EXISTING_FILES=$(find "$KEYCMD_DIR" -maxdepth 1 \( -name "*.plist" -o -name "*.logickeycommands" \) 2>/dev/null | grep -v backups || true)
if [ -n "$EXISTING_FILES" ]; then
    echo "Backing up existing key commands to: $BACKUP_DIR/backup_$TIMESTAMP/"
    mkdir -p "$BACKUP_DIR/backup_$TIMESTAMP"
    echo "$EXISTING_FILES" | while read -r f; do
        cp "$f" "$BACKUP_DIR/backup_$TIMESTAMP/"
    done
    echo "  Backed up $(echo "$EXISTING_FILES" | wc -l | tr -d ' ') files."
else
    echo "No existing key commands found — clean install."
fi

# Check for CC conflicts (CC 20-93 on CH 16)
echo ""
echo "Checking for MIDI CC conflicts..."
# Logic Pro stores key commands in binary/proprietary format.
# We can only warn — actual conflict detection requires Logic Pro to be running.
echo "  Note: Logic 12.2+ does not import this .plist. Use it only as a"
echo "  CC→Command mapping reference. Use 'MIDI Learn' in Logic Pro >"
echo "  Key Commands > Edit (⌥K) to bind any commands you actually need."

# Stage preset reference (NOT importable on Logic 12.2+)
cp "$PRESET_SRC" "$KEYCMD_DIR/LogicProMCP-KeyCommands.plist"
echo ""
echo "✓ Mapping reference staged: $KEYCMD_DIR/LogicProMCP-KeyCommands.plist"
echo ""
echo "=== Next Steps ==="
echo "Logic Pro 12.2+ does NOT accept this .plist via Import (the menu is gray)."
echo "The file is staged only as a CC→Command mapping reference."
echo ""
echo "If you need any of the channel-only ops (e.g. transport.capture_recording):"
echo "  1. Open Logic Pro"
echo "  2. Logic Pro > Key Commands > Edit (⌥K)"
echo "  3. Search for the command, click [Learn New Assignment],"
echo "     and send the matching CC on Channel 16 from your MCP client"
echo "     (use port:\"keycmd\" so the CC arrives on LogicProMCP-KeyCmd-Internal)."
echo "  4. Click [Save Assignments]"
echo ""
echo "Most preset ops are already routed via logic_edit / logic_project /"
echo "logic_navigate / logic_tracks / logic_transport without any manual"
echo "binding — see docs/SETUP.md §MIDIKeyCommands for the audited matrix."
echo ""
echo "To restore previous Key Commands: Scripts/uninstall-keycmds.sh"
