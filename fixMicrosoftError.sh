#!/bin/bash
#   Last updated November 2024
#
#   Purpose: deletes a temporary file that causes Microsoft Office apps to
#   have an error. the root cause is a bug that shows up when the user also
#   has Adobe Acrobat installed.
#
#   This script is a bandaid, and has options to run from Self Service,
#   so users can run it whenever they need, OR you can have it run on a
#   scheduled interval if the user complains they have to run the policy
#   alot.
#
##############################################################################

# Variables
QUITAPPS=$4         # Set as a parameter in Jamf
DELETEFOLDER=true   # Set true if always deleting the folder
ISOFFICERUNNING=$6  # Set as a parameter in Jamf

# Functions
isOfficeRunning () {
    officeApps=("Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint")
    for appName in "${officeApps[@]}"; do
        if pgrep "$appName" > /dev/null 2>&1; then
            DELETEFOLDER=false
            echo "An Office app is open: $appName"
            break
        fi
    done
}

quitApps () {
    killall 'Microsoft Excel' 'Microsoft PowerPoint' 'Microsoft Word' 2>/dev/null
    echo 'Quit all open Office applications.'
}

deleteFolder () {
    if [ -z "$3" ]; then
        echo "Error: User parameter (\$3) is not set."
        exit 1
    fi
    folderPath="/Users/$3/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized"
    if rm -rf "$folderPath"; then
        echo 'Deleted Startup folder.'
    else
        echo 'Error deleting Startup folder.'
        exit 1
    fi
}

# Main Logic
if [ "$ISOFFICERUNNING" == 'true' ]; then
    isOfficeRunning
fi

if [ "$QUITAPPS" == 'true' ]; then
    quitApps
fi

if [ "$DELETEFOLDER" == 'true' ]; then
    deleteFolder
fi
