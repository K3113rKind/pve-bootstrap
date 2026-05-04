#!/bin/bash
# =============================================================================
# config.default.sh
# Generische Defaults.
# Nicht hier editieren, sondern in config.local.sh überschreiben!
# =============================================================================

# --- Schedule -----------------------------------------------------------------
# Cron-Format. Default: Samstag 03:00 Uhr
CRON_SCHEDULE="0 3 * * 6"
CRON_CMD="/etc/ultimate-updater/update.sh -s >> /var/log/ultimate-updater-cron.log 2>&1"
CRON_MARKER="# pve-bootstrap:ultimate-updater"

# --- Pakete für den PVE-Host --------------------------------------------------
HOST_TOOLS="fail2ban iptraf-ng ncdu git ethtool neofetch smartmontools \
            curl wget gnupg ca-certificates htop nano vim less rsync"

# --- Pakete für Debian/Ubuntu LXCs --------------------------------------------
LXC_BASE_PKGS="sudo locales bash-completion curl wget gnupg ca-certificates \
               htop net-tools iputils-ping dnsutils rsync"

# --- Feature-Toggles ----------------------------------------------------------
ENABLE_NAG_REMOVAL=true
ENABLE_POSTFIX_DISABLE=true
ENABLE_FAIL2BAN_PROXMOX_JAIL=true

# --- NFS-Storages -------------------------------------------------------------
# Leer lassen, um das NFS-Modul zu überspringen.
# In config.local.sh überschreiben mit echten Werten.
#
# Format pro Eintrag: "Name|Export-Pfad|Content-Types"
# Content-Types: backup, iso, vztmpl, rootdir, images, snippets (kommasepariert)
NFS_SERVER=""
NFS_STORAGES=()

# --- Externe Quellen ----------------------------------------------------------
UU_INSTALLER_URL="https://raw.githubusercontent.com/BassT23/Proxmox/master/install.sh"
