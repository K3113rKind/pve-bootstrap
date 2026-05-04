#!/bin/bash
# =============================================================================
# config.local.sh
# Persönliche Einstellungen — wird durch .gitignore von Git ausgeschlossen.
# NIE auf GitHub committen!
# =============================================================================

# --- NFS-Storages (Synology DS im Heimnetz) -----------------------------------
NFS_SERVER="192.168.0.4"
NFS_STORAGES=(
  "SynologyTemplate|/volume1/ProxmoxTemplates|iso,vztmpl"
  "SynologyBackup|/volume1/ProxmoxBackup|backup"
)

# --- Schedule (Default Sa 03:00 reicht) ---------------------------------------
# CRON_SCHEDULE="0 3 * * 6"

# --- Optional: zusätzliche Tools ----------------------------------------------
# HOST_TOOLS="$HOST_TOOLS tmux ripgrep"
