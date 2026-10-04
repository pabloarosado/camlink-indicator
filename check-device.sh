#!/bin/sh
set -eu
cd "$(dirname "$0")"
./build.sh >&2
exec 'build/Cam Link Indicator.app/Contents/MacOS/CamLinkIndicator' --check
