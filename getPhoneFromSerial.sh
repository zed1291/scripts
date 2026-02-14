#!/bin/bash
#   Last updated November 2024
#
#   Purpose: for reading a list of phone serial numbers and getting the
#   active phone line.
#
##############################################################################

# server and credential information
jamfProURL="URL"                        # Example "https://acme.jamfcloud.com"
username="username"                     # Enter the Jamf Pro username that has permissions to read
password="password"                     # mobile devices.

# request auth token
authToken=$( /usr/bin/curl \
--request POST \
--silent \
--url "$jamfProURL/api/v1/auth/token" \
--user "$username:$password" )

# parse auth token
token=$( /usr/bin/plutil \
-extract token raw - <<< "$authToken" )

# Path to the CSV file containing the device information
fileName="" # Type the filename here
serial_file="/Users/$USER/Downloads/$fileName.csv"
output_file="/Users/$USER/Desktop/phoneNumbers.csv"

# Clear the output file
> "$output_file"

# Function to retrieve and append phone numbers to output file
getPhoneNumbers() {
    serial_number=$1
    response=$(curl -s --request GET \
     --url "$jamfProURL/JSSResource/mobiledevices/serialnumber/$serial_number" \
     -H "Authorization: Bearer ${token}" \
     --header 'accept: application/json')

    # Extract phone number from JSON
    phone_number=$(echo "$response" | grep -o '"phone_number":"[+0-9]*"' | sed 's/"phone_number":"\([+0-9]*\)"/\1/')

    # Write only the phone number to the output file if found
    if [[ -n "$phone_number" ]]; then
        echo "$phone_number" >> "$output_file"
    else
        echo "No phone number found for serial number: $serial_number"
    fi
}

# Process each serial number in the CSV file
while read -r serialNumber; do
    # Trim whitespace
    serialNumber=$(echo "$serialNumber" | tr -d '\r' | xargs)

    # Skip the header row
    if [[ "$serialNumber" != "serialNumber" ]]; then
        getPhoneNumbers "$serialNumber"
    fi
done < "$serial_file"

# Invalidate auth token
response=$(curl -o /dev/null -s -w "%{http_code}" \
--header "Authorization: Bearer $token" \
--request POST \
--url "$jamfProURL/api/v1/auth/invalidate-token")

# Add token invalidation status to output
if [[ "$response" -eq 204 ]]; then
    echo "Bearer token invalidated successfully."
else
    echo "Failed to invalidate token. HTTP Status: $response"
fi

# Remove duplicate lines and overwrite the file
awk '!seen[$0]++' "$output_file" | sed -E 's/^\+?1?//g' > temp.csv && mv temp.csv "$output_file"
echo "De-duped!"
