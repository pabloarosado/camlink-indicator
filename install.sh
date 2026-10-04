#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != '--login' ]; }; then
    echo 'Usage: ./install.sh [--login]' >&2
    exit 2
fi
# Build successfully before replacing an existing installation.
./build.sh
if /usr/bin/pgrep -x CamLinkIndicator >/dev/null; then
    echo 'Quit Cam Link Indicator from its menu, then run this installer again.' >&2
    exit 1
fi
mkdir -p "$HOME/Applications"
/usr/bin/ditto 'build/Cam Link Indicator.app' "$HOME/Applications/Cam Link Indicator.app"
if [ "${1-}" = '--login' ]; then
    ./login-item.sh enable
fi
/usr/bin/open -g "$HOME/Applications/Cam Link Indicator.app"
echo 'Installed in ~/Applications/Cam Link Indicator.app'
