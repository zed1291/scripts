#!/bin/bash 
#
#   Purpose: to be used as an extension attribute script in Jamf Pro.
#
#	Useful if you're using Jamf macOS Onboarding feature for zero touch
#	deployment. MacOS Onboarding wrties a file to a file after it completes.
#
##############################################################################

user=`defaults read /Library/Preferences/com.apple.loginwindow.plist lastUserName`
result=`sudo -u $user defaults read /Users/"$user"/Library/Preferences/com.jamfsoftware.selfservice.mac.plist com.jamfsoftware.selfservice.onboardingcomplete`

if [ "$result" == 1 ]; then
	echo "<result>Enrolled</result>"
else
	echo "<result>Not Enrolled</result>"
fi