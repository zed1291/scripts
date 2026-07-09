#!/bin/bash

# Save logs to file
LOG_FILE="/Library/Addigy/.addigy_installs.log"

# If over 1MB, delete the first 512KB of lines
if [ -f "$LOG_FILE" ] && [ $(wc -c < "$LOG_FILE") -gt 1048576 ]; then
    tail -c 524288 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

############################################
############################################
# Use this part as the conditional script in Addigy
# 'exit 1' = install app

APP_NAME="Signal"
echo ""
echo "Starting 'Install $APP_NAME.' ($(date '+%Y-%m-%d %H:%M:%S'))"
update_only="No"

# Determine the latest version of the app
RELEASES_URL="https://updates.signal.org/desktop/latest-mac.yml"
latest_version=$(curl -s $RELEASES_URL | grep -o "version: .*" | cut -d " " -f 2)
installed_version=$(/usr/bin/defaults read "/Applications/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)

# Check if installed and/or if an update is needed.
if [[ ! -d "/Applications/$APP_NAME.app" ]]; then
    # Not installed
    if [[ $update_only == "Yes" ]]; then
        echo "$APP_NAME is not installed, and update-only is selected. Exiting..."
        exit 0
    fi
    echo "$APP_NAME is not installed. Installing..."
    # exit 1
elif [ -z "$latest_version" ]; then
    # Cannot compare installed version with latest version
    echo "Error: Couldn't determine the latest $APP_NAME version."
    exit 0
elif [[ "$latest_version" != "$installed_version" ]]; then
    # Sort version numbers to make sure the retrieved $latest_version
    # is actually greater than the $installed_version
    if printf '%s\n' "$installed_version" "$latest_version" | sort -V -C; then

        # $latest_version is greater than $installed_version
        echo "$latest_version is higher than $installed_version"
        # An update is needed
        echo "Installed version: $installed_version."
        echo "Updating to $latest_version..."
        # exit 1
    else
        # $latest_version is LOWER than $installed_version
        echo "Error: the installed version is greater than the latest version."
        echo "Installed: $installed_version"
        echo "'Latest': $latest_version"
        exit 0
    fi
else
    # The installed version is up to date
    echo "Latest version $latest_version, already installed."
    exit 0
fi

# echo "If statement catch-all."
# exit 0

############################################
############################################
# Main body of script

# These variables need to be declared again if breaking up the script
APP_NAME="Signal"

# Save logs to file
LOG_FILE="/Library/Addigy/.addigy_installs.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Prevent concurrent run
LOCK_FILE="/tmp/${APP_NAME}_install.lock"
if [ -f "$LOCK_FILE" ]; then
    existing_pid=$(cat "$LOCK_FILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
        echo "Another instance of this script is already running (PID $existing_pid). Exiting."
        exit 0
    else
        echo "Stale lock file found. Removing and continuing."
        rm -f "$LOCK_FILE"
    fi
else
    echo "Not running concurrently"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

RELEASES_URL="https://updates.signal.org/desktop/latest-mac.yml"
latest_version=$(curl -s $RELEASES_URL | grep -o "version: .*" | cut -d " " -f 2)
download_url="https://updates.signal.org/desktop/signal-desktop-mac-universal-$latest_version.dmg"
if [[ -d "/Applications/$APP_NAME.app" ]]; then installed_version=$(/usr/bin/defaults read "/Applications/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString); fi

# End of re-declaring variables
#####

swiftInstalled() {
    # Check if Swift Dialog is installed
    if [ ! -f "/usr/local/bin/dialog" ]; then
        echo "Swift Dialog not installed"
        return 1
    else
        echo "Swift Dialog installed"
    fi
}

alertHours() {
    # Check if alerting within the allowed window
    # Only give notifications if before 10am or after 4pm
    if [ $(date +%H) -lt 10 ] || [ $(date +%H) -gt 15 ]; then
        echo "Script is running in allowed alerting hours."
        return 0
    else
        echo "Script is not running in allowed alerting hours."
        return 1
    fi
}

zoom () {
    if ps aux | grep "zoom.us" | grep -q "aomhost"; then
        echo "A Zoom call is ongoing, exiting..."
        return 1
    else
        # No Zoom meeting
        return 0
    fi
}

popUpWindow() {
    # Download custom icon
    ICON_URL="YourIconHere"
    ICON_PATH="/tmp/Update_icon.png"
    curl -s -L -o "$ICON_PATH" "$ICON_URL"

    set +euo pipefail # Disable 'strict mode' so Addigy won't erroneously exit
    # if an option other than Button 1 is used.

    # Show Swift Dialog alert with macOS-native styling
    /usr/local/bin/dialog \
        --title "$APP_NAME Update Available" \
        --message "$APP_NAME version $latest_version is available.\n\nCurrent version: $installed_version\n\nClick Update Now to quit $APP_NAME, install the update, and reopen the app automatically." \
        --icon "$ICON_PATH" \
        --iconsize 128 \
        --button1text "Update Now" \
        --button2text "Later" \
        --timer 60 \
        --hidetimerbar \
        --defaultbutton 1 \
        --width 500 --height 220 \
        --titlefont "name=Helvetica,size=16,weight=semibold" \
        --messagefont "name=Helvetica,size=13,weight=regular" \
        --position bottomright \
        --ontop
    exitCode=$?
    # Check the exit code - Update Now returns returns 0, depleted timer returns 4
    # Later returns 2.

    if [[ -f "$ICON_PATH" ]]; then rm "$ICON_PATH"; fi
    if [[ "$exitCode" == "0" ]]; then
        echo "User clicked 'Update Now', continuing with $APP_NAME update."
        if pgrep -xq "$APP_NAME"; then killall "$APP_NAME"; fi
        echo "Continuing with install..."
        sleep 2
        return 0
    elif [[ "$exitCode" == "4" ]]; then
        # User let the timer run out
        echo "The timer ran out, deferring install."
        return 1
    else
        echo "$APP_NAME update was deferred."
        return 1
    fi
}

download () {
    # Make temp folder for downloads
    if [[ ! -d "/tmp/$APP_NAME" ]]; then mkdir -p "/tmp/$APP_NAME"; fi

    # Download the app
    echo "Downloading $APP_NAME..."
    curl -L -o "/tmp/$APP_NAME/$APP_NAME.dmg" "$download_url"
}

install () {
    mount_point=$(hdiutil attach -nobrowse "/tmp/$APP_NAME/$APP_NAME.dmg" | grep -o "/Volumes/$APP_NAME.*")

    # Rename existing app as backup
    if [[ -d "/Applications/$APP_NAME.app" ]]; then
        mv "/Applications/$APP_NAME.app" "/Applications/$APP_NAME.app.bak"
        backup=true
    fi

    # Copy new version
    sudo cp -Rf "$mount_point/$APP_NAME.app" /Applications/

    if [[ $? -ne 0 ]]; then
        echo "Install failed, restoring previous version..."
        rm -rf "/Applications/$APP_NAME.app"
        mv "/Applications/$APP_NAME.app.bak" "/Applications/$APP_NAME.app"
        hdiutil detach "$mount_point"
        return 1
    fi

    # Verify the new bundle is valid before committing
    if ! codesign --verify "/Applications/$APP_NAME.app" 2>/dev/null; then
        echo "Code signature invalid, restoring previous version..."
        rm -rf "/Applications/$APP_NAME.app"
        if $had_existing; then mv "/Applications/$APP_NAME.app.bak" "/Applications/$APP_NAME.app"; fi
        hdiutil detach "$mount_point"
        return 1
    fi

    # New version confirmed good, remove backup
    if $had_existing; then rm -rf "/Applications/$APP_NAME.app.bak"; fi
    hdiutil detach "$mount_point"
    rm -rf "/tmp/$APP_NAME"
}

# On the first run, the app will be downloaded before any
# potential popup windows for end users.
# This allows for immediate install after users click 'Update.'
if [[ ! -f "/tmp/$APP_NAME/$APP_NAME.dmg" ]]; then
    echo "Downloading $APP_NAME."
    download
else
    echo "$APP_NAME is already cached from a previous deferral."
fi

# Check if App is running
if pgrep -xq "$APP_NAME"; then
    if ! alertHours; then exit 0; fi # Check to make sure alerting withing the allowed window
    if ! zoom; then exit 0; fi # Check if Zoom is running
    echo "$APP_NAME is open, asking to install."
    if ! swiftInstalled; then exit 0; fi # Check if Swift Dialog is installed
    if ! popUpWindow; then exit 0; fi # Ask user for permission to update
    reopen_app="Yes"
else
    echo "$APP_NAME is not open, continuing with install..."
    reopen_app="No"
fi

if install; then
    echo "Install was successful"
else
    # remove cached download and retry
    if [[ -d "/tmp/$APP_NAME" ]]; then rm -rf "/tmp/$APP_NAME"; fi
    download
    install
    if [[ $? -ne 0 ]]; then
        echo "Install failed a second time"
        if [[ -d "/tmp/$APP_NAME" ]]; then rm -rf "/tmp/$APP_NAME"; fi
        exit 1
    fi
fi

if [ -d "/Applications/$APP_NAME.app" ]; then
    echo "$APP_NAME has been installed to Applications."
    installed_version=$(/usr/bin/defaults read "/Applications/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString)
    echo "Installed version $installed_version."
    if [ $reopen_app == "Yes" ]; then open "/Applications/$APP_NAME.app"; fi
    exit 0
else
    echo "An error occured installing $APP_NAME."
    exit 1
fi
