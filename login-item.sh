#!/bin/sh
set -eu
label='local.camlink.signal-indicator'
agent="$HOME/Library/LaunchAgents/$label.plist"
app="$HOME/Applications/Cam Link Indicator.app"
domain="gui/$(id -u)"
case "${1-}" in
    enable)
        if [ ! -d "$app" ]; then
            echo 'Install the app with ./install.sh first.' >&2
            exit 1
        fi
        mkdir -p "$HOME/Library/LaunchAgents"
        # plutil escapes the path correctly, including spaces and XML characters.
        staging=$(mktemp "${TMPDIR:-/tmp}/camlink-login.XXXXXX")
        trap 'rm -f "$staging"' EXIT HUP INT TERM
        /usr/bin/plutil -create xml1 "$staging"
        /usr/bin/plutil -insert Label -string "$label" "$staging"
        /usr/bin/plutil -insert ProgramArguments -xml '<array/>' "$staging"
        /usr/bin/plutil -insert ProgramArguments.0 -string '/usr/bin/open' "$staging"
        /usr/bin/plutil -insert ProgramArguments.1 -string '-g' "$staging"
        /usr/bin/plutil -insert ProgramArguments.2 -string "$app" "$staging"
        /usr/bin/plutil -insert RunAtLoad -bool YES "$staging"
        /usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$staging"
        /usr/bin/plutil -lint "$staging"
        if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            /bin/launchctl bootout "$domain/$label"
        fi
        /usr/bin/install -m 644 "$staging" "$agent"
        /bin/launchctl bootstrap "$domain" "$agent"
        echo 'Start at login enabled. Quit still stops the app until you reopen it or log in again.'
        ;;
    disable)
        if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            /bin/launchctl bootout "$domain/$label"
        fi
        rm -f "$agent"
        echo 'Start at login disabled. The running app is unchanged.'
        ;;
    *)
        echo 'Usage: ./login-item.sh enable|disable' >&2
        exit 2
        ;;
esac
