#!/bin/bash

DESC=$(cat <<'EOF'
#####################################################################
# /boot cleanup                                                     #
# Author: Nicolas Wagener (XNLXBDT)                                 #
#                                                                   #
# Ein Script das /boot aufräumt mit den folgenden Schritten:        #
# 1) Löscht alle alten kernels, bis auf 2                           #
# 1) Löscht unbenötigte kernel dependencies                         #
# 2) Löscht alte initramfs-rescue                                   #
# 2) Löscht alte initramfs                                          #
# 3) Checkt ob das neueste Kernel noch in den Grub Einträgen ist    #
# 4) Wenn nicht, dann wird das neueste verfügbare Kernel gewählt    #
#####################################################################
29.07.2025: Script erstellt
30.07.2025: Fix für kernel und kernel-uek

---------------------------------------------------------------------
EOF
)

set -eo pipefail

# Logging Funktionen
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

# Funktion für y/n confirmation
confirm() {
    if [[ "$ALWAYS-YES" != true ]]; then
        read -p "Fortfahren? [y/N]: " response
    
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
            echo "  -y, --yes         Sagt bei jedem Prompt automatisch ja"
            echo "  -s, --silent      Nur Error-Messages (impliziert -y)"
            echo "  -v, --verbose     Alle Messages inkl. Debug"
            echo "  -h, --help        Diese Hilfe"
            exit 0
            ;;
        *)
            echo "ERROR: Unbekannte Option: $1"
            echo "Nutze -h für Hilfe"
            exit 1
            ;;
    esac
done

# Check mutually exclusive flags
if [[ "$SILENT" == true && "$VERBOSE" == true ]]; then
    log_error "-v/--verbose und -s/--silent schliessen sich gegenseitig aus"
fi

# Print Description if not silent
if [[ "$SILENT" != true ]]; then
    echo "$DESC"
fi

if [[ $EUID -ne 0 ]]; then
    log_error "Script muss als root ausgeführt werden"
fi
log_debug "User ist root"



log_info "Kernel Cleanup"

log_debug "Versuche, Kernel zu finden"
KERNEL_NAME=""

KERNEL_COUNT_BEFORE=$(rpm -qa kernel-uek | wc -l)
log_debug "UEK Kernel Count: $KERNEL_COUNT_BEFORE"

if [[ $KERNEL_COUNT_BEFORE -le 0 ]]; then
    log_debug "UEK Kernel nicht gefunden"
    
    KERNEL_COUNT_BEFORE=$(rpm -qa kernel | wc -l)
    log_debug "Kernel Count: $KERNEL_COUNT_BEFORE"
    
    if [[ $KERNEL_COUNT_BEFORE -le 0 ]]; then
        log_debug "Es wurde kein Kernel gefunden"
    fi
    
    KERNEL_NAME="kernel"
else
    KERNEL_NAME="kernel-uek"
fi
  
log_debug "Kernel Name: $KERNEL_NAME"
  
if [[ $KERNEL_COUNT_BEFORE -le 2 ]]; then
    log_info "Nur $KERNEL_COUNT_BEFORE Kernel installiert – nichts zu entfernen"
else
    log_debug "Entferne alte Kernel mit DNF"
    if [[ "$ALWAYS_YES" == true ]]; then
        if [[ "$VERBOSE" == true ]]; then
            dnf rm -y $(dnf rq --installonly --latest-limit=-2 -q)
        else
            dnf rm -y $(dnf rq --installonly --latest-limit=-2 -q) 1>/dev/null
        fi
    else
        echo "Momentane Kernels:"
        log_debug "Showing kernels with name $KERNEL_NAME"
        rpm -qa $KERNEL_NAME
        echo ""
        
        if [[ "$VERBOSE" == true ]]; then
            dnf -v remove $(dnf rq --installonly --latest-limit=-2 -q)
        else
            dnf remove $(dnf rq --installonly --latest-limit=-2 -q)
        fi
    fi
    
    # Zähle Kernel nach dem Cleanup
    KERNEL_COUNT_AFTER=$(rpm -qa $KERNEL_NAME | wc -l)
    KERNEL_REMOVED_COUNT=$((KERNEL_COUNT_BEFORE - KERNEL_COUNT_AFTER))
    
    log_debug "Checke ob DNF funktioniert hat"
    if [[ $KERNEL_REMOVED_COUNT -gt 0 ]]; then
        log_info "$KERNEL_REMOVED_COUNT Kernel wurden erfolgreich entfernt ($KERNEL_COUNT_BEFORE → $KERNEL_COUNT_AFTER)"
    else
        log_error "DNF lief durch, aber keine Kernel entfernt"
    fi
fi



log_info "Lösche unbenötigte kernel dependencies"
if [[ $KERNEL_NAME == "kernel-uek" ]]; then
    if [[ "$ALWAYS_YES" != true ]]; then
        echo ""
        echo "Da dieses System das UEK hat, können manche Dependencies für das normale Kernel gelöscht werden"
        echo ""
        if [[ "$VERBOSE" == true ]]; then
            dnf -v rm kernel
        else
            dnf rm kernel
        fi
    else 
        log_debug "Lösche unbenötigte kernel dependencies mit dnf"
        if [[ "$VERBOSE" == true ]]; then
            dnf -vy rm kernel 1>/dev/null
        else
            dnf -y rm kernel 1>/dev/null
        fi
    fi
fi
log_info "Alle unbenötigten kernel dependencies gelöscht"



log_info "Lösche überflüssige rescue initramfs"
INITRAMFS_RESCUE_COUNT_BEFORE=$(ls /boot/initramfs-0-rescue-* | wc -l)
log_debug "Rescue initramfs: $INITRAMFS_RESCUE_COUNT_BEFORE"

if [[ $INITRAMFS_RESCUE_COUNT_BEFORE -le 0 ]]; then
    log_error "Keine Resuce initramfs gefunden"
elif [[ $INITRAMFS_RESCUE_COUNT_BEFORE -le 1 ]]; then
    log_info "Nur 1 rescue initramfs vorhanden - nichts zu entfernen"
else 
    log_debug "Alte rescue initramfs werden gelöscht"
    if [[ "$ALWAYS_YES" != true ]]; then
        echo ""
        echo "Momentante rescue initrams:"
        ls -lt /boot/initramfs-0-rescue-*
        
        echo ""
        echo "Zu löschende rescue initrams:"
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
    
    log_debug "Checke ob Kommando funktioniert hat"
    if [[ $INITRAMFS_RESCUE_REMOVED_COUNT -gt 0 ]]; then
        log_info "$INITRAMFS_RESCUE_REMOVED_COUNT Rescue initramfs wurden erfolgreich entfernt ($INITRAMFS_RESCUE_COUNT_BEFORE → $INITRAMFS_RESCUE_COUNT_AFTER)"
    else
        log_error "Kommando lief durch, aber keine rescue initramfs entfernt"
    fi
fi



log_info "Lösche überflüssige initramfs"
INITRAMFS_COUNT_BEFORE=$(find /boot -name "initramfs-*.img" ! -name "*rescue*" | wc -l)
log_debug "initramfs: $INITRAMFS_COUNT_BEFORE"

readarray -t kernels < <(rpm -qa $KERNEL_NAME | sed "s/^$KERNEL_NAME-//")
TO_DELETE=()

for initramfsfile in /boot/initramfs-*; do
    log_debug "Iteration für: $initramfsfile"
    log_debug "Vegleich mit: /boot/initramfs-${kernels[0]}"
    log_debug "Vegleich 2 mit: /boot/initramfs-${kernels[1]}"

    if [[ ! "$initramfsfile" =~ /boot/initramfs-${kernels[0]}* && ! "$initramfsfile" =~ /boot/initramfs-${kernels[1]}* && ! "$initramfsfile" =~ /boot/initramfs-0-* ]]; then
        log_debug "$initramfsfile soll gelöscht werden"
        TO_DELETE+=("$initramfsfile")
    else
        log_debug "$initramfsfile soll NICHT gelöscht werden"
        log_debug "-----------------------------------------"
    fi
done

if [[ ${#TO_DELETE[@]} == 0 ]]; then
    log_info "keine überflüssigen initramfs gefunden"
elif [[ "$ALWAYS_YES" != true ]]; then
    echo ""
    echo "Momentane Initramfs:"
    find /boot -name "initramfs-*.img" ! -name "*rescue*"
    
    echo ""
    echo "Zu löschende (${#TO_DELETE[@]} initramfs):"
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
    log_info "Alle überflüssigen initramfs gelöscht"
fi



log_info "Checke Grub Entries"
SAVED_ENTRY=$(grub2-editenv list | sed -n 's/^saved_entry=//p')
log_debug "SAVED_ENTRY: '$SAVED_ENTRY'"

GREP_RESULT=$(echo "$(grubby --info=ALL)" | grep "$SAVED_ENTRY" || true)
log_debug "Grep Exit code: $GREP_RESULT"
if [[ -n "$GREP_RESULT" ]]; then
    log_info "Entry existiert noch"
else
    log_info "Entry existiert nicht!"
    
    if [[ "$ALWAYS_YES" != true ]]; then
        echo ""
        echo "Das folgende Kernel wird als Default Entry gesetzt:"
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

log_info "/boot cleanup abgeschlossen"