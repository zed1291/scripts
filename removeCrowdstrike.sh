#!/bin/bash

check_for_crowdstrike() {
    if [ -d "/Applications/Falcon.app" ]; then return 1; fi
}

if check_for_crowdstrike; then
    echo "Crowdstrike is already not installed"
    exit 0
fi


expect <<- DONE
spawn /Applications/Falcon.app/Contents/Resources/falconctl uninstall -t
expect "Falcon Maintenance Token:"
send -- "Token goes here"
send -- "\r"
expect eof
DONE

if check_for_crowdstrike; then
    echo "Crowdstrike successfully removed."
    exit 0
else
    echo "Error: Crowdstrike is still installed."
    exit 1
fi