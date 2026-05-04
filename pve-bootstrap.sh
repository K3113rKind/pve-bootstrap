#!/bin/bash
# =============================================================================
# pve-bootstrap.sh
# Idempotentes Bootstrap-/Wartungs-Skript für Proxmox VE (Single-Node).
#
# Zwei Modi:
#   - Initial-Run: Marker fehlt -> einmalige Bestätigung, alle Module laufen
#   - Drift-Run:   Marker da    -> nur driftrelevante Module (neue CTs/VMs etc.)
#
# Aufruf:
#   ./pve-bootstrap.sh                  # Auto-Detect (initial vs. drift)
#   ./pve-bootstrap.sh --dry-run        # nur anzeigen, nichts ändern
#   ./pve-bootstrap.sh --force-initial  # Initial-Run erzwingen
#   ./pve-bootstrap.sh --skip=fail2ban,nag
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/var/lib/pve-bootstrap"
STATE_FILE="$STATE_DIR/initialized"

# ---------- Config laden -----------------------------------------------------
[[ -f "$SCRIPT_DIR/config.default.sh" ]] || { echo "config.default.sh fehlt"; exit 1; }
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.default.sh"

if [[ -f "$SCRIPT_DIR/config.local.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/config.local.sh"
  CONFIG_LOCAL_LOADED=true
else
  CONFIG_LOCAL_LOADED=false
fi

# ---------- Flags ------------------------------------------------------------
DRY_RUN=false
FORCE_INITIAL=false
SKIP_MODULES=""

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)        DRY_RUN=true ;;
    --force-initial)     FORCE_INITIAL=true ;;
    --skip=*)            SKIP_MODULES="${arg#*=}" ;;
    --help|-h)
      sed -n '2,15p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unbekannter Parameter: $arg"; exit 2 ;;
  esac
done

# ---------- Logging ----------------------------------------------------------
C_OK="\e[1;32m"; C_WARN="\e[1;33m"; C_INFO="\e[1;36m"; C_SKIP="\e[1;90m"
C_CHG="\e[1;35m"; C_ERR="\e[1;31m"; C_RST="\e[0m"

log()       { echo -e "${C_INFO}[INFO]${C_RST} $*"; }
log_ok()    { echo -e "${C_OK}[ OK ]${C_RST} $*"; }
log_skip()  { echo -e "${C_SKIP}[SKIP]${C_RST} $*"; }
log_warn()  { echo -e "${C_WARN}[WARN]${C_RST} $*"; }
log_chg()   { echo -e "${C_CHG}[CHG ]${C_RST} $*"; }
log_err()   { echo -e "${C_ERR}[ERR ]${C_RST} $*" >&2; }
section()   { echo; echo -e "${C_INFO}=== $* ===${C_RST}"; }

skip_module() { [[ ",$SKIP_MODULES," == *",$1,"* ]]; }

run_or_dry() {
  if $DRY_RUN; then
    log_chg "(dry-run) würde ausführen: $*"
    return 0
  fi
  "$@"
}

# ---------- Pre-flight -------------------------------------------------------
[[ $EUID -eq 0 ]] || { log_err "Muss als root laufen"; exit 1; }
[[ -d /etc/pve ]] || { log_err "Kein PVE-Host (/etc/pve fehlt)"; exit 1; }

PVE_VERSION=$(pveversion 2>/dev/null | head -1 | grep -oE 'pve-manager/[0-9.]+' | cut -d/ -f2)
DEB_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

# ---------- Mode decision ----------------------------------------------------
INITIAL_RUN=false
if $FORCE_INITIAL || [[ ! -f "$STATE_FILE" ]]; then
  INITIAL_RUN=true
fi

# ---------- Banner -----------------------------------------------------------
echo -e "${C_INFO}"
cat <<'EOF'
+------------------------------------------------------+
|              PVE-Bootstrap (Single-Node)             |
+------------------------------------------------------+
EOF
echo -e "${C_RST}"
log "PVE: ${PVE_VERSION:-unknown} | Debian: $DEB_CODENAME | Host: $(hostname)"
$CONFIG_LOCAL_LOADED && log "config.local.sh geladen" || log_warn "Keine config.local.sh - reine Defaults"
$DRY_RUN && log_warn "DRY-RUN aktiv - keine Änderungen werden geschrieben"

