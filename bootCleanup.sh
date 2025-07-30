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

# Logging functions
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][ERROR]: $1" >&2  
    exit 1
}

log_info() {
    if [[ "$SILENT" != true ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')][INFO]: $1"
    fi
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')][DEBUG]: $1"
    fi
}

# Function for y/n confirmation
confirm() {
    if [[ "$ALWAYS-YES" != true ]]; then
        read -p "Continue? [y/N]: " response
    
        if [[ "${response,,}" != "y" && "${response,,}" != "yes" ]]; then
            exit 1
        fi
    fi
}

# Default flags
SILENT=false
VERBOSE=false
ALWAYS_YES=false

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--silent)
            SILENT=true
            ALWAYS_YES=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -y|--yes)
            ALWAYS_YES=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [flag]"
            echo "  -y, --yes         Automatically accepts every y/n prompt"
            echo "  -s, --silent      Only show error messages (implicates -y)"
            echo "  -v, --verbose     All messages including debug"
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

# Check mutually exclusive flags
if [[ "$SILENT" == true && "$VERBOSE" == true ]]; then
    log_error "-v/--verbose and -s/--silent are mutually exclusive"
fi

# Print Description if not silent
if [[ "$SILENT" != true ]]; then
    echo "$DESC"
fi

if [[ $EUID -ne 0 ]]; then
    log_error "Script has to be run as root"
fi
log_debug "User is root"



log_info "Kernel Cleanup"

log_debug "Trying to find kernel"
KERNEL_NAME=""

KERNEL_COUNT_BEFORE=$(rpm -qa kernel-uek | wc -l)
log_debug "UEK Kernel Count: $KERNEL_COUNT_BEFORE"

if [[ $KERNEL_COUNT_BEFORE -le 0 ]]; then
    log_debug "UEK Kernel not found"
    
    KERNEL_COUNT_BEFORE=$(rpm -qa kernel | wc -l)
    log_debug "Kernel Count: $KERNEL_COUNT_BEFORE"
    
    if [[ $KERNEL_COUNT_BEFORE -le 0 ]]; then
        log_debug "No kernel found"
    fi
    
    KERNEL_NAME="kernel"
else
    KERNEL_NAME="kernel-uek"
fi
  
log_debug "Kernel name: $KERNEL_NAME"
  
if [[ $KERNEL_COUNT_BEFORE -le 2 ]]; then
    log_info "Only $KERNEL_COUNT_BEFORE kernels installed - Nothing to remove"
else
    log_debug "Removing old kernels with DNF"
    if [[ "$ALWAYS_YES" == true ]]; then
        if [[ "$VERBOSE" == true ]]; then
            dnf rm -y $(dnf rq --installonly --latest-limit=-2 -q)
        else
            dnf rm -y $(dnf rq --installonly --latest-limit=-2 -q) 1>/dev/null
        fi
    else
        echo "Current Kernels:"
        log_debug "Showing kernels with name $KERNEL_NAME"
        rpm -qa $KERNEL_NAME
        echo ""
        
        if [[ "$VERBOSE" == true ]]; then
            dnf -v remove $(dnf rq --installonly --latest-limit=-2 -q)
        else
            dnf remove $(dnf rq --installonly --latest-limit=-2 -q)
        fi
    fi
    
    # Count kernels after cleanup
    KERNEL_COUNT_AFTER=$(rpm -qa $KERNEL_NAME | wc -l)
    KERNEL_REMOVED_COUNT=$((KERNEL_COUNT_BEFORE - KERNEL_COUNT_AFTER))
    
    log_debug "Checke ob DNF funktioniert hat"
    if [[ $KERNEL_REMOVED_COUNT -gt 0 ]]; then
        log_info "$KERNEL_REMOVED_COUNT kernels removed ($KERNEL_COUNT_BEFORE → $KERNEL_COUNT_AFTER)"
    else
        log_error "dnf ran successfully but no kernels were removed"
    fi
fi



log_info "Remove unnecessary dependencies"
if [[ $KERNEL_NAME == "kernel-uek" ]]; then
    if [[ "$ALWAYS_YES" != true ]]; then
        echo ""
        echo "This system uses uek so some dependencies can be removed"
        echo ""
        if [[ "$VERBOSE" == true ]]; then
            dnf -v rm kernel
        else
            dnf rm kernel
        fi
    else 
        log_debug "Removing unnecessary dependencies with dnf"
        if [[ "$VERBOSE" == true ]]; then
            dnf -vy rm kernel 1>/dev/null
        else
            dnf -y rm kernel 1>/dev/null
        fi
    fi
fi
log_info "All unnecessary dependencies have been removed"



log_info "Remove unnecessary rescue initramfs"
INITRAMFS_RESCUE_COUNT_BEFORE=$(ls /boot/initramfs-0-rescue-* | wc -l)
log_debug "Rescue initramfs: $INITRAMFS_RESCUE_COUNT_BEFORE"

