#!/usr/bin/env bash
# es-tests.sh
#############
# This script lets you install a non-official emulationstation mod in RetroPie.
# It is for those who want to test and help devs with feedback.
#
# Bear in mind that many of those mods are still in development, and you need
# to know how to fix things if something break.


# globals ####################################################################

VERSION="zeta"

# TESTERS: set NO_WARNING_FLAG to 1 if you don't want that warning message.
NO_WARNING_FLAG=0

SCRIPT_URL="https://raw.githubusercontent.com/hex007/es-dev/master/es-tests.sh"
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
SCRIPT_NAME="$(basename "$0")"
REPO_FILE="es-repos.txt"
REPO_FILE_FULL="$SCRIPT_DIR/$REPO_FILE"
BACKTITLE="$SCRIPT_NAME (version: $VERSION) - manage EmulationStation mods on your RetroPie"
REPO_URL_TEMPLATE="https://github.com/"
SRC_DIR="$HOME/src"
RP_SETUP_DIR="$HOME/RetroPie-Setup"
RP_SUPPLEMENTARY_SRC_DIR="$RP_SETUP_DIR/scriptmodules/supplementary"
RP_PACKAGES_SH="$RP_SETUP_DIR/retropie_packages.sh"
RP_SUPPLEMENTARY_DIR="/opt/retropie/supplementary"

[[ "$1" == "--no-warning" ]] && NO_WARNING_FLAG=1
if [[ "$NO_WARNING_FLAG" == 0 ]]; then
    dialog --backtitle "W A R N I N G !" --title " WARNING! " \
    --yesno "\nThis script lets you install a non-official emulationstation mod in RetroPie. It is for those who want to test and help devs with feedback.\n\nBear in mind that many of those mods are still in development and you will need to know how to fix things if something break!\n\n\nDo you want to proceed?" \
    15 75 2>&1 > /dev/tty \
    || exit
fi


# dialog functions ##########################################################

function dialogMenu() {
    local text="$1"
    shift
    dialog --no-mouse \
        --backtitle "$BACKTITLE" \
        --cancel-label "Back" \
        --ok-label "OK" \
        --menu "$text\n\nChoose an option." 17 75 10 "$@" \
        2>&1 > /dev/tty
}

function dialogYesNo() {
    dialog --no-mouse --colors --backtitle "$BACKTITLE" --yesno "$@" 15 75 2>&1 > /dev/tty
}

function dialogMsg() {
    dialog --no-mouse --colors --ok-label "OK" --backtitle "$BACKTITLE" --msgbox "$@" 15 70 2>&1 > /dev/tty
}

function dialogInfo {
    dialog --colors --infobox "$@" 8 50 2>&1 >/dev/tty
}

# end of dialog functions ###################################################


function main_menu() {
    local choice

    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" --title " MAIN MENU " \
            --ok-label OK --cancel-label Exit \
            --menu "What do you want to do?" 17 75 10 \
            B "Build an ES repo/branch from the list" \
            L "Launch ES build using repo/branch from the list" \
            E "Edit the ES repo/branch list" \
            C "Choose an installed ES branch to be the default" \
            R "Remove an installed unofficial ES branch" \
            U "Update \"$SCRIPT_NAME\" script" \
            2>&1 > /dev/tty)

        case "$choice" in
            B)  build_es_branch_menu ;;
            L)  launch_es_branch_menu ;;
            E)  edit_repo_branch_menu ;;
            C)  set_default_es_menu ;;
            R)  remove_installed_es_menu ;;
            U)  update_script ;;
            *)  break ;;
        esac
    done
}


function build_es_branch_menu() {
    if [[ ! -s "$REPO_FILE_FULL" ]]; then
        dialogMsg "\"$REPO_FILE\" is empty!\n\nAdd some ES repo/branch first."
        return 1
    fi

    local options=()
    local choice
    local i

    while true; do
        i=1
        options=()
        while read -r repo branch; do
            options+=( $((i++)) "$repo ~ $branch" )
        done < "$REPO_FILE_FULL"
        choice=$(dialogMenu "List of available ES repository/branch to download, build and install (from \"$REPO_FILE\")." "${options[@]}") \
        || return 1
        repo=$(  echo "${options[2*choice-1]}" | tr -d ' ' | cut -d'~' -f1)
        branch=$(echo "${options[2*choice-1]}" | tr -d ' ' | cut -d'~' -f2)
        es_download_build_install "$repo" "$branch"
    done
}


