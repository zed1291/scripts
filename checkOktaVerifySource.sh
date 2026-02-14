#!/bin/bash 
#
#   Purpose: to be used as an extension attribute script in Jamf Pro
#
##############################################################################

# All apps downloaded from Mac App Store
# willl have a _MASReceipt folder.
directory="/Applications/Okta Verify.app/Contents/_MASReceipt/"

# Check if the directory exists.
if [ -d "$directory" ]; then
    result="Mac App Store"
else
    result="Package"
fi

if [ ! -d "/Applications/Okta Verify.app" ]; then
    result="Not installed"
fi

echo "<result>$result</result>"