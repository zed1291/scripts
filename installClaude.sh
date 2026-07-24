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

APP_NAME="Claude"

# Get the console user home directory
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "$LOGNAME")
APP_PATHS=("/Applications/$APP_NAME.app" "/Users/$CONSOLE_USER/Applications/$APP_NAME.app")

echo ""
echo "Starting 'Install $APP_NAME.' ($(date '+%Y-%m-%d %H:%M:%S'))"
update_only="Yes" # Change this to 'No' if you want to install when not yet installed

# Determine the latest version
RELEASES_URL="https://downloads.claude.ai/releases/darwin/universal/RELEASES.json"
releases_data=$(curl -fs "$RELEASES_URL")
download_url=$(echo "$releases_data" | grep -o '"url":"[^"]*"' | cut -d'"' -f4 | sed 's/\.zip$/.pkg/')
latest_version=$(echo "$releases_data" | grep -o '"url":"[^"]*"' | cut -d'"' -f4 | grep -oE '/[0-9]+\.[0-9]+\.[0-9]+/' | head -n1 | tr -d '/')

# Check all possible paths for installed version
installed_version=""
for app_path in "${APP_PATHS[@]}"; do
    if [ -d "$app_path" ]; then
        installed_version=$(/usr/bin/defaults read "$app_path/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
        if [ -n "$installed_version" ]; then
            break
        fi
    fi
done

echo "Latest: $latest_version, installed: $installed_version"
echo "Download URL: $download_url"

# Check if installed and/or if an update is needed.
app_installed=false
for app_path in "${APP_PATHS[@]}"; do
    if [ -d "$app_path" ]; then
        app_installed=true
        break
    fi
done

if [[ "$app_installed" == false ]]; then
    # Not installed
    if [[ $update_only == "Yes" ]]; then
        echo "$APP_NAME is not installed, and update-only is selected. Exiting..."
        exit 0
    fi
    echo "$APP_NAME is not installed. Installing..."
    exit 1
elif [ -z "$latest_version" ]; then
    # Cannot compare installed version with latest version
    echo "Error: Couldn't determine the latest $APP_NAME version."
    exit 0
elif [[ "$latest_version" != "$installed_version" ]]; then
    # Sort version numbers to make sure the retrieved $latest_version
    # is actually greater than the $installed_version
    if printf '%s\n' "$installed_version" "$latest_version" | sort -V -C; then
        echo "Updating to $latest_version..."
        exit 1
    else
        # $latest_version is LOWER than $installed_version
        echo "Error: the installed version is greater than the latest version."
        echo "Installed: $installed_version"
        echo "'Latest': $latest_version"
        exit 0
    fi
else
    # The installed version is up to date
    echo "Latest available version $installed_version, already installed."
    exit 0
fi

echo "If statement catch-all."
exit 0

############################################
############################################
# Main body of script
set +euo pipefail # Disable 'strict mode' so Addigy won't erroneously exit

# These variables need to be declared again if breaking up the script
APP_NAME="Claude"
RELEASES_URL="https://downloads.claude.ai/releases/darwin/universal/RELEASES.json"
releases_data=$(curl -fs "$RELEASES_URL")
download_url=$(echo "$releases_data" | grep -o '"url":"[^"]*"' | cut -d'"' -f4 | sed 's/\.zip$/.pkg/')

# Define possible installation locations
# Get the console user home directory
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null || echo "$LOGNAME")
APP_PATHS=("/Applications/$APP_NAME.app" "/Users/$CONSOLE_USER/Applications/$APP_NAME.app")

# Save logs to file
LOG_FILE="/Library/Addigy/.addigy_installs.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# End of re-declaring variables
#####

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

download () {
    # Make temp folder for downloads
    if [[ ! -d "/tmp/$APP_NAME" ]]; then mkdir -p "/tmp/$APP_NAME"; fi

    # Download the app
    echo "Downloading $APP_NAME..."
    curl -L -o "/tmp/$APP_NAME/$APP_NAME.pkg" "$download_url"

}

install () {
    # Install the .pkg to /Applications
    echo "Installing $APP_NAME to /Applications..."
    sudo installer -pkg "/tmp/$APP_NAME/$APP_NAME.pkg" -target /
    if [[ $? -ne 0 ]]; then
        echo "Install failed"
        return 1
    fi

    # Clean up
    rm -rf "/tmp/$APP_NAME"
}

checkIfOpen() {
    # Check if App is running
    if pgrep -xq "$APP_NAME"; then
        echo "$APP_NAME is open, exiting instead of installing."
        return 1
    else
        echo "$APP_NAME is not open, continuing with install..."
    fi
}

if ! checkIfOpen; then exit 0; fi

# Only re-download if not cached already
if [[ ! -f "/tmp/$APP_NAME/$APP_NAME.pkg" ]]; then
    echo "Downloading $APP_NAME."
    download
else
    echo "$APP_NAME was cached from a previous deferral."
fi

if ! checkIfOpen; then exit 0; fi

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

# Check if installed in either location
app_found=false
for app_path in "${APP_PATHS[@]}"; do
    if [ -d "$app_path" ]; then
        echo "$APP_NAME has been installed to $app_path."
        installed_version=$(/usr/bin/defaults read "$app_path/Contents/Info.plist" CFBundleShortVersionString)
        echo "Version $installed_version."
        app_found=true
        break
    fi
done

if [ "$app_found" = true ]; then
    exit 0
else
    echo "An error occured installing $APP_NAME."
    exit 1
fi