function es_download_build_install() {
    local developer=$(echo "$repo" | sed "s#.*https://github.com/\([^/]*\)/.*#\1#")
    local es_src_dir=$(friendly_repo_branch_name)
    local es_install_dir="${RP_SUPPLEMENTARY_DIR}/$es_src_dir"
    es_src_dir="$SRC_DIR/$es_src_dir"

    dialogYesNo "Are you sure you want to download, build and install ${developer}'s $branch ES branch?\n\n(Note: source files will be stored at \"$es_src_dir\")" \
    || return

    dialogInfo "Downloading source files for ${developer}'s $branch ES branch..."
    
    # Clone repo on branch. If repo present then pull latest updates.
    # If pull fails then abort merge and pull selcting all changes from remote.
    # If that fails too then display error message.
(    git clone -b "$branch" "$repo" "$es_src_dir" 2> /dev/null ) || \
(    git -C "$es_src_dir" pull || ( git -C "$es_src_dir" merge --abort && git -C "$es_src_dir" pull -X theirs ) ) || \
(    dialogMsg "Failed to download ${developer}'s $branch ES branch.\n\nPlease, check your connection and try again." && return 1 )
    
    dialogInfo "Building ${developer}'s $branch ES branch..."
    if ! build_es; then
        echo "====== W A R N I N G !!! ======"
        echo "= SOMETHING WRONG HAPPENED!!! ="
        echo "==============================="
        read -t 30 -p "Look for error messages above. Press <enter> to continue."
        dialogMsg "Failed to build ${developer}'s $branch ES branch. :(\n\n(you should have seen the error messages, right?)"
        return 1
    fi
    
    while true; do
        dialog  --no-mouse --colors \
            --backtitle "$BACKTITLE" \
            --ok-label "Launch" \
            --extra-button --extra-label "Install" \
            --cancel-label "Back" \
            --yesno "SUCCESS!\n\nThe \Zb${developer}'s\ZB EmulationStation \Zb$branch\ZB branch was successfully built!\n\nWhat would you like to do now?" 15 75
        
        case $? in
            0 ) run_es || return 1;;
            3 ) install_es || return 1;;
            * ) return 0;;
        esac
    done
}


function build_es() {
    local ret=0
    local make_clean_flag=0
    dir=`pwd`
    
    # Find how may processors we can spare for compilation. If running on faster than dual core use 2 less
    proc=$(( `nproc` >= 4 ? `nproc`-2 : 1 ))

    # Check if running on Arm6 ie. Pi 0/1
    if [[ `uname -m` == "armv6l" ]]; then
        # Remove additional swap
        rpSwap on 512
    fi

    cd "$es_src_dir"
    git submodule update --init --recursive
    mkdir -p build
    cd build
    cmake .. -DFREETYPE_INCLUDE_DIRS=/usr/include/freetype2/ || ret=1
    # following RetroPie user Hex's suggestion [https://retropie.org.uk/forum/post/81034]
    dialogYesNo "We are ready to compile \Zb${developer}'s \"$branch\"\ZB ES branch.\n\nWould you like to skip 'make clean' before running 'make'?\n\n\ZbNote\ZB : This will make compilation faster if previously compiled." \
    || make clean
    make -j $proc || ret=1
    cd $dir
    
    # Check if running on Arm6 ie. Pi 0/1
    if [[ `uname -m` == "armv6l" ]]; then
        # Remove additional swap
        rpSwap off
    fi
    
    return $ret
}

function launch_es_branch_menu() {
    if [[ ! -s "$REPO_FILE_FULL" ]]; then
        dialogMsg "\"$REPO_FILE\" is empty!\n\nAdd some ES repo/branch first."
        return 1
    fi

    local options=()
    local choice
    local i

    while true; do
        i=1
        options=()
        while read -r repo branch; do
            options+=( $((i++)) "$repo ~ $branch" )
        done < "$REPO_FILE_FULL"
        choice=$(dialogMenu "List of available ES repository/branch to download, build and install (from \"$REPO_FILE\")." "${options[@]}") \
        || return 1
        repo=$(  echo "${options[2*choice-1]}" | tr -d ' ' | cut -d'~' -f1)
        branch=$(echo "${options[2*choice-1]}" | tr -d ' ' | cut -d'~' -f2)
        
        local developer=$(echo "$repo" | sed "s#.*https://github.com/\([^/]*\)/.*#\1#")
        local es_src_dir=$(friendly_repo_branch_name)
        es_src_dir="$SRC_DIR/$es_src_dir"
        run_es
    done
}

function run_es() {
    $es_src_dir/emulationstation || ( dialogMsg "You must first compile the repo and branch : \n\n $repo ~ $branch" && return 1 )
}

function install_es() {
    local ret=0
    
    if [ ! -f "$es_src_dir/emulationstation" ]; then
        dialogMsg "Failed to install ${developer}'s $branch ES branch. Binary not found.\n\n\ZbNote : You must first compile the binary from BUILD menu.\ZB"
        return 1
    fi
        
    
    # Handle installation on Linux System (!Raspberry pi)
    if [[ `uname -m` != arm* ]]; then
        dialogYesNo "\ZbNote : You are not running this on Raspberry Pi.\ZB\nES will be installed in '/usr/bin/'.\n\nWould you like to continue?" \
        || return 0
        
        ( sudo cp -f "$es_src_dir/emulationstation" "/usr/bin/emulationstation" || \
            ( read -t 30 -p "Look for error messages above. Press <enter> to continue."
                dialogMsg "Failed to install ${developer}'s $branch ES branch. :(\n\n(you should have seen the error messages, right?)"
                return 1 
            ) \
        ) \
        && dialogMsg "SUCCESS!\n\nThe ${developer}'s EmulationStation $branch branch was successfully installed!\n\nThis ES version is now the default emulationstation on your system.\n\nYou can choose which ES version will be the default one using the \"C\" option at Main Menu."
        return 0
    fi
    
    # Handle installation on Raspberry Pi
    dialogInfo "Installing ${developer}'s $branch ES branch in \"$es_install_dir\"."

    sudo mkdir -p "$es_install_dir"
    sudo cp -f "$es_src_dir/CREDITS.md" "$es_install_dir/"
    sudo cp -f "$es_src_dir/emulationstation" "$es_install_dir/" || ret=1
    sudo cp -f "$es_src_dir/emulationstation.sh" "$es_install_dir/" || ret=1
    sudo cp -f "$es_src_dir/GAMELISTS.md" "$es_install_dir/"
    sudo cp -f "$es_src_dir/README.md" "$es_install_dir/"
    sudo cp -f "$es_src_dir/THEMES.md" "$es_install_dir/"

    if ret; then
        rp_scriptmodule_action configure || ret=1
    fi

    if ! ret; then
        echo "====== W A R N I N G !!! ======"
        echo "= SOMETHING WRONG HAPPENED!!! ="
        echo "==============================="
        read -t 30 -p "Look for error messages above. Press <enter> to continue."
        dialogMsg "Failed to install ${developer}'s $branch ES branch in \"$es_install_dir\". :(\n\n(you should have seen the error messages, right?)"
        return 1
    fi
    
    dialogMsg "SUCCESS!\n\nThe ${developer}'s EmulationStation $branch branch was successfully installed!\n\nThis ES version is now the default emulationstation on your system.\n\nYou can choose which ES version will be the default one using the \"C\" option at Main Menu."
    return 0
}


function rp_scriptmodule_action() {
    [[ -z "$1" ]] && return 1

    local action="$1"
    local module_id="$2"
    local scriptmodule
    local ret=0

    [[ -z "$module_id" ]] && module_id=$(basename "$es_src_dir")

    if [[ "$module_id" == emulationstation || "$module_id" == emulationstation-kids ]]; then
        sudo "$RP_PACKAGES_SH" "$module_id" "$action"
        return $?
    fi

    scriptmodule="$RP_SUPPLEMENTARY_SRC_DIR/${module_id}.sh"

    cat > "$scriptmodule" << _EoF_
#!/usr/bin/env bash

rp_module_id="$module_id"
rp_module_desc="EmulationStation $module_id branch"
rp_module_section="exp"

function configure_${module_id}() {
        configure_emulationstation
}
_EoF_

    sudo "$RP_PACKAGES_SH" "$module_id" "$action" || ret=1
    rm -f "$scriptmodule"

    return $ret
}


function edit_repo_branch_menu() {
    local options=()
    local choice
    local i=1
    local repo
    local branch

    while true; do
        options=(A "Add an ES repo/branch to the list")
        [[ -s "$REPO_FILE_FULL" ]] && options+=(D "DELETE ALL REPO/BRANCHES IN THE LIST")

        while read -r line; do
            line_number=$(echo "$line" | cut -d: -f1)
            developer=$(echo "$line" | sed "s#.*https://github.com/\([^/]*\)/.*#\1#")
            branch=$(echo "$line" | sed "s,[^ ]* *,,")
            options+=( "$line_number" "Delete ${developer}'s \"$branch\" branch" )
        done < <(nl -s: -w1 "$REPO_FILE_FULL")

        choice=$(dialogMenu "Edit the ES repository/branch list \"$REPO_FILE\"." "${options[@]}") \
        || return 1

        case "$choice" in
            A)  add_repo_branch
                ;;
            D)  dialogYesNo "Are you sure you want to delete every single entry in \"$REPO_FILE_FULL\"?" \
                || continue
                echo -n > "$REPO_FILE_FULL"
                ;;
            *)  repo=$(  sed -n ${choice}p "$REPO_FILE_FULL" | cut -d' ' -f1)
                branch=$(sed -n ${choice}p "$REPO_FILE_FULL" | cut -d' ' -f2)
                dialogYesNo "Are you sure you want to delete the following line from \"$REPO_FILE_FULL\"?\n\n$repo $branch" \
                || continue
                sed -i ${choice}d "$REPO_FILE_FULL"
                remove_source_files "$SRC_DIR/$(friendly_repo_branch_name)"
                ;;
        esac
    done
}


function add_repo_branch() {
    local form=()
    local new_repo="$REPO_URL_TEMPLATE"
    local new_branch

    while true; do
        form=( $(dialog --form "Enter the ES repository URL and the branch name."  17 75 5 \
            "URL    :" 1 1 "$new_repo"   1 10 80 0 \
            "branch :" 2 1 "$new_branch" 2 10 30 0 \
            2>&1 > /dev/tty)
        ) || return 1
        new_repo="${form[0]}"
        new_branch="${form[@]:1}"

        dialogInfo "Adding \"$new_branch\" to the the list.\nPlease wait..."
        validate_repo_branch "$new_repo" "$new_branch" || continue
        echo "$new_repo $new_branch" >> "$REPO_FILE_FULL"
        return 0
    done
}


function validate_repo_branch() {
    local repo="$(echo $1 | sed 's/\.git$//')"
    local branch="$2"

    if grep -qi "$repo *$branch" "$REPO_FILE_FULL" ; then
        dialogMsg "The \"$branch\" branch from \"$repo\" is already in the list!\n\nNothing will be changed."
        return 1
    fi

    if [[ "$repo" != ${REPO_URL_TEMPLATE}* ]]; then
        dialogMsg "The repository URL you provided is invalid (doesn't seem to be a github one): \"$repo\"\n\nThis script only works with github repositories."
        return 1
    fi

    if ! curl -Is "${repo}/tree/${branch}" | grep -q '^Status: 200'; then
        dialogMsg "This is an invalid repo/branch:\n${repo}/tree/${branch}\n(Or maybe your connection is down and the script is unable to validate repo/branch.)\n\nNothing will be changed."
        return 1
    fi
    return 0
}


function set_default_es_menu() {
    # List all repositories available. If user requests for an install just copy
    # the binary. If binary is missing then notify user that they have not built
    # the binary. If repo is altogether missing then notify user that they have not
    # downloaded sources at all.
    
    if [[ ! -s "$REPO_FILE_FULL" ]]; then
        dialogMsg "\"$REPO_FILE\" is empty!\n\nAdd some ES repo/branch first."
        return 1
    fi

    local options=()
    local choice
    local i

    i=1
    options=()
    while read -r repo branch; do
        options+=( $((i++)) "$repo ~ $branch" )
    done < "$REPO_FILE_FULL"
    choice=$(dialogMenu "List of available ES repository/branch to install (from \"$REPO_FILE\")." "${options[@]}") \
    || return 1
    repo=$(  echo "${options[2*choice-1]}" | tr -d ' ' | cut -d'~' -f1)
    branch=$(echo "${options[2*choice-1]}" | tr -d ' ' | cut -d'~' -f2)
    
    local developer=$(echo "$repo" | sed "s#.*https://github.com/\([^/]*\)/.*#\1#")
    local es_src_dir=$(friendly_repo_branch_name)
    es_src_dir="$SRC_DIR/$es_src_dir"
    
    # Install and return. Only continue if error on install
    (install_es || return 1 ) && return 0
}


