#!/bin/bash 
#
#   Purpose: sends a wipe command to iPhones in bulk.
#
##############################################################################

# server and credential information
jamfProURL="URL"                        # Example "https://acme.jamfcloud.com"
username="username"                     # Enter the Jamf Pro username that has permissions to send 
password="password"                     # wipe commands to mobile devices.

# Path to the CSV file containing the serial numbers
# 
# The CVS is expected to have one column, optionally with the
# header "serialNumber" and then one serial number per line.
# There should always be an empty line after the list of serials.
# If the last row is not empty, then the final serial number won't
# be read.
fileName="" # Type the filename here
serial_file="/Users/$USER/Downloads/$fileName.csv"

# Check to make sure serial file exists at the specified location
if [ ! -f "$serial_file" ]; then
    echo "Error: CSV file not found at $serial_file" >&2
    exit 1
fi

# Request auth token.
authToken=$( /usr/bin/curl \
--request POST \
--silent \
--url "$jamfProURL/api/v1/auth/token" \
--user "$username:$password" )

# Parse auth token.
token=$( /usr/bin/plutil \
-extract token raw - <<< "$authToken" )

if [ -z "$token" ]; then
    echo "Error: Unable to retrieve auth token." >&2
    exit 1
fi

# echo "Token is $token"

################################
################################
################################

get_jamf_id() {
    local serial_number="$1"

    jamfId=$(curl -s -H "Accept: text/xml" \
        --header "Authorization: Bearer $token" \
        "$jamfProURL/JSSResource/mobiledevices/serialnumber/$serial_number/subset/general" | \
        grep -o "<id>[0-9]*</id>" | sed 's/<id>//;s/<\/id>//')

    if [ -z "$jamfId" ]; then
        echo "Error: Unable to retrieve Jamf ID for serial number $serial_number" >&2
        return 1
    fi

    echo "$jamfId"
    return 0
}

erase_iphone() {
    local serial_number="$1"
    local jamfId

    jamfId=$(get_jamf_id "$serial_number")
    if [ $? -ne 0 ]; then
        echo "Skipping erase for $serial_number due to Jamf ID retrieval error."
        return 1
    fi

    echo "Erasing $serial_number with Jamf ID: $jamfId"

    response=$(curl -s --write-out "HTTPSTATUS:%{http_code}" \
        --request POST \
        --url "$jamfProURL/api/v2/mobile-devices/$jamfId/erase" \
        --header 'accept: application/json' \
        --header 'content-type: application/json' \
        --header "Authorization: Bearer $token" \
        --data '
        {
        "preserveDataPlan": false,
        "disallowProximitySetup": false,
        "clearActivationLock": true
        }')

    # Extract HTTP status
    http_status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | sed 's/HTTPSTATUS://')
    http_body=$(echo "$response" | sed -e 's/HTTPSTATUS:[0-9]*//')

    if [ "$http_status" -ne 200 ]; then
        echo "Error erasing iPhone with Jamf ID $jamfId: HTTP $http_status - $http_body"
        return 1
    fi

    return 0
}

################################
################################
################################

erase_count=0
fail_count=0

while read -r serialNumber; do
    # Trim whitespace
    serialNumber=$(echo "$serialNumber" | tr -d '\r' | xargs)

    # Skip the header row
    if [[ "$serialNumber" != "serialNumber" ]]; then
        erase_iphone "$serialNumber"
        if [ $? -eq 0 ]; then
            ((erase_count++))
        else
            ((fail_count++))
        fi
    fi
done < "$serial_file"

echo ""
echo "Successfully sent erase commands to $erase_count devices."
echo "Failed to send erase commands to $fail_count devices."


################################
################################
################################

# Invalidate auth token.
response=$(curl -o /dev/null -s -w "%{http_code}" \
--header "Authorization: Bearer $token" \
--request POST \
--url "$jamfProURL/api/v1/auth/invalidate-token")

echo ""

if [[ "$response" -eq 204 ]]; then
    echo "Bearer token invalidated successfully."
else
    echo "Failed to invalidate token. HTTP Status: $response"
fi