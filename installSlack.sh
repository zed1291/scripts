#!/bin/bash

############################################
############################################
# Use this part as the conditional script in Addigy
# 'exit 1' = install app

APP_NAME="Slack"

# Get the console user home directory
logged_in_user=$(stat -f%Su /dev/console 2>/dev/null || echo "$LOGNAME")
APP_PATHS=("/Applications/$APP_NAME.app" "/Users/$logged_in_user/Applications/$APP_NAME.app")

# Save logs to file
LOG_FILE="/Library/Addigy/.addigy_installs.log"

# If over 1MB, delete the first 512KB of lines
if [ -f "$LOG_FILE" ] && [ $(wc -c < "$LOG_FILE") -gt 1048576 ]; then
    tail -c 524288 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "Starting 'Install $APP_NAME.' ($(date '+%Y-%m-%d %H:%M:%S'))"
update_only="No"

# Determine the latest version
RELEASES_URL="https://slack.com/release-notes/mac"
DOWNLOAD_URL="https://slack.com/api/desktop.latestRelease?redirect=1&variant=pkg&arch=universal"
latest_version=$(curl -s "$RELEASES_URL" | grep -o 'Slack [0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')

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
public_version=$(curl -s -L -I "$DOWNLOAD_URL" \
  | grep -i "^location:" \
  | sed -E 's/^[Ll]ocation:[[:space:]]*(https:\/\/.*)/\1/' \
  | tail -n1 \
  | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' \
  | head -n1
)
echo "Latest: $latest_version, public: $public_version, installed: $installed_version"

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
elif [[ "$latest_version" != "$installed_version" && "$public_version" != "$installed_version" ]]; then
    # Sort version numbers to make sure the retrieved $latest_version
    # is actually greater than the $installed_version
    if printf '%s\n' "$installed_version" "$latest_version" | sort -V -C; then

        # $latest_version is greater than $installed_version
        # An update is needed
        # echo "Installed version: $installed_version."
        echo "Updating to $public_version..."
        exit 1
    else
        # $latest_version is LOWER than $installed_version
        echo "Error: the installed version is greater than the latest version."
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
APP_NAME="Slack"
DOWNLOAD_URL="https://slack.com/api/desktop.latestRelease?redirect=1&variant=pkg&arch=universal"

# Get the console user home directory
logged_in_user=$(stat -f%Su /dev/console 2>/dev/null || echo "$LOGNAME")
APP_PATHS=("/Applications/$APP_NAME.app" "/Users/$logged_in_user/Applications/$APP_NAME.app")

# End of re-declaring variables
#####

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

download () {
    # Make temp folder for downloads
    if [[ ! -d "/tmp/$APP_NAME" ]]; then mkdir -p "/tmp/$APP_NAME"; fi

    # Download the app
    echo "Downloading $APP_NAME..."
    curl -L -o "/tmp/$APP_NAME/$APP_NAME.pkg" "$DOWNLOAD_URL"

}

install () {
    # Install the .pkg
    echo "Installing $APP_NAME to /Applications..."
    sudo installer -pkg "/tmp/$APP_NAME/$APP_NAME.pkg" -target /Applications
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
        # echo "$APP_NAME is open, letting their .pkg installer handle that"
        echo "$APP_NAME is open, exiting instead of installing."
        return 1
    else
        echo "$APP_NAME is not open and needs to be updated, continuing with install..."
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
