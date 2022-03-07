#!/bin/bash

PROGRAM_NAME="ramdisk.sh"

usage() {
    echo "usage: $PROGRAM_NAME [init | copy | help]"
    echo "  init      Initialise RAM Disk"
    echo "  copy      Copy files to RAM Disk. (Requires initialised ramdisk first)"
    echo "  sync      Copy files from RAM Disk back to original folders"
    echo "  remove    Remove the RAM Disk (WARNING: Will remove ALL files that reside on the RAM disk)"
    echo "  help      Display help (this page)"
    echo "When no argument is passed, the default is to run 'init' then 'copy'"
    exit 1
}

# Name of the ramdisk.
RAM_DISK_NAME="RAM Disk"
WORKING_DIRECTORY="/Users/jurriaandentoonder"
# The directories (or files) to copy to the ramdisk, relative from the working directory
#declare -a INCLUDED_DIRECTORIES=("git/gh/schuldenteller" "git/gl/energiebespaarders")
declare -a INCLUDED_DIRECTORIES=("git/gh/amdrxbot")

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
        notification "Succesfully removed $RAM_DISK_NAME, remember to disable the cron job for sync!"
    fi
}

if [[ $# -eq 0 ]]
then
    # Default flow (no arguments)
    init_ramdisk default
    copy_to_ramdisk
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
    else
        echo "Unknown argument $1."
        usage
    fi
fi
