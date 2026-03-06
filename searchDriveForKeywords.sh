#!/bin/bash

# Copy/paste each block into the terminal that
# has gam installed.
# I recommend *not* using the Google Cloud Console,
# because it'll time out during many of these steps.
#
# Note: there are variables like $label, $it_email_address,
# and $ids_file that are declared multiple times.
# 
# This is because it is likely that you will step away
# from this script as it is running a time intensive task
# and if you're ssh-ing into a VM, you may need
# to re-declare these variables when you come back.
#
# If you're using gam locally, this wont be a problem.
# Otherwise, make sure you copy/paste the content of
# these variables every time they appear in this script.

###################################################
###################################################
#
# This section is for the search terms, and the same
# array will be used for searching both all MyDrives
# and all Shared Drives.
#
###################################################
###################################################

# Each sub-array is stored as a string with | as a delimiter
searchTerms=(
    "keyword1|keyword2" # must include both keywords
    "keyword3" # must include just this keyword
)

###################################################
###################################################
#
# This section is for searching all MyDrives using
# the above search terms, and then adding a label
# to the found files.
#
###################################################
###################################################

# Single CSV file for all results
output_file="gam_results/all_results.csv"
mkdir -p gam_results # create folder that will be used for storing results
touch $output_file  # create export file

for item in "${searchTerms[@]}"; do # this is for personal drives
    IFS='|' read -ra subarray <<< "$item"
    if [ "${#subarray[@]}" -eq 1 ]; then
        echo "Searching for one item: ${subarray[0]}"
        gam all users show filelist query "fullText contains '${subarray[0]}'" fields id,title,owners,alternatelink >> "$output_file"
    elif [ "${#subarray[@]}" -eq 2 ]; then
        echo "Searching for two items: ${subarray[0]} and ${subarray[1]}"
        gam all users show filelist query "fullText contains '${subarray[0]}' and fullText contains '${subarray[1]}'" fields id,title,owners,alternatelink >> "$output_file"
    else
        echo "Unexpected number of items in: $item"
    fi
done

# Add the label to all found files in user's myDrive
awk '!seen[$0]++' $output_file > temp.csv && mv temp.csv $output_file # Make CSV only have unique lines
label="SJiJFhQlI" # use correct label ID here
gam csv "$output_file" gam user ~Owner process filedrivelabels id ~id addlabel "$label"

###################################################
###################################################
#
# This section is for searching all Shared Drives
# using the above search terms, and then adding a
# label to the found files.
#
###################################################
###################################################

# Gets all the Drive IDs of the Shared Drives
# that $it_email_address is a part of.
it_email_address="it@domain.com" # use correct email here
ids_file="gam_results/shared_drive_ids.csv"
echo "id" > $ids_file
gam user $it_email_address show shareddrive fields id | grep "Shared Drive ID:" | awk '{print $4}' >> $ids_file

sharedDriveOutput="gam_results/shared_drive_output.csv"
touch $sharedDriveOutput # create export file

for item in "${searchTerms[@]}"; do # this is for shared drives
    IFS='|' read -ra subarray <<< "$item"
    if [ "${#subarray[@]}" -eq 1 ]; then
        echo "Searching for one item: ${subarray[0]}"
        gam csv $ids_file gam user $it_email_address print filelist fullquery "fullText contains '${subarray[0]}'" select teamdriveid ~id showownedby any id title filepath >> "$sharedDriveOutput"
    elif [ "${#subarray[@]}" -eq 2 ]; then
        echo "Searching for two items: ${subarray[0]} and ${subarray[1]}"
        gam csv $ids_file gam user $it_email_address print filelist fullquery "fullText contains '${subarray[0]}' and fullText contains '${subarray[1]}'" select teamdriveid ~id showownedby any id title filepath >> "$sharedDriveOutput"
    else
        echo "Unexpected number of items in: $item"
    fi
done

# add the label to all found files in Shared Drives
awk '!seen[$0]++' $sharedDriveOutput > temp.csv && mv temp.csv $sharedDriveOutput # Make CSV only have unique lines

label="SJiJFhQlI"
gam csv "$sharedDriveOutput" gam user $it_email_address process filedrivelabels id ~id addlabel "$label"

###################################################
###################################################
#
# This section is for verifying the labels were
# added to the files that need them.
#
###################################################
###################################################

# Verify labels were added
label="SJiJFhQlI"                # use correct label ID here
it_email_address="it@domain.com" # use correct email here
ids_file="gam_results/shared_drive_ids.csv"

# MyDrive
# Filter the sheet that this outputs using the 'labelInfo.labels' column for rows
# that are not blank. Those will be the files that actually have the label.
gam all users print filelist fields id,name,owners,webViewLink,labelinfo includelabels "labels/$label" todrive

# Shared Drives
gam csv "$ids_file" gam user $it_email_address print filelist query "'labels/$label' in labels" select teamdriveid ~id fields id,drivename,name,driveid,mimetype,labelinfo includelabels "labels/$label" > verifySharedDriveLabels.csv