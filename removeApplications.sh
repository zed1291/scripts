#!/bin/bash

# =============================================================================
# Self Service App Uninstaller
# This is meant to all users with Standard accounts to delete applications
# from the /Applications folder, which typically requires Admin access.
#
# This script is 99% vibe-coded using Mistral AI.
# It has been tested in Addigy and Iru, and found to be working.
# There is no guarantee it works for you, or that it does not
# break in the future.
# =============================================================================

DIALOG="/usr/local/bin/dialog"
ICON_URL="[web link to your icon here]"
ICON_PATH="/tmp/branded_icon.png"
DIALOG_CMD_FILE="/tmp/uninstall_dialog.cmd"
APP_DIR="/Applications"

# Bundle IDs of apps that must never appear in the uninstall list.
# Covers both the main app and any vendor uninstaller app with the same or
# related bundle ID prefix. Adjust IDs to match what's actually on your fleet.
#
# To verify on a device:
#   defaults read /Applications/AppName.app/Contents/Info CFBundleIdentifier
#
EXCLUDED_BUNDLE_IDS=(
    "com.addigy.MacManage"           # MacManage
    "com.huntress.app"               # Huntress
    "corp.sap.privileges"            # Privileges
    "com.crowdstrike.falcon.Agent"   # Falcon sensor daemon
    "com.crowdstrike.falcon.App"     # Falcon UI app
    "com.splashtop.Splashtop-Streamer" # Splashtop
)

# -----------------------------------------------------------------------------
# Logging: all output goes to both stdout and the system log
# Usage:
#   log_msg "some info message"
#   log_msg "something failed" err
# -----------------------------------------------------------------------------

LOGGER_TAG="Remove Applications"
ADDIGY_LOG="/Library/Addigy/.addigy_installs.log" # You'll likely want to change this location

