#!/bin/bash

############################################
############################################
# Use this part as the conditional script in Addigy
# 'exit 1' = install app

APP_NAME="1Password"
echo "Starting 'Install $APP_NAME.'"
update_only="No"

# Determine the latest version
RELEASES_URL="https://releasebot.io/updates/1password/1password-mac"
latest_version=$(curl -s $RELEASES_URL | grep -o "$APP_NAME for Mac [0-9.*]*" | head -n 1 | awk '{print $4}')
installed_version=$(/usr/bin/defaults read "/Applications/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)

# Check if installed and/or if an update is needed.
if [[ ! -d "/Applications/$APP_NAME.app" ]]; then
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

        # $latest_version is greater than $installed_version
        echo "$latest_version is higher than $installed_version"
        # An update is needed
        echo "Installed version: $installed_version."
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
    echo "Latest version $latest_version, already installed."
    exit 0
fi

echo "If statement catch-all."
exit 0

############################################
############################################
# Main body of script

# These variables need to be declared again if breaking up the script
APP_NAME="1Password"
RELEASES_URL="https://releasebot.io/updates/1password/1password-mac"
latest_version=$(curl -s $RELEASES_URL | grep -o "$APP_NAME for Mac [0-9.*]*" | head -n 1 | awk '{print $4}')
if [[ -d "/Applications/$APP_NAME.app" ]]; then installed_version=$(/usr/bin/defaults read "/Applications/$APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString); fi

# End of re-declaring variables
#####

# Latest .pkg version of the app
DOWNLOAD_URL="https://downloads.1password.com/mac/1Password.pkg"


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

# On the first run, the app will be downloaded before any
# potential popup windows for end users.
# This allows for immediate install after users click 'Update.'
if [[ ! -f "/tmp/$APP_NAME/$APP_NAME.pkg" ]]; then
    echo "Downloading $APP_NAME."
    download
else
    echo "$APP_NAME is already cached from a previous deferral."
fi

# Check if App is running
if pgrep -xq "$APP_NAME"; then
    echo "$APP_NAME is open, exiting instead of installing update."
    exit 0 # No update alerts, letting Addigy do that.
else
    echo "$APP_NAME is not open and needs to be updated, continuing with install."
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
