#!/bin/bash

DESC=$(cat <<'EOF'
######################################################################
# /boot cleanup                                                      #
#                                                                    #
# A script that cleans /boot with the following steps:               #
# 1) Remove all old kernels but 2                                    #
# 1) Remove unused kernel dependencies (UEK)                         #
# 2) Remove old initramfs-rescue                                     #
# 2) Remove old initram-fs                                           #
# 3) Check if one of the remaining kernels is the GRUB default entry #
# 4) If not, automatically select the newest kernel                  #
######################################################################

----------------------------------------------------------------------
EOF
)

set -eo pipefail



# Declare log levels
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["PROMPTS"]=2
    ["SILENT"]=3
)

# Function for logging
# First argument: loglevel
# Second argument: message
log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ ${LOG_LEVELS[$level]} -lt ${LOG_LEVELS[$LOGLEVEL]} ]]; then
        return 0
    fi
    
    echo "[$timestamp][$level]: $message"
}

# Like log, but only the message argument and exits 1
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][ERROR]: $message" >&2
    exit 1
}

# Function for y/n confirmation
# The arguments are pairs of a "title" (string) and a command (bash function)
# This will be used to show the user data that is relevant for their confirmation
confirm() {
    if [[ "$ALWAYS_YES" == true ]]; then
        return 0
    fi
    
    log "DEBUG" "Printing confirm info"
    
    echo "================================"
    
    while [[ $# -gt 1 ]]; do
        echo "$1:"
        echo
        eval "$2"
        shift 2
        echo "================================"
    done
    
    log "DEBUG" "Reading user input"
    
    read -p "Continue? [y/N]: " response
    
    if [[ "${response,,}" != "y" && "${response,,}" != "yes" ]]; then
        exit 1
    fi
}



# Default flags
LOGLEVEL="PROMPTS"
ALWAYS_YES=false

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--loglevel)
            if [[ ! ${LOG_LEVELS[$2]} ]]; then
                log_error "Invalid log level: $2"
            elif [[ "$2" == "SILENT" ]]; then
                ALWAYS_YES=true
            fi
            LOGLEVEL=$2
            shift 2
            ;;
        -y|--yes)
            ALWAYS_YES=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [flag]"
            echo "  -y, --yes         Automatically accepts every y/n prompt"
            echo "  -l, --loglevel    DEBUG, PROMPTS, INFO, SILENT (SILENT implicates -y)"
            echo "  -h, --help        This help"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Use -h or --help for options"
            exit 1
            ;;
    esac
done

# Print Description if not silent
if [[ "$LOGLEVEL" != "SILENT" ]]; then
    echo "$DESC"
fi

# Root check
log "DEBUG" "Checking if user is root"
if [[ $EUID -ne 0 ]]; then
    log_error "Script has to be run as root"
fi
log "DEBUG" "User is root"

# Poot partition space check
log "DEBUG" "Checking boot partition utilisation"
BOOT_SPACE_BEFORE=$(df -h /boot | awk 'NR==2 {print $3}' | tr -d 'M')
log "DEBUG" "Current boot partition utilisation (MiB): $BOOT_SPACE_BEFORE"



log "INFO" "Kernel Cleanup"

log "DEBUG" "Trying to find kernel"
KERNEL_NAME=""

log "DEBUG" "Checking for UEK"
KERNEL_COUNT_BEFORE=$(rpm -qa kernel-uek | wc -l)
log "DEBUG" "UEK Kernel Count: $KERNEL_COUNT_BEFORE"

if [[ $KERNEL_COUNT_BEFORE -le 0 ]]; then
    log "DEBUG" "UEK Kernel not found"
    
    log "DEBUG" "Checking for normal kernel"
    KERNEL_COUNT_BEFORE=$(rpm -qa kernel | wc -l)
    log "DEBUG" "Kernel Count: $KERNEL_COUNT_BEFORE"
    
    if [[ $KERNEL_COUNT_BEFORE -le 0 ]]; then
        log_error "No kernel found"
    fi
    
    KERNEL_NAME="kernel"
else
    KERNEL_NAME="kernel-uek"
fi
  
log "DEBUG" "Kernel name found: $KERNEL_NAME"
  
if [[ $KERNEL_COUNT_BEFORE -le 2 ]]; then
    log "INFO" "Only $KERNEL_COUNT_BEFORE kernels installed - nothing to remove"
else
    log "DEBUG" "Removing old kernels with DNF"
    
    confirm "Current kernels" "rpm -qa $KERNEL_NAME" "Kernels (and dependencies) to be removed" "dnf rq --installonly --latest-limit=-2 -q"
    log "DEBUG" "Starting removal with DNF"
    dnf rm -y $(dnf rq --installonly --latest-limit=-2 -q) 1>/dev/null
    log "DEBUG" "DNF finished"
    
    # Count kernels after cleanup
    KERNEL_COUNT_AFTER=$(rpm -qa $KERNEL_NAME | wc -l)
    KERNEL_REMOVED_COUNT=$((KERNEL_COUNT_BEFORE - KERNEL_COUNT_AFTER))
    
    log "INFO" "$KERNEL_REMOVED_COUNT kernel(s) removed ($KERNEL_COUNT_BEFORE → $KERNEL_COUNT_AFTER)"
fi



log "INFO" "Removing unnecessary dependencies for UEK"
if [[ $KERNEL_NAME == "kernel-uek" ]]; then
    log "DEBUG" "UEK detected, starting dependency removal confirmation"
    
    confirm "Showing unnecessary dependencies with DNF" "dnf --assumeno rm kernel"

    log "DEBUG" "Removal confirmed, starting DNF"
    dnf -y rm kernel 1>/dev/null
    log "INFO" "All unnecessary dependencies removed"