function get_installed_branches() {
    local installed_branches=( $(find "$RP_SUPPLEMENTARY_DIR" -type f -name emulationstation.sh ! -path '*/configscripts/*') )
    local b
    for b in "${installed_branches[@]}"; do
        basename "$(dirname "$b")"
    done
}


function remove_installed_es_menu() {
    local options=()
    local choice
    local i
    local es_branch

    while true; do
        i=1
        for es_branch in $(get_installed_branches); do
            [[ "$es_branch" == "emulationstation" || "$es_branch" == "emulationstation-kids" ]] \
            && continue
            options+=( $((i++)) "$es_branch" )
        done

        if [[ -z "${options[@]}" ]]; then
            dialogMsg "There's no unofficial ES branches installed on \"$RP_SUPPLEMENTARY_DIR\"!"
            return 1
        fi

        choice=$(dialogMenu "List of installed unofficial ES branches on \"$RP_SUPPLEMENTARY_DIR\".\n\nWhich one would you like to uninstall?" "${options[@]}") \
        || return 1
        es_branch="${options[2*choice-1]}"

        dialogYesNo "Are you sure you want to uninstall the \"$es_branch\" ES branch?" \
        || continue

        remove_source_files "$SRC_DIR/$es_branch"

        if rp_scriptmodule_action remove "$es_branch"; then
            if sudo "$RP_PACKAGES_SH" emulationstation configure; then
                dialogMsg "SUCCESS!\n\nThe \"$es_branch\" ES branch was uninstalled!\n\nThe official RetroPie ES is now the default emulationstation."
            else
                dialogMsg "WARNING!\n\nThe \"$es_branch\" ES branch was uninstalled.\nBut we failed to set the official RetroPie ES as the default emulationstation. You need to sort it."
            fi
        else
            dialogMsg "FAIL!!\n\nFailed to uninstall the \"$es_branch\" ES branch."
        fi
    done
}


function friendly_repo_branch_name() {
    local developer=$(echo "$repo" | sed "s#.*https://github.com/\([^/]*\)/.*#\1#")
    echo "es_${developer}_${branch}" | tr '[:upper:]' '[:lower:]'
}


function remove_source_files() {
    local es_src_dir="$1"
    if [[ -d "$es_src_dir" ]]; then
        dialogYesNo "Do you want to remove source files from \"$es_src_dir\" too?" \
        && rm -rf "$es_src_dir" \
        && dialogMsg "Source files from \"$es_src_dir\" has been removed."
    fi
}


function update_script() {
    local err_flag=0
    local err_msg

    dialogYesNo "Are you sure you want to download the latest version of \"$SCRIPT_NAME\" script?" \
    || return 1

    err_msg=$(wget "$SCRIPT_URL" -O "/tmp/$SCRIPT_NAME" 2>&1) \
    && err_msg=$(cp "/tmp/$SCRIPT_NAME" "$SCRIPT_DIR/$SCRIPT_NAME" 2>&1) \
    || err_flag=1

    if [[ $err_flag -ne 0 ]]; then
        err_msg=$(echo "$err_msg" | tail -1)
        dialogMsg "Failed to update \"$SCRIPT_NAME\".\n\nError message:\n$err_msg"
        return 1
    fi

    [[ -x "$SCRIPT_DIR/$SCRIPT_NAME" ]] && exec "$SCRIPT_DIR/$SCRIPT_NAME" --no-warning
    return 1
}

## @fn rpSwap()
## @param command *on* to add swap if needed and *off* to remove later
## @param memory total memory needed (swap added = memory needed - available memory)
## @brief Adds additional swap to the system if needed.
function rpSwap() {
    local command=$1
    local swapfile="$__swapdir/swap"
    case $command in
        on)
            rpSwap off
            local memory=$(free -t -m | awk '/^Total:/{print $2}')
            local needed=$2
            local size=$((needed - memory))
            mkdir -p "$__swapdir/"
            if [[ $size -ge 0 ]]; then
                echo "Adding $size MB of additional swap"
                fallocate -l ${size}M "$swapfile"
                chmod 600 "$swapfile"
                mkswap "$swapfile"
                swapon "$swapfile"
            fi
            ;;
        off)
            echo "Removing additional swap"
            swapoff "$swapfile" 2>/dev/null
            rm -f "$swapfile"
            ;;
    esac
}

# START HERE #################################################################

main_menu
