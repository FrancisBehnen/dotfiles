#!/bin/bash
set -e

PROGRAM_NAME="ramdisk.sh"

usage() {
    echo "usage: $PROGRAM_NAME [init | copy | cron | help]"
    echo "  enable       Runs 'init' then 'copy' then 'add_plist'. This the fully automated way of enabling the ramdisk"
    echo "  disable      Runs 'remove_plist' then 'sync' then 'remove'. This is the fully automated way of disabling and removing the ramdisk"
    echo "Fine grained commands, to execute only partial steps:"
    echo "  init         Initialise RAM Disk"
    echo "  copy         Copy files to RAM Disk. (Requires initialised ramdisk first)"
    echo "  sync         Copy files from RAM Disk back to original folders"
    echo "  remove       Remove the RAM Disk (WARNING: Will remove ALL files that reside on the RAM disk)"
    echo "  cron         Display example crontab entry"
    echo "  add_plist    Add a plist file to users launchagents and load it, to trigger sync every minute"
    echo "  remove_plist Remove the plist to trigger sync every minute"
    echo "  help         Display help (this page)"
    echo "When no argument is passed, the default is to run 'enable'"
    exit 1
}

cron_example() {
    echo "Example crontab configuration:"
    echo
    echo "PATH=/usr/local/bin:/bin:/usr/bin"
    echo "* * * * * /Users/jurriaan/ramdisk.sh sync > /dev/null"
    echo
    echo "This will sync from the ramdisk every minute"
    echo "Also pipes the stdout to null, so only errors are outputted"
}

# Name of the ramdisk.
RAM_DISK_NAME="RAM Disk"
WORKING_DIRECTORY="/Users/jurriaan"
PLIST_NAME="nl.den-toonder.ramdisk.plist"
# The directories (or files) to copy to the ramdisk, relative from the working directory
#declare -a INCLUDED_DIRECTORIES=("git/gh/schuldenteller" "git/gl/energiebespaarders")
#declare -a INCLUDED_DIRECTORIES=("git/gh/amdrxbot")
#declare -a INCLUDED_DIRECTORIES=("git/gl/deb/")
declare -a INCLUDED_DIRECTORIES=("git/infrapod/")
#declare -a INCLUDED_DIRECTORIES=("git/gh/axolotl/")

notification() {
    local message="$1"
    local sound="${2:-Blow}"

    osascript -e "display notification \"$message\" with title \"RAMdisk script\" sound name \"$sound\""
}

show_error_msg() {
    local err_msg="❌  ERROR: $1"
    notification "$err_msg" "Basso"
    >&2 echo "$err_msg"
}

init_ramdisk() {
    source_called=$1
    if [ ! -d "/Volumes/$RAM_DISK_NAME" ]
    then
        echo "🔂  Initialising /Volumes/$RAM_DISK_NAME."
        diskutil erasevolume HFS+ 'RAM Disk' `hdiutil attach -nobrowse -nomount ram://16777216`
        if [ ! -d "/Volumes/$RAM_DISK_NAME" ]
        then
            show_error_msg "/Volumes/$RAM_DISK_NAME/ not found after initializing, exiting..."
            exit 1
        fi
        notification "Succesfully initialised $RAM_DISK_NAME. Don't forget to setup the sync cron job."
    else
        if [ "$source_called" = "default" ]
        then
            show_error_msg "/Volumes/$RAM_DISK_NAME/ already exists, skipping initalisation and exiting to prevent accidental overwrites on $RAM_DISK_NAME."
            >&2 echo "If you want to reinitialise the ramdisk, first run '$PROGRAM_NAME remove' to remove the RAM Disk"
            exit 1
        else
            >&2 echo "⚠️  WARNING: /Volumes/$RAM_DISK_NAME/ already exists, skipping initalisation."
        fi
        exit 1
    fi
    echo "✅ Succesfully initialized ramdisk."
}

