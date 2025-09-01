# This was the start of a script to programmatically traverse the whole folder tree and link all files.
# I never finished it.
# Code copied from: https://askubuntu.com/questions/968887/recursive-bash-script-to-collect-information-about-each-file-in-a-directory-stru
# #!/usr/bin/env zsh

for i in ./**/*
do
    if [ -f "$i" ];
    then
        printf "Path: %s\n" "${i%/*}" # shortest suffix removal
        printf "Filename: %s\n" "${i##*/}" # longest prefix removal
        printf "Extension: %s\n"  "${i##*.}"
        printf "Filesize: %s\n" "$(du -b "$i" | awk '{print $1}')"
        # some other command can go here
        printf "\n\n"
    fi
done
