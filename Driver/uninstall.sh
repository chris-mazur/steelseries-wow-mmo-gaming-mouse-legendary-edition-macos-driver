#!/bin/zsh
# Stops and removes the LaunchAgent. Leaves config.json in place.
PLIST_LABEL="com.steelseries.wowmousedriver"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
rm -f "$PLIST_DEST"
echo "Driver stopped and LaunchAgent removed."
echo "Config left in place at: $HOME/Library/Application Support/SteelSeriesWowMouseDriver/config.json"
