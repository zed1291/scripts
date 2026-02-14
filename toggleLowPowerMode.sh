#!/bin/bash

# This toggles low power mode for Apple Silicon devices
status=$(pmset -g |grep lowpowermode)

if [ "${status: -1}" = "0" ]; then
    sudo pmset -a lowpowermode 1
else
    sudo pmset -a lowpowermode 0
fi