if $INITIAL_RUN; then
  echo
  log_warn "Initial-Run: alle Module werden ausgeführt."
  echo "  Folgende Aktionen werden durchlaufen:"
  echo "    1. APT-Repos (Enterprise raus, no-subscription rein)"
  echo "    2. Subscription-Nag entfernen (apt-Hook)"
  echo "    3. Postfix abschalten"
  echo "    4. Host-Tools installieren"
  echo "    5. fail2ban konfigurieren (sshd + proxmox)"
  echo "    6. NFS-Storages einbinden (falls in config gesetzt)"
  echo "    7. Ultimate Updater installieren"
  echo "    8. Ultimate Updater Config anpassen"
  echo "    9. Cronjob anlegen (Schedule: $CRON_SCHEDULE)"
  echo "   10. LXC-Bootstrap-Skript + Anwendung auf alle Debian/Ubuntu-LXCs"
  echo
  if ! $DRY_RUN; then
    read -p "$(echo -e "${C_CHG}[?]${C_RST} Initial-Bootstrap starten? [y/N]: ")" -r ans
    [[ "$ans" =~ ^[YyJj]$ ]] || { log "Abgebrochen"; exit 0; }
  fi
else
  log "Drift-Run: nur Module für neue CTs/VMs und Config-Drift werden geprüft."
fi

# =============================================================================
# Module
# =============================================================================

# --- Modul: APT-Repos (init only) -------------------------------------------
mod_repos() {
  $INITIAL_RUN || { log_skip "[repos] init-only, übersprungen im Drift-Modus"; return; }
  skip_module repos && { log_skip "[repos] via --skip übersprungen"; return; }
  section "APT-Repos"

  local ent="/etc/apt/sources.list.d/pve-enterprise.list"
  if [[ -f "$ent" ]] && grep -qE '^[[:space:]]*deb' "$ent"; then
    run_or_dry sed -i.bak 's/^[[:space:]]*deb/#deb/' "$ent"
    log_ok "Enterprise-Repo deaktiviert"
  else
    log_skip "Enterprise-Repo schon deaktiviert/fehlt"
  fi

  local ceph="/etc/apt/sources.list.d/ceph.list"
  if [[ -f "$ceph" ]] && grep -qE '^[[:space:]]*deb.*enterprise\.proxmox\.com' "$ceph"; then
    run_or_dry sed -i.bak 's|enterprise\.proxmox\.com/debian/ceph-\([a-z]*\) \([a-z]*\) enterprise|download.proxmox.com/debian/ceph-\1 \2 no-subscription|' "$ceph"
    log_ok "Ceph-Repo umgestellt"
  fi

  local nosub="/etc/apt/sources.list.d/pve-no-subscription.list"
  if ! grep -rqE '^[[:space:]]*deb.*pve-no-subscription' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    run_or_dry bash -c "echo 'deb http://download.proxmox.com/debian/pve $DEB_CODENAME pve-no-subscription' > '$nosub'"
    log_ok "no-subscription Repo eingetragen"
  else
    log_skip "no-subscription Repo bereits vorhanden"
  fi

  $DRY_RUN || apt-get update -qq && log_ok "apt update ok" || log_warn "apt update meldete Fehler"
}

# --- Modul: Nag (init only) -------------------------------------------------
mod_nag() {
  $INITIAL_RUN || { log_skip "[nag] init-only"; return; }
  skip_module nag && { log_skip "[nag] via --skip übersprungen"; return; }
  $ENABLE_NAG_REMOVAL || { log_skip "[nag] disabled in config"; return; }
  section "Subscription-Nag"

  local hook="/etc/apt/apt.conf.d/no-nag-script"
  if [[ -f "$hook" ]]; then
    log_skip "apt-Hook existiert bereits"
    return
  fi

  if $DRY_RUN; then
    log_chg "(dry-run) würde $hook anlegen + proxmox-widget-toolkit reinstall"
  else
    cat > "$hook" <<'HOOK'
DPkg::Post-Invoke {
  "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\\.js$'; if [ $? -eq 1 ]; then { echo 'Removing subscription nag'; sed -i '/.*data\\.status.*{/{s/\\!/\\!/;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi";
};
HOOK
    apt --reinstall install proxmox-widget-toolkit -y >/dev/null 2>&1
    log_ok "Nag-Hook installiert + sofort angewendet"
    log_warn "Browser-Cache leeren (Strg+F5)"
  fi
}

# --- Modul: Postfix (init only) ---------------------------------------------
mod_postfix() {
  $INITIAL_RUN || { log_skip "[postfix] init-only"; return; }
  skip_module postfix && { log_skip "[postfix] via --skip übersprungen"; return; }
  $ENABLE_POSTFIX_DISABLE || { log_skip "[postfix] disabled in config"; return; }
  section "Postfix"

  if systemctl is-active postfix >/dev/null 2>&1; then
    run_or_dry systemctl stop postfix
    run_or_dry systemctl disable postfix
    log_ok "Postfix gestoppt + disabled"
  else
    log_skip "Postfix läuft nicht"
  fi
}

# --- Modul: Host-Tools (init only) ------------------------------------------
mod_tools() {
  $INITIAL_RUN || { log_skip "[tools] init-only"; return; }
  skip_module tools && { log_skip "[tools] via --skip übersprungen"; return; }
  section "Host-Tools"

  local missing=""
  for pkg in $HOST_TOOLS; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=" $pkg"
  done

  if [[ -z "$missing" ]]; then
    log_skip "Alle Tools bereits installiert"
    return
  fi
  log "Fehlend:$missing"
  run_or_dry apt-get install -y $missing
  $DRY_RUN || log_ok "Tools installiert"
}

# --- Modul: fail2ban (init only) --------------------------------------------
mod_fail2ban() {
  $INITIAL_RUN || { log_skip "[fail2ban] init-only"; return; }
  skip_module fail2ban && { log_skip "[fail2ban] via --skip übersprungen"; return; }
  $ENABLE_FAIL2BAN_PROXMOX_JAIL || { log_skip "[fail2ban] disabled in config"; return; }
  section "fail2ban"

  command -v fail2ban-client >/dev/null 2>&1 || { log_warn "fail2ban nicht installiert"; return; }

  local proxmox_filter="/etc/fail2ban/filter.d/proxmox.conf"
  if [[ -f "$proxmox_filter" ]]; then
    log_skip "Proxmox-Filter existiert"
  elif $DRY_RUN; then
    log_chg "(dry-run) würde $proxmox_filter anlegen"
  else
    cat > "$proxmox_filter" <<'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
    log_ok "Proxmox-Filter angelegt"
  fi

  local jail="/etc/fail2ban/jail.local"
  if [[ -f "$jail" ]] && grep -q '\[proxmox\]' "$jail"; then
    log_skip "jail.local enthält bereits [proxmox]"
  elif $DRY_RUN; then
    log_chg "(dry-run) würde $jail mit [sshd]+[proxmox] schreiben + fail2ban restart"
  else
    [[ -f "$jail" ]] && cp "$jail" "${jail}.bak.$(date +%Y%m%d-%H%M%S)"
    cat > "$jail" <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh

[proxmox]
enabled  = true
port     = https,http,8006
filter   = proxmox
logpath  = /var/log/daemon.log
maxretry = 3
bantime  = 1h
EOF
    systemctl restart fail2ban
    log_ok "jail.local geschrieben + fail2ban restart"
  fi
}