else
    log "INFO" "Kernel is not UEK - nothing to do"
fi



log "INFO" "Removing unnecessary rescue initramfs"
log "DEBUG" "Counting current amount"
INITRAMFS_RESCUE_COUNT_BEFORE=$(ls /boot/initramfs-0-rescue-* | wc -l)
log "DEBUG" "Rescue initramfs count: $INITRAMFS_RESCUE_COUNT_BEFORE"

if [[ $INITRAMFS_RESCUE_COUNT_BEFORE -le 0 ]]; then
    log_error "no rescue initramfs found"
elif [[ $INITRAMFS_RESCUE_COUNT_BEFORE -le 1 ]]; then
    log "INFO" "Only 1 rescue initramfs found - nothing to remove"
else 
    log "DEBUG" "Confirming rescue initramfs removal"
    confirm "Current rescueinitramfs" "ls -lt /boot/initramfs-0-rescue-*" "Rescure initramfs to be kept" "ls -t /boot/initramfs-0-rescue-* | head -n 1"  "Rescue initrams to be deleted" "ls -t /boot/initramfs-0-rescue-* | tail -n +2"
    
    log "DEBUG" "Removal confirmed, starting rm"
    ls -t /boot/initramfs-0-rescue-* | tail -n +2 | xargs rm
    log "DEBUG" "rm done"
    
    log "DEBUG" "Counting new amount"
    INITRAMFS_RESCUE_COUNT_AFTER=$(ls /boot/initramfs-0-rescue-* | wc -l)
    log "DEBUG" "Calculating difference"
    INITRAMFS_RESCUE_REMOVED_COUNT=$((INITRAMFS_RESCUE_COUNT_BEFORE - INITRAMFS_RESCUE_COUNT_AFTER))
    
    log "INFO" "$INITRAMFS_RESCUE_REMOVED_COUNT rescue initramfs removed ($INITRAMFS_RESCUE_COUNT_BEFORE → $INITRAMFS_RESCUE_COUNT_AFTER)"
fi



log "INFO" "Removing unnecessary initramfs"

log "DEBUG" "Counting current amount"
INITRAMFS_COUNT_BEFORE=$(find /boot -name "initramfs-*.img" ! -name "*rescue*" | wc -l)
log "DEBUG" "initramfs amount: $INITRAMFS_COUNT_BEFORE"

log "DEBUG" "Getting current kernel versions"
readarray -t kernels < <(rpm -qa $KERNEL_NAME | sed "s/^$KERNEL_NAME-//")
TO_DELETE=()
TO_KEEP=()

for initramfsfile in /boot/initramfs-*; do
    log "DEBUG" "Iteration for file: $initramfsfile"
    log "DEBUG" "Comparison 1: /boot/initramfs-${kernels[0]}"
    log "DEBUG" "Comparison 2: /boot/initramfs-${kernels[1]}"

    if [[ ! "$initramfsfile" =~ /boot/initramfs-${kernels[0]}* && ! "$initramfsfile" =~ /boot/initramfs-${kernels[1]}* && ! "$initramfsfile" =~ /boot/initramfs-0-* ]]; then
        TO_DELETE+=("$initramfsfile")
        log "DEBUG" "$initramfsfile didnt match with any kernel version and should be deleted"
       
    else
        TO_KEEP+=("$initramfsfile")
        log "DEBUG" "$initramfsfile matched a kernel version and should NOT be deleted"
        log "DEBUG" "-----------------------------------------"
    fi
done

if [[ ${#TO_DELETE[@]} == 0 ]]; then
    log "INFO" "No unnecessary initramfs found"
else
    log "DEBUG" "Confirming initramfs removal"
    confirm "Current initramfs" 'find /boot -name "initramfs-*.img" ! -name "*rescue*"' "Initramfs to be kept" 'printf "%s\n" "${TO_KEEP[@]}"' "Initramfs to be deleted" 'printf "%s\n" "${TO_DELETE[@]}"'

    log "DEBUG" "Removal confirmed, starting rm"
    rm "${TO_DELETE[@]}"
    log "DEBUG" "rm done"

    log "INFO" "All unnecessary initramfs removed"
fi




log "INFO" "Checking grub entries"
SAVED_ENTRY=$(grub2-editenv list | sed -n 's/^saved_entry=//p')
log "DEBUG" "SAVED_ENTRY: '$SAVED_ENTRY'"

GREP_RESULT=$(echo "$(grubby --info=ALL)" | grep "$SAVED_ENTRY" || true)
log "DEBUG" "Grep Result: $GREP_RESULT"

if [[ -n "$GREP_RESULT" ]]; then
    log "INFO" "Entry still exists - nothing to do"
else
    log "INFO" "Entry doesn't exist!"
    
    log "DEBUG" "Confirming new default entry"
    confirm "The following kernel will be set as default entry" "grubby --info=0"
    log "DEBUG" "New entry confirmed, starting grub2-set-default and grub2-mkconfig"
    
    grub2-set-default $(grubby --info=0 | sed -n 's/^id="\(.*\)"$/\1/p')
    grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null
fi

log "DEBUG" "Measuring new boot partition utilisation"
BOOT_SPACE_AFTER=$(df -h /boot | awk 'NR==2 {print $3}' | tr -d 'M')
log "DEBUG" "Current boot partition utilisation (MiB): $BOOT_SPACE_BEFORE"

log "PROMPTS" "/boot cleanup complete ($(($BOOT_SPACE_BEFORE-$BOOT_SPACE_AFTER))MiB saved)"