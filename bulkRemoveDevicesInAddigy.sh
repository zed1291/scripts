#!/bin/bash
##################################################################
#
# This script is for bulk removal of devices in Addigy, via their
# serial numbers. Place a csv on your desktop with one serial
# number per line, and they will be removed.
#
##################################################################

ORG_ID="org_id_here"
API_KEY="key_here"

# Read the CSV file line by line
while IFS= read -r serial || [[ -n "$serial" ]]; do
    # Skip empty lines
    if [[ -z "$serial" ]]; then
        continue
    fi

    echo "Deleting device with serial: $serial"

    # Run the API command for each serial
    curl -X 'DELETE' \
        "https://api.addigy.com/api/v2/o/$ORG_ID/devices/$serial" \
        -H 'accept: application/json' \
        -H "x-api-key: $API_KEY"

    echo "" # Add a newline for readability
done < ~/Desktop/serials.csv
