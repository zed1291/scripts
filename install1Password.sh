#!/bin/bash
# Last updated 14 February 2026

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

swiftInstalled() {
    # Check if Swift Dialog is installed
    if [ ! -f "/usr/local/bin/dialog" ]; then
        echo "Swift Dialog not installed"
        exit 1
    else
        echo "Swift Dialog is installed."
    fi
}

reduceAlertFatigue () {
    parameter="$1"
    if [[ $parameter == "Check" ]]; then
        if [[ ! -f "/tmp/alertFatigue_$APP_NAME.txt" ]]; then
            # This is the first pass or the alert
            # fatigue cycle has completed.
            return 0
        fi
        return 1
    fi

    if [[ $parameter == "Read" ]]; then
        # read number
        countdown=$(<"/tmp/alertFatigue_$APP_NAME.txt")
        echo "Countdown is: $countdown"
        if [[ $countdown != 0 ]]; then
            return 1
        fi
        return 0
    fi

    if [[ $parameter == "Write" ]]; then
        echo "5" > "/tmp/alertFatigue_$APP_NAME.txt"
        echo "Set Alert fatigue to 5"
        return 0
    fi

    if [[ $parameter == "Count down" ]]; then
        # subtract one from the number that already exists
        countdown=$(<"/tmp/alertFatigue_$APP_NAME.txt")
        countdown=$((countdown - 1))
        echo "$countdown" > "/tmp/alertFatigue_$APP_NAME.txt"
        echo "Decreased the alert fatigue number by 1."
        return 0
    fi

    if [[ $parameter == "Remove" ]]; then
        rm "/tmp/alertFatigue_$APP_NAME.txt"
        echo "Removed alert fatigue file"
        return 0
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
    ICON_URL="your icon here"
    ICON_PATH="/tmp/Update_icon.png"
    curl -s -L -o "$ICON_PATH" "$ICON_URL"

    echo "Showing popup"

    # Show Swift Dialog alert with macOS-native styling
    /usr/local/bin/dialog \
        --title "$APP_NAME Update Available" \
        --message "$APP_NAME version $latest_version is available.\n\nCurrent version: $installed_version\n\nClick Update Now to quit $APP_NAME, install the update, and reopen the app automatically." \
        --icon "$ICON_PATH" \
        --iconsize 128 \
        --button1text "Update Now" \
        --button2text "Later" \
        --timer 90 \
        --hidetimerbar \
        --defaultbutton 1 \
        --width 500 --height 220 \
        --titlefont "name=Helvetica,size=16,weight=semibold" \
        --messagefont "name=Helvetica,size=13,weight=regular" \
        --position bottomright \
        --ontop

    # Check the exit code - button 1 returns 0, button 2 returns 2
    DIALOG_EXIT_CODE=$?

    if [[ "$DIALOG_EXIT_CODE" == "0" ]]; then
        echo "User clicked 'Update Now', continuing with $APP_NAME update."
        if pgrep -xq "$APP_NAME"; then killall "$APP_NAME"; fi
        echo "Continuing with install..."
        rm "$ICON_PATH"
        sleep 2
    elif [[ "$DIALOG_EXIT_CODE" == "4" ]]; then
        reduceAlertFatigue "Write"
        echo "The timer ran out, deferring install."
        rm "$ICON_PATH"
        exit 0
    else
        # Writes alert fatigue file to 5
        reduceAlertFatigue "Write"
        echo "$APP_NAME update was deferred."
        rm "$ICON_PATH"
        exit 0
    fi
}

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
    # Returns 0 if the alert fatigue file doesn't exist
    # This is either the first time this user has had a popup,
    # or it has been deleted after previously completing the cycle.
    if reduceAlertFatigue "Check"; then
        echo "No alert fatigue"
    else
        # Return 0 if alert fatigue number is 0
        # Return 1 if alert fatigue number is not 0
        if reduceAlertFatigue "Read"; then
            # Delete the alert fatigue file
            reduceAlertFatigue "Remove"
        else
            # Count down the alert fatigue number
            reduceAlertFatigue "Count down"
        fi

        echo "Exiting to avoid alert fatigue"
        exit 0
    fi

    swiftInstalled
    if zoom; then # check to see if there is an active zoom call
        echo "$APP_NAME is open, asking to install..."
        popUpWindow
    else
        # Exit due to ongoing zoom call
        exit 0
    fi
    reopen_app="Yes"
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
    echo "Version $latest_version."
    if [ $reopen_app == "Yes" ]; then open "/Applications/$APP_NAME.app"; fi
    exit 0
else
    echo "An error occured installing $APP_NAME."
    exit 1
fi