log_msg() {
    local msg="$1"
    local level="${2:-info}"          # default to info; pass "err" for errors
    local priority="daemon.${level}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$msg"
    logger -t "$LOGGER_TAG" -p "$priority" -- "$msg"
    echo "[Remove Applications] ($timestamp) $msg" >> "$ADDIGY_LOG"
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

LOGGED_IN_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
LOGGED_IN_UID=$(id -u "$LOGGED_IN_USER" 2>/dev/null)

run_dialog() {
    "$DIALOG" "$@"
}

dialog_update() {
    echo "$1" >> "$DIALOG_CMD_FILE"
    sleep 0.2
}

cleanup() {
    [[ -f "$ICON_PATH" ]] && rm -f "$ICON_PATH"
    [[ -f "$DIALOG_CMD_FILE" ]] && rm -f "$DIALOG_CMD_FILE"
}
trap cleanup EXIT

# Resolve symlinks to canonical real path (works on macOS without realpath)
resolve_path() {
    local path="$1"
    if [[ -L "$path" ]]; then
        local target
        target=$(readlink "$path")
        if [[ "$target" != /* ]]; then
            target="$(dirname "$path")/$target"
        fi
        echo "$target"
    else
        echo "$path"
    fi
}

# Return 0 (true) if the given bundle ID matches any entry in EXCLUDED_BUNDLE_IDS
is_excluded_bundle_id() {
    local bundle_id="$1"
    [[ -z "$bundle_id" ]] && return 1
    for ex in "${EXCLUDED_BUNDLE_IDS[@]}"; do
        [[ "$bundle_id" == "$ex" ]] && return 0
    done
    return 1
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

echo "" >> "$ADDIGY_LOG"
log_msg "=== uninstall_app.sh started by $(whoami) ==="

if [[ ! -x "$DIALOG" ]]; then
    log_msg "ERROR: swiftDialog not found at $DIALOG. Please install swiftDialog first." err
    exit 1
fi

if [[ -z "$LOGGED_IN_USER" || -z "$LOGGED_IN_UID" ]]; then
    log_msg "ERROR: Could not determine logged-in user. Exiting." err
    exit 1
fi

log_msg "Script running as: $(whoami) | GUI session user: $LOGGED_IN_USER (UID: $LOGGED_IN_UID)"

curl -s -L -o "$ICON_PATH" "$ICON_URL" || true

# -----------------------------------------------------------------------------
# Build app list
# Parallel arrays: DISPLAY_NAMES, APP_PATHS, APP_TYPES ("delete" or "uninstaller")
# Tracks seen real paths to deduplicate symlinks pointing to same target
# -----------------------------------------------------------------------------

SELECT_ITEMS=""
declare -a DISPLAY_NAMES
declare -a APP_PATHS
declare -a APP_TYPES
declare -a SEEN_REAL_PATHS

# -- Pass 1: Top-level /Applications (direct rm -rf) --------------------------
while IFS= read -r -d '' path; do
    name=$(basename "$path" .app)

    bundle_id=$(defaults read "$path/Contents/Info" CFBundleIdentifier 2>/dev/null || true)

    # Skip system Apple apps
    [[ "$bundle_id" == com.apple.* ]] && continue

    # Skip protected apps by bundle ID
    if is_excluded_bundle_id "$bundle_id"; then
        log_msg "Skipping excluded app (bundle ID: ${bundle_id:-unknown}): $path"
        continue
    fi

    DISPLAY_NAMES+=("$name")
    APP_PATHS+=("$path")
    APP_TYPES+=("delete")
    SEEN_REAL_PATHS+=("$path")

    [[ -n "$SELECT_ITEMS" ]] && SELECT_ITEMS+=","
    SELECT_ITEMS+="$name"
done < <(find "$APP_DIR" -maxdepth 1 -name "*.app" -type d -print0 | sort -z)

# -- Pass 2: Vendor uninstaller apps, following symlinks, deduplicated ---------
# Search locations: /Applications (nested), /Applications/Utilities, /Library/Application Support/Adobe
SEARCH_PATHS=("$APP_DIR" "/Applications/Utilities" "/Library/Application Support/Adobe")

while IFS= read -r -d '' path; do
    real_path=$(resolve_path "$path")

    # Deduplicate: skip if we've already seen this real path
    already_seen=false
    for seen in "${SEEN_REAL_PATHS[@]}"; do
        [[ "$seen" == "$real_path" ]] && already_seen=true && break
    done
    [[ "$already_seen" == true ]] && continue
    SEEN_REAL_PATHS+=("$real_path")

    bundle_id=$(defaults read "$real_path/Contents/Info" CFBundleIdentifier 2>/dev/null || true)

    # Skip protected uninstaller apps by bundle ID
    if is_excluded_bundle_id "$bundle_id"; then
        log_msg "Skipping excluded uninstaller (bundle ID: ${bundle_id:-unknown}): $real_path"
        continue
    fi

    # Build a clean display label:
    # Walk up the directory tree, skipping generic/infrastructure folder names,
    # and use the first meaningful ancestor as the display label.
    GENERIC_DIRS=("Utils" "Utilities" "resources" "uninstall" "Uninstall" "HDBox" "DEBox" "DE6" "Contents" "MacOS" "Helpers" "Support" "bin" "Frameworks")
    SKIP_ROOTS=("/Applications" "/Applications/Utilities" "/Library" "/Library/Application Support" "/")

    parent_dir=$(dirname "$real_path")
    display_parent=""
    for _ in 1 2 3 4 5; do
        candidate=$(basename "$parent_dir")
        is_generic=false
        for g in "${GENERIC_DIRS[@]}"; do
            [[ "$candidate" == "$g" ]] && is_generic=true && break
        done
        is_root=false
        for r in "${SKIP_ROOTS[@]}"; do
            [[ "$parent_dir" == "$r" ]] && is_root=true && break
        done
        if [[ "$is_generic" == false && "$is_root" == false ]]; then
            display_parent="$candidate"
            break
        fi
        parent_dir=$(dirname "$parent_dir")
    done

    uninstaller_name=$(basename "$real_path" .app)

    if [[ -n "$display_parent" && "$display_parent" != "$uninstaller_name" ]]; then
        label="$display_parent (Uninstall)"
    else
        label="$uninstaller_name"
    fi

    DISPLAY_NAMES+=("$label")
    APP_PATHS+=("$real_path")
    APP_TYPES+=("uninstaller")

    [[ -n "$SELECT_ITEMS" ]] && SELECT_ITEMS+=","
    SELECT_ITEMS+="$label"

done < <(find -L "${SEARCH_PATHS[@]}" \
              -mindepth 2 -maxdepth 5 \
              \( -iname "Uninstall*.app" -o -iname "*Uninstall.app" -o -iname "*Uninstaller.app" \) \
              -type d -print0 2>/dev/null | sort -z)

if [[ ${#DISPLAY_NAMES[@]} -eq 0 ]]; then
    log_msg "No removable applications found. Exiting."
    exit 0
fi

log_msg "App list built: ${#DISPLAY_NAMES[@]} item(s) available for removal."

# -----------------------------------------------------------------------------
# Dialog 1: App picker
# -----------------------------------------------------------------------------

set +euo pipefail

PICKER_OUTPUT=$(run_dialog \
    --title "Uninstall an Application" \
    --message "Select an application to remove from this Mac.\n\\n\nThis action cannot be undone." \
    --icon "$ICON_PATH" \
    --iconsize 128 \
    --selecttitle "Installed Applications" \
    --selectitems "$SELECT_ITEMS" \
    --selectrequired \
    --button1text "Continue" \
    --button2text "Cancel" \
    --width 560 --height 300 \
    --titlefont "name=Helvetica,size=16,weight=semibold" \
    --messagefont "name=Helvetica,size=13,weight=regular" \
    --position center \
    --moveable \
    --json \
    2>/dev/null)
exitCode=$?

if [[ "$exitCode" != "0" ]]; then
    log_msg "User $LOGGED_IN_USER cancelled at app selection."
    exit 0
fi

SELECTED_LABEL=$(echo "$PICKER_OUTPUT" | sed -n 's/.*"SelectedOption"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | xargs)

if [[ -z "$SELECTED_LABEL" ]]; then
    log_msg "ERROR: Empty selection returned. Raw output: $PICKER_OUTPUT" err
    exit 1
fi

# Look up the label in DISPLAY_NAMES to get path and type
SELECTED_PATH=""
SELECTED_TYPE=""
SELECTED_NAME=""
for i in "${!DISPLAY_NAMES[@]}"; do
    if [[ "${DISPLAY_NAMES[$i]}" == "$SELECTED_LABEL" ]]; then
        SELECTED_PATH="${APP_PATHS[$i]}"
        SELECTED_TYPE="${APP_TYPES[$i]}"
        SELECTED_NAME=$(basename "$SELECTED_PATH" .app)
        break
    fi
done

if [[ -z "$SELECTED_PATH" || ! -e "$SELECTED_PATH" ]]; then
    log_msg "ERROR: Could not resolve path for selection: $SELECTED_LABEL" err
    exit 1
fi

log_msg "User $LOGGED_IN_USER selected: $SELECTED_LABEL | Path: $SELECTED_PATH | Type: $SELECTED_TYPE"

# -----------------------------------------------------------------------------
# Dialog 2: Confirmation
# -----------------------------------------------------------------------------

rm -f "$DIALOG_CMD_FILE"
touch "$DIALOG_CMD_FILE"

if [[ "$SELECTED_TYPE" == "uninstaller" ]]; then
    CONFIRM_MSG="Are you sure you want to uninstall **$SELECTED_LABEL**?\n\nThe vendor's uninstaller will run, and may require clicking 'ok' from another popup window."
    CONFIRM_BTN="Run Uninstaller"
else
    CONFIRM_MSG="Are you sure you want to uninstall **$SELECTED_LABEL**?\n\nThis cannot be undone."
    CONFIRM_BTN="Delete App"
fi

run_dialog \
    --title "Confirm Removal" \
    --message "$CONFIRM_MSG" \
    --icon "$ICON_PATH" \
    --iconsize 128 \
    --button1text "$CONFIRM_BTN" \
    --button2text "Cancel" \
    --width 540 --height 260 \
    --titlefont "name=Helvetica,size=16,weight=semibold" \
    --messagefont "name=Helvetica,size=13,weight=regular" \
    --position center \
    --moveable \
    --commandfile "$DIALOG_CMD_FILE" \
    2>/dev/null &

DIALOG_PID=$!
sleep 0.5

wait $DIALOG_PID
exitCode=$?

if [[ "$exitCode" != "0" ]]; then
    log_msg "User $LOGGED_IN_USER cancelled at confirmation for: $SELECTED_LABEL"
    exit 0
fi

log_msg "User $LOGGED_IN_USER confirmed removal of: $SELECTED_LABEL ($SELECTED_PATH)"

# -----------------------------------------------------------------------------
# Dialog 3: Progress
# -----------------------------------------------------------------------------

rm -f "$DIALOG_CMD_FILE"
touch "$DIALOG_CMD_FILE"

if [[ "$SELECTED_TYPE" == "uninstaller" ]]; then
    PROGRESS_MSG="Running the uninstaller for **$SELECTED_LABEL**."
    PROGRESS_TEXT="Launching uninstaller…"
else
    PROGRESS_MSG="Removing **$SELECTED_LABEL** from this Mac."
    PROGRESS_TEXT="Deleting $SELECTED_NAME.app…"
fi

run_dialog \
    --title "Uninstalling…" \
    --message "$PROGRESS_MSG" \
    --icon "$ICON_PATH" \
    --iconsize 128 \
    --progress \
    --progresstext "$PROGRESS_TEXT" \
    --button1text "Please wait…" \
    --button1disabled \
    --width 540 --height 250 \
    --titlefont "name=Helvetica,size=16,weight=semibold" \
    --messagefont "name=Helvetica,size=13,weight=regular" \
    --position center \
    --moveable \
    --commandfile "$DIALOG_CMD_FILE" \
    --button2 false \
    2>/dev/null &

DIALOG_PID=$!
sleep 0.5

# -----------------------------------------------------------------------------
# Execute: delete or run uninstaller binary directly as root
# -----------------------------------------------------------------------------

DELETE_EXIT=0

if [[ "$SELECTED_TYPE" == "uninstaller" ]]; then
    log_msg "Launching uninstaller binary: $SELECTED_PATH"
    dialog_update "progresstext: Running uninstaller…"

    UNINSTALLER_BIN=$(defaults read "$SELECTED_PATH/Contents/Info" CFBundleExecutable 2>/dev/null)

    if [[ -z "$UNINSTALLER_BIN" ]]; then
        log_msg "ERROR: Could not determine uninstaller binary name from bundle: $SELECTED_PATH" err
        DELETE_EXIT=1
    else
        UNINSTALLER_EXEC="$SELECTED_PATH/Contents/MacOS/$UNINSTALLER_BIN"
        if [[ ! -x "$UNINSTALLER_EXEC" ]]; then
            log_msg "ERROR: Uninstaller binary not executable: $UNINSTALLER_EXEC" err
            DELETE_EXIT=1
        else
            # For known Adobe apps: derive the product name from the label
            # (strip the " (Uninstall)" suffix) and pass it as a CLI argument.
            # The Adobe Acrobat Uninstaller accepts the product display name
            # as a positional argument to skip the picker UI.
            EXTRA_ARGS=()
            if [[ "$SELECTED_PATH" == *"/Adobe/"* ]]; then
                PRODUCT_NAME="${SELECTED_LABEL% (Uninstall)}"
                log_msg "Adobe uninstaller detected; passing product name: $PRODUCT_NAME"
                EXTRA_ARGS=("$PRODUCT_NAME")
            fi

            log_msg "Running: $UNINSTALLER_EXEC ${EXTRA_ARGS[*]}"
            "$UNINSTALLER_EXEC" "${EXTRA_ARGS[@]}" 2>&1
            DELETE_EXIT=$?
            log_msg "Uninstaller exited with code: $DELETE_EXIT"
        fi
    fi
else
    if pgrep -xq "$SELECTED_NAME"; then
        log_msg "$SELECTED_NAME is running; force quitting before removal."
        dialog_update "progresstext: Quitting $SELECTED_NAME…"
        killall "$SELECTED_NAME" 2>/dev/null
        sleep 1
    fi

    dialog_update "progresstext: Deleting $SELECTED_NAME.app…"
    log_msg "Removing: $SELECTED_PATH"
    rm -rf "$SELECTED_PATH"
    DELETE_EXIT=$?
fi

sleep 2

# -----------------------------------------------------------------------------
# Result
# -----------------------------------------------------------------------------

if [[ "$DELETE_EXIT" == "0" ]]; then
    log_msg "SUCCESS: Removal completed for: $SELECTED_PATH (initiated by $LOGGED_IN_USER)"

    if [[ "$SELECTED_TYPE" == "uninstaller" ]]; then
        SUCCESS_MSG="The uninstaller for **$SELECTED_LABEL** has finished."
    else
        SUCCESS_MSG="**$SELECTED_LABEL** has been successfully removed from this Mac."
    fi

    dialog_update "title: Removal Complete"
    dialog_update "message: $SUCCESS_MSG"
    dialog_update "icon: SF=checkmark.circle.fill,colour=#34c759"
    dialog_update "progresstext: Done"
    dialog_update "progress: complete"
    dialog_update "button1text: Done"
    dialog_update "button1: enable"
    wait $DIALOG_PID 2>/dev/null
else
    log_msg "ERROR: Removal failed with exit code $DELETE_EXIT for: $SELECTED_PATH (initiated by $LOGGED_IN_USER)" err

    dialog_update "title: Removal Failed"
    dialog_update "message: Something went wrong while removing **$SELECTED_LABEL**.\n\nError code: $DELETE_EXIT\n\nPlease contact IT for support."
    dialog_update "icon: SF=exclamationmark.triangle.fill,colour=#ff3b30"
    dialog_update "progresstext: Error"
    dialog_update "button1text: OK"
    dialog_update "button1: enable"
    wait $DIALOG_PID 2>/dev/null
    exit "$DELETE_EXIT"
fi

exit 0
