#!/bin/bash
# LogicProMCP Key Commands Uninstaller
# Removes MCP preset and optionally restores from backup.
# Reference: PRD §6.3, §9.3

set -euo pipefail

KEYCMD_DIR="${LOGIC_PRO_MCP_KEYCMD_DIR:-$HOME/Music/Audio Music Apps/Key Commands}"
BACKUP_DIR="$KEYCMD_DIR/backups"
MCP_PRESET="$KEYCMD_DIR/LogicProMCP-KeyCommands.plist"
AUTO_RESTORE="${LOGIC_PRO_MCP_KEYCMD_AUTO_RESTORE:-0}"

echo "=== LogicProMCP Key Commands Uninstaller ==="
echo ""

# Remove MCP preset
if [ -f "$MCP_PRESET" ]; then
    rm "$MCP_PRESET"
    echo "✓ Removed: $MCP_PRESET"
else
    echo "MCP preset not found — nothing to remove."
fi

# List available backups
if [ -d "$BACKUP_DIR" ]; then
    BACKUPS=$(ls -d "$BACKUP_DIR"/backup_* 2>/dev/null || true)
    if [ -n "$BACKUPS" ]; then
        echo ""
        echo "Available backups:"
        echo "$BACKUPS" | while read -r b; do
            echo "  - $(basename "$b") ($(ls "$b" | wc -l | tr -d ' ') files)"
        done

        # Restore latest backup
        LATEST=$(echo "$BACKUPS" | sort -r | head -1)
        echo ""
        # RB-6 (2026-05-08 enterprise review) closed in v3.4.0: pre-fix the
        # `else` branch ran `read -p` unconditionally, which under
        # `set -euo pipefail` exits 1 in non-TTY contexts (MDM, fleet
        # automation, CI). The fix uses `[ -t 0 ]` to detect whether stdin
        # is a TTY: when not, default to skipping the restore (the safe
        # action for unattended uninstalls — the operator can re-run with
        # `LOGIC_PRO_MCP_KEYCMD_AUTO_RESTORE=1` if they actually wanted
        # the restore). Interactive runs are unchanged.
        # v3.4.1 (Boomer P2-5): make the AUTO_RESTORE branch fail-loud on
        # an empty backup directory. Pre-fix the `cp .../* ... || true`
        # masked an empty source dir as success, so an operator running
        # uninstall with `LOGIC_PRO_MCP_KEYCMD_AUTO_RESTORE=1` against a
        # corrupt backup would see "✓ Restored" without any files moving.
        # The new check counts what actually exists in $LATEST first.
        if [ "$AUTO_RESTORE" = "1" ]; then
            BACKUP_FILE_COUNT=$(find "$LATEST" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
            if [ "$BACKUP_FILE_COUNT" = "0" ]; then
                echo "⚠  Backup '$(basename "$LATEST")' is empty — skipping restore."
                echo "  Pick a different backup with LOGIC_PRO_MCP_KEYCMD_RESTORE_FROM=<path>"
                echo "  or remove the corrupt backup directory manually."
            else
                cp "$LATEST"/* "$KEYCMD_DIR/" 2>/dev/null || true
                echo "✓ Restored $BACKUP_FILE_COUNT files from: $(basename "$LATEST")"
            fi
        elif [ -t 0 ]; then
            read -p "Restore from $(basename "$LATEST")? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cp "$LATEST"/* "$KEYCMD_DIR/" 2>/dev/null || true
                echo "✓ Restored from: $(basename "$LATEST")"
            else
                echo "Skipped restore."
            fi
        else
            echo "Non-interactive shell detected — skipping restore prompt."
            echo "Re-run with LOGIC_PRO_MCP_KEYCMD_AUTO_RESTORE=1 to auto-restore from $(basename "$LATEST")."
        fi
    else
        echo "No backups found."
    fi
else
    echo "No backup directory found."
fi

echo ""
echo "Done. Restart Logic Pro to apply changes."