# --- Modul: NFS (init only) -------------------------------------------------
mod_nfs() {
  $INITIAL_RUN || { log_skip "[nfs] init-only"; return; }
  skip_module nfs && { log_skip "[nfs] via --skip übersprungen"; return; }
  section "NFS-Storages"

  if [[ -z "${NFS_SERVER:-}" ]] || [[ ${#NFS_STORAGES[@]} -eq 0 ]]; then
    log_skip "Keine NFS-Storages in config gesetzt"
    return
  fi

  local cfg="/etc/pve/storage.cfg"
  for entry in "${NFS_STORAGES[@]}"; do
    local name="${entry%%|*}"; local rest="${entry#*|}"
    local export="${rest%%|*}"; local content="${rest#*|}"

    if grep -q "^nfs: $name$" "$cfg"; then
      log_skip "Storage '$name' bereits konfiguriert"
      continue
    fi
    run_or_dry pvesm add nfs "$name" \
      --server "$NFS_SERVER" --export "$export" \
      --content "$content" --prune-backups "keep-all=1"
    $DRY_RUN || log_ok "Storage '$name' hinzugefügt"
  done
}

# --- Modul: Ultimate Updater Install (init only) ----------------------------
mod_uu_install() {
  $INITIAL_RUN || { log_skip "[uu] init-only"; return; }
  skip_module uu && { log_skip "[uu] via --skip übersprungen"; return; }
  section "Ultimate Updater"

  if [[ -f /etc/ultimate-updater/update.sh ]]; then
    log_skip "Ultimate Updater bereits installiert"
    return
  fi

  if $DRY_RUN; then
    log_chg "(dry-run) würde Installer ausführen: $UU_INSTALLER_URL"
  else
    bash <(curl -s "$UU_INSTALLER_URL")
    log_ok "Ultimate Updater installiert"
  fi
}

# --- Modul: Ultimate Updater Config (drift-aware) ---------------------------
mod_uu_config() {
  skip_module uu_config && { log_skip "[uu_config] via --skip übersprungen"; return; }
  section "Ultimate Updater Config"

  local conf="/etc/ultimate-updater/update.conf"
  [[ -f "$conf" ]] || { log_warn "$conf fehlt"; return; }

  declare -A wanted=(
    ["STOPPED_CONTAINER"]="false"
    ["STOPPED_VM"]="false"
    ["ONLY"]=""
  )

  local changes=0
  for key in "${!wanted[@]}"; do
    local target="${wanted[$key]}"
    local current
    current=$(awk -F'"' "/^${key}=/ {print \$2; exit}" "$conf")
    if [[ "$current" == "$target" ]]; then
      log_skip "$key bereits = \"$target\""
    elif $INITIAL_RUN; then
      run_or_dry sed -i "s/^${key}=\".*\"/${key}=\"${target}\"/" "$conf"
      $DRY_RUN || log_ok "$key gesetzt auf \"$target\""
      changes=$((changes+1))
    else
      log_warn "Drift in $key: aktuell=\"$current\" soll=\"$target\" (manuell ändern oder --force-initial)"
    fi
  done
  [[ $changes -gt 0 && ! -f "${conf}.bak.bootstrap" ]] && cp "$conf" "${conf}.bak.bootstrap"
}

# --- Modul: Cronjob (drift-aware) -------------------------------------------
mod_cron() {
  skip_module cron && { log_skip "[cron] via --skip übersprungen"; return; }
  section "Cronjob"

  local existing
  existing=$(crontab -l 2>/dev/null || true)
  local our_line="$CRON_SCHEDULE $CRON_CMD $CRON_MARKER"

  if echo "$existing" | grep -qF "$CRON_MARKER"; then
    local current_line
    current_line=$(echo "$existing" | grep -F "$CRON_MARKER")
    if [[ "$current_line" == "$our_line" ]]; then
      log_skip "Cronjob existiert mit korrektem Schedule"
      return
    fi
    if $INITIAL_RUN; then
      if ! $DRY_RUN; then
        (echo "$existing" | grep -vF "$CRON_MARKER"; echo "$our_line") | crontab -
      fi
      log_ok "Cronjob aktualisiert"
    else
      log_warn "Drift im Cronjob: aktuell '$current_line' soll '$our_line' (manuell oder --force-initial)"
    fi
    return
  fi

  if echo "$existing" | grep -q '/etc/ultimate-updater/update.sh'; then
    log_warn "Manueller Cron-Eintrag für update.sh vorhanden - wird nicht überschrieben"
    return
  fi

  if $DRY_RUN; then
    log_chg "(dry-run) würde Cron eintragen: $our_line"
  else
    (echo "$existing"; echo "$our_line") | crontab -
    log_ok "Cron eingetragen ($CRON_SCHEDULE)"
  fi
}

# --- Modul: LXC-Bootstrap (drift-aware, läuft auch im Drift-Modus) ----------
mod_lxc_bootstrap() {
  skip_module lxc && { log_skip "[lxc] via --skip übersprungen"; return; }
  section "LXC-Bootstrap"

  local helper="/usr/local/bin/lxc-bootstrap.sh"
  local desired_content
  desired_content=$(cat <<EOF
#!/bin/bash
# Auto-generiert von pve-bootstrap.sh - nicht von Hand editieren
BASE_PKGS="$LXC_BASE_PKGS"
for CT in \$(pct list | tail -n +2 | awk '{print \$1}'); do
  STATUS=\$(pct status "\$CT")
  OS=\$(pct config "\$CT" | awk '/^ostype/ {print \$2}')
  [[ "\$STATUS" != "status: running" ]] && continue
  [[ "\$OS" =~ debian|ubuntu ]] || continue
  echo "==> CT \$CT (\$OS)"
  pct exec "\$CT" -- bash -c "apt-get update -qq && apt-get install -y \$BASE_PKGS" 2>&1 | tail -5
done
EOF
)

  if [[ -f "$helper" ]] && [[ "$(cat "$helper")" == "$desired_content" ]]; then
    log_skip "$helper aktuell"
  elif $DRY_RUN; then
    log_chg "(dry-run) würde $helper schreiben"
  else
    echo "$desired_content" > "$helper"
    chmod +x "$helper"
    log_ok "$helper geschrieben"
  fi

  if $DRY_RUN; then
    log_chg "(dry-run) würde $helper jetzt ausführen"
  else
    "$helper"
    log_ok "LXC-Bootstrap durchgelaufen"
  fi
}

# =============================================================================
# Ausführung
# =============================================================================
mod_repos
mod_nag
mod_postfix
mod_tools
mod_fail2ban
mod_nfs
mod_uu_install
mod_uu_config
mod_cron
mod_lxc_bootstrap

# State setzen
if $INITIAL_RUN && ! $DRY_RUN; then
  mkdir -p "$STATE_DIR"
  date -Iseconds > "$STATE_FILE"
  log_ok "State-Marker gesetzt: $STATE_FILE"
fi

section "Fertig"
$DRY_RUN && log_warn "DRY-RUN war aktiv - nichts wurde geändert"
log_ok "Bootstrap-Lauf abgeschlossen"