if [[ $INITRAMFS_RESCUE_COUNT_BEFORE -le 0 ]]; then
    log_error "no rescue initramfs found"
elif [[ $INITRAMFS_RESCUE_COUNT_BEFORE -le 1 ]]; then
    log_info "Only 1 rescue initramfs found - nothing to remove"
else 
    log_debug "Removing old rescue initramfs"
    if [[ "$ALWAYS_YES" != true ]]; then
        echo ""
        echo "Current rescue initrams:"
        ls -lt /boot/initramfs-0-rescue-*
        
        echo ""
        echo "Rescue initrams to be deleted:"
        ls -t /boot/initramfs-0-rescue-* | tail -n +2
        
        echo ""
        confirm
    fi
        
    if [[ "$VERBOSE" == true ]]; then
        ls -t /boot/initramfs-0-rescue-* | tail -n +2 | xargs rm -v
    else
        ls -t /boot/initramfs-0-rescue-* | tail -n +2 | xargs rm
    fi
    
    INITRAMFS_RESCUE_COUNT_AFTER=$(ls /boot/initramfs-0-rescue-* | wc -l)
    INITRAMFS_RESCUE_REMOVED_COUNT=$((INITRAMFS_RESCUE_COUNT_BEFORE - INITRAMFS_RESCUE_COUNT_AFTER))
    
    log_debug "Checking if command worked"
    if [[ $INITRAMFS_RESCUE_REMOVED_COUNT -gt 0 ]]; then
        log_info "$INITRAMFS_RESCUE_REMOVED_COUNT rescue initramfs removed ($INITRAMFS_RESCUE_COUNT_BEFORE → $INITRAMFS_RESCUE_COUNT_AFTER)"
    else
        log_error "Command ran but no initramfs removed"
    fi
fi



log_info "Remove unnecessary initramfs"
INITRAMFS_COUNT_BEFORE=$(find /boot -name "initramfs-*.img" ! -name "*rescue*" | wc -l)
log_debug "initramfs: $INITRAMFS_COUNT_BEFORE"

readarray -t kernels < <(rpm -qa $KERNEL_NAME | sed "s/^$KERNEL_NAME-//")
TO_DELETE=()

for initramfsfile in /boot/initramfs-*; do
    log_debug "Iteration for: $initramfsfile"
    log_debug "Comparison 1: /boot/initramfs-${kernels[0]}"
    log_debug "Comparison 2: /boot/initramfs-${kernels[1]}"

    if [[ ! "$initramfsfile" =~ /boot/initramfs-${kernels[0]}* && ! "$initramfsfile" =~ /boot/initramfs-${kernels[1]}* && ! "$initramfsfile" =~ /boot/initramfs-0-* ]]; then
        log_debug "$initramfsfile should be deleted"
        TO_DELETE+=("$initramfsfile")
    else
        log_debug "$initramfsfile should NOT be deleted"
        log_debug "-----------------------------------------"
    fi
done

if [[ ${#TO_DELETE[@]} == 0 ]]; then
    log_info "No unnecessary initramfs found"
elif [[ "$ALWAYS_YES" != true ]]; then
    echo ""
    echo "Current Initramfs:"
    find /boot -name "initramfs-*.img" ! -name "*rescue*"
    
    echo ""
    echo "(${#TO_DELETE[@]}) initramfs to be deleted:"
    printf "%s\n" "${TO_DELETE[@]}"
    
    echo ""
    confirm
fi

for file in "${TO_DELETE[@]}"; do
    if [[ "$VERBOSE" == true ]]; then
        rm -v $file
    else
        rm $file
    fi
done

if [[ ${#TO_DELETE[@]} != 0 ]]; then
    log_info "All unnecessary initramfs removed"
fi



log_info "Check grub entries"
SAVED_ENTRY=$(grub2-editenv list | sed -n 's/^saved_entry=//p')
log_debug "SAVED_ENTRY: '$SAVED_ENTRY'"

GREP_RESULT=$(echo "$(grubby --info=ALL)" | grep "$SAVED_ENTRY" || true)
log_debug "Grep Result: $GREP_RESULT"
if [[ -n "$GREP_RESULT" ]]; then
    log_info "Entry still exists"
else
    log_info "Entry doesn't exist!"
    
    if [[ "$ALWAYS_YES" != true ]]; then
        echo ""
        echo "The following kernel will be set as default entry:"
        echo ""
        grubby --info=0
        echo ""
        confirm
    fi
    
    grub2-set-default $(grubby --info=0 | sed -n 's/^id="\(.*\)"$/\1/p')
    if [[ "$SILENT" == true ]]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
fi

log_info "/boot cleanup complete"