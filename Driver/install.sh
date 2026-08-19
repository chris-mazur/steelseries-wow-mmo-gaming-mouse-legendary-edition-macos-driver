#!/bin/zsh
# Builds the driver, always leaving a ready-to-run binary in place. Whether it
# also gets registered as a LaunchAgent (auto-start at login, auto-restart on
# crash) is up to you - by default this asks; pass --login or --no-login to
# skip the prompt (handy for scripted installs).
set -e

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/SteelSeriesWowMouseDriver"
BIN_PATH="$APP_SUPPORT/wowmousedriverd"
LOG_DIR="$APP_SUPPORT/logs"
PLIST_LABEL="com.steelseries.wowmousedriver"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

START_AT_LOGIN=""
for arg in "$@"; do
    case "$arg" in
        --login) START_AT_LOGIN="yes" ;;
        --no-login) START_AT_LOGIN="no" ;;
    esac
done

echo "Building..."
swiftc -O "$SCRIPT_DIR/main.swift" -o "$SCRIPT_DIR/wowmousedriverd"

mkdir -p "$APP_SUPPORT" "$LOG_DIR"
cp "$SCRIPT_DIR/wowmousedriverd" "$BIN_PATH"
echo "Installed binary: $BIN_PATH"

if [[ -z "$START_AT_LOGIN" ]]; then
    if [[ -t 0 ]]; then
        echo -n "Start automatically at login and keep running in the background? [y/N] "
        read -r REPLY
        case "$REPLY" in
            [Yy]*) START_AT_LOGIN="yes" ;;
            *) START_AT_LOGIN="no" ;;
        esac
    else
        START_AT_LOGIN="no"
    fi
fi

if [[ "$START_AT_LOGIN" == "yes" ]]; then
    echo "Installing LaunchAgent..."
    sed -e "s#__BIN_PATH__#$BIN_PATH#" -e "s#__LOG_DIR__#$LOG_DIR#" \
        "$SCRIPT_DIR/com.steelseries.wowmousedriver.plist" > "$PLIST_DEST"

    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
    launchctl enable "gui/$(id -u)/$PLIST_LABEL"

    echo "Installed and started as a LaunchAgent (starts automatically at login)."
    echo "To stop this later, run: ./uninstall.sh"
else
    echo "Not installing a LaunchAgent. Run the driver manually with:"
    echo "  \"$BIN_PATH\""
    echo "You can install the LaunchAgent later by re-running this script and answering yes,"
    echo "or with: ./install.sh --login"
fi

echo "Config: $APP_SUPPORT/config.json"
echo "Logs: $LOG_DIR"