add_plist() {
    cp "./$PLIST_NAME" "$HOME/Library/LaunchAgents/"
    sed -i '' "s#SEDREPLACEPWD#$PWD#g" "$HOME/Library/LaunchAgents/$PLIST_NAME" 
    launchctl load -w "$HOME/Library/LaunchAgents/$PLIST_NAME"
    echo "✅ Succesfully copied plist file to LaunchAgents and loaded it. The ramdisk is now synced automatically back to persistent storage every minute."
    notification "Succesfully copied $PLIST_NAME to LaunchAgents and loaded it!"
}

remove_plist() {
    launchctl unload -w "$HOME/Library/LaunchAgents/$PLIST_NAME"
    rm "$HOME/Library/LaunchAgents/$PLIST_NAME"
    notification "Succesfully removed plist and unloaded it!"
    echo "✅ Succesfully removed plist file, syncing is now stopped."
}

copy_to_ramdisk() {
    if [ ! -d "/Volumes/$RAM_DISK_NAME" ]
    then
        show_error_msg "/Volumes/$RAM_DISK_NAME/ has not been found, please initialise the ram disk first."
        exit 1
    fi
    echo "🔄  Copying files to /Volumes/$RAM_DISK_NAME/, please stand by..."
    for directory in "${INCLUDED_DIRECTORIES[@]}"; do
        echo "ℹ️    Copying files from $directory"
        rsync -a -R --info=progress2 "$WORKING_DIRECTORY/./$directory" /Volumes/"$RAM_DISK_NAME/" --delete
    done
    echo "✅ Succesfully copied over contents to ramdisk."
    notification "Succesfully copied over contents to $RAM_DISK_NAME"
}

sync_ramdisk() {
    if [ ! -d "/Volumes/$RAM_DISK_NAME" ]
    then
        show_error_msg "/Volumes/$RAM_DISK_NAME/ has not been found, please initialise the ram disk first."
        exit 1
    fi
    echo "🔄  Copying files from /Volumes/$RAM_DISK_NAME/ back to original directories, please stand by..."
    for directory in "${INCLUDED_DIRECTORIES[@]}"; do
        echo "ℹ️    Copying files from $directory"
        rsync -a -R --info=progress2 /Volumes/"$RAM_DISK_NAME/./$directory" "$WORKING_DIRECTORY" --delete
    done
    echo "✅ Succesfully synced ramdisk to persistent storage."
}

remove_ramdisk() {
    if [ ! -d "/Volumes/$RAM_DISK_NAME" ]
    then
        >&2 echo "⚠️  WARNING: /Volumes/$RAM_DISK_NAME/ has not been found."
        exit 1
    fi

    echo
    echo "##### WARNING #####"
    echo "This will PERMANTENLY delete all files that are on /Volumes/$RAM_DISK_NAME/ right now."
    echo "Please ensure you have the lastest version somewhere on non-volatile storage."
    echo 
    read -p "Are you sure you want to remove the RAM Disk? [yN] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        diskutil eject /Volumes/"$RAM_DISK_NAME" 
        echo "✅ Succesfully removed ramdisk."
        notification "Succesfully removed $RAM_DISK_NAME, remember to disable the cron job for sync!"
    fi
}

if [[ $# -eq 0 ]]
then
    # Default flow (no arguments)
    init_ramdisk default
    copy_to_ramdisk
    add_plist
else
    if [ "$1" = "help" ]
        then
            usage
    elif [ "$1" = "init" ]
    then
        init_ramdisk
    elif [ "$1" = "copy" ]
    then
        copy_to_ramdisk
    elif [ "$1" = "sync" ]
    then
        sync_ramdisk
    elif [ "$1" = "remove" ]
    then
        remove_ramdisk
    elif [ "$1" = "cron" ]
    then
        cron_example
    elif [ "$1" = "enable" ]
    then
        init_ramdisk default
        copy_to_ramdisk
        add_plist
    elif [ "$1" = "disable" ]
    then
        remove_plist
        sync_ramdisk
        remove_ramdisk
    else
        echo "Unknown argument $1."
        usage
    fi
fi
