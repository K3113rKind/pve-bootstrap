# pve-bootstrap

Idempotentes Bootstrap- und Wartungs-Skript für Proxmox VE Hosts (Single-Node).

Setzt einen frisch installierten PVE-Server in einem Rutsch auf produktiven Stand und kann anschließend regelmäßig wiederholt werden, um neue LXCs/VMs mit Standardpaketen zu versorgen.

**Getestet auf:** PVE 8.4 (Debian Bookworm) und PVE 9.1 (Debian Trixie)

## Was es tut

**Beim Erstaufruf** (Initial-Run, einmalige Bestätigung):

1. APT-Repos sauber setzen — Enterprise raus, no-subscription rein, Ceph umstellen
2. Subscription-Nag-Popup entfernen via apt-Hook (überlebt Updates)
3. Postfix abschalten
4. Host-Tools installieren (fail2ban, iptraf-ng, ncdu, smartmontools, …)
5. fail2ban konfigurieren mit `[sshd]` und `[proxmox]` Jail
6. NFS-Storages einbinden (optional, via `config.local.sh`)
7. [Ultimate Updater](https://github.com/BassT23/Proxmox) installieren
8. `update.conf` anpassen (gestoppte Container/VMs in Ruhe lassen, kein Tag-Filter)
9. Cronjob anlegen (Default: Samstag 03:00, headless Update-Lauf)
10. LXC-Bootstrap-Skript anlegen + Standardpakete in alle laufenden Debian/Ubuntu-Container
11. Globalen Befehl `pve-bootstrap` via Symlink in `/usr/local/bin/` anlegen

**Bei Folge-Aufrufen** (Drift-Run, ohne Prompts):

- LXC-Bootstrap auf neue Container anwenden
- Cronjob-Drift erkennen
- Ultimate-Updater-Config-Drift erkennen
- Init-only-Module werden übersprungen

## Voraussetzungen

- Proxmox VE 8.4+ oder 9.x (Debian Bookworm oder Trixie)
- Single-Node-Setup (für Cluster muss das Cron- und LXC-Modul angepasst werden)
- Root-Zugriff auf den PVE-Host
- Internetzugang

## Schnellstart

```bash
# Repo auf den PVE-Host klonen
git clone https://github.com/<USER>/pve-bootstrap.git
cd pve-bootstrap

# Lokale Config anlegen (NFS-Server, eigene Werte)
cp config.local.sh.example config.local.sh
nano config.local.sh

# Erstmal trocken laufen lassen
./pve-bootstrap.sh --dry-run

# Echt ausführen (einmalige Bestätigung, dann läuft alles durch)
./pve-bootstrap.sh
```

Nach dem ersten Lauf ist `pve-bootstrap` global verfügbar:

```bash
pve-bootstrap           # Drift-Run (neue CTs versorgen, Config prüfen)
pve-bootstrap --dry-run
```

## Aufrufoptionen

```bash
pve-bootstrap                        # Auto-Detect (initial vs. drift)
pve-bootstrap --dry-run              # Nur anzeigen, nichts ändern
pve-bootstrap --force-initial        # Initial-Run erzwingen
pve-bootstrap --skip=fail2ban,nag    # Module gezielt überspringen
pve-bootstrap --help
```

## Konfiguration

Zwei Dateien:

- `config.default.sh` — committed, generische Defaults, **nicht editieren**
- `config.local.sh` — gitignored, hier eigene Werte überschreiben

Beispiel `config.local.sh`:

```bash
NFS_SERVER="192.168.0.4"
NFS_STORAGES=(
  "SynologyTemplate|/volume1/ProxmoxTemplates|iso,vztmpl"
  "SynologyBackup|/volume1/ProxmoxBackup|backup"
)

CRON_SCHEDULE="0 4 * * 0"   # Sonntag 04:00 statt Samstag
```

## LXC-Bootstrap: Container ausschließen

Container mit inkompatiblen Paketsystemen (z.B. Yunohost mit `sudo-ldap`) können vom LXC-Bootstrap ausgenommen werden via PVE-Tag:

```bash
pct set 150 --tags no-bootstrap
pct set 151 --tags no-bootstrap
```

Der LXC-Bootstrap überspringt Container mit diesem Tag automatisch.

## State-Marker

Nach dem ersten erfolgreichen Lauf wird `/var/lib/pve-bootstrap/initialized` angelegt. Solange diese Datei existiert, läuft das Skript im Drift-Modus.

```bash
# Marker löschen → nächster Lauf ist wieder Initial-Run
rm /var/lib/pve-bootstrap/initialized

# Oder direkt:
pve-bootstrap --force-initial
```

## Modul-Übersicht

| Modul | Skip-Name | Initial | Drift |
|-------|-----------|---------|-------|
| APT-Repos | `repos` | ✓ | – |
| Subscription-Nag | `nag` | ✓ | – |
| Postfix | `postfix` | ✓ | – |
| Host-Tools | `tools` | ✓ | – |
| fail2ban | `fail2ban` | ✓ | – |
| NFS-Storages | `nfs` | ✓ | – |
| Ultimate Updater Install | `uu` | ✓ | – |
| Ultimate Updater Config | `uu_config` | ✓ | (warnt bei Drift) |
| Cronjob | `cron` | ✓ | (warnt bei Drift) |
| LXC-Bootstrap | `lxc` | ✓ | ✓ |

## PVE 8 → 9 Upgrade

Das Skript funktioniert auf beiden Versionen — `DEB_CODENAME` wird automatisch aus `/etc/os-release` gelesen (`bookworm` oder `trixie`). Beim Upgrade selbst:

1. System vollständig auf PVE 8.4 updaten
2. `pve8to9 --full` ausführen und alle FAILs beheben
3. Repos auf Trixie umstellen + `apt dist-upgrade`
4. Reboot
5. State-Marker löschen + `pve-bootstrap --force-initial` für Nachkontrolle

Offizielle Upgrade-Anleitung: https://pve.proxmox.com/wiki/Upgrade_from_8_to_9

## Sicherheitshinweise

- Vor dem Erstaufruf auf einem Produktivsystem unbedingt `--dry-run` nutzen
- Backups der angefassten Configs werden mit Timestamp angelegt (`*.bak.<DATUM>`)
- Bei manuell geänderten Configs (`update.conf`, Cronjob) wird im Drift-Modus nur gewarnt, nicht überschrieben

## Was bewusst NICHT enthalten ist

- **Netzwerkkonfiguration** — zu individuell
- **PVE-Backup-Jobs** — über die WebUI sauberer zu konfigurieren
- **Cluster/Corosync** — Skript ist Single-Node-only
- **CPU-Governor** — hardwareabhängig

## Changelog

### Aktuell
- Globaler Befehl `pve-bootstrap` wird nach Initial-Run automatisch via Symlink angelegt
- LXC-Bootstrap überspringt Container mit Tag `no-bootstrap` (für inkompatible Systeme wie Yunohost)
- LXC-Bootstrap Output kompakt: nur Zusammenfassungszeile pro Container
- Dry-Run Logging korrigiert: kein fälschliches `[OK]` mehr bei nicht ausgeführten Aktionen
- PVE 9.1 / Debian Trixie getestet und bestätigt

### Initial
- Modulare Architektur mit Initial/Drift-Modus
- Idempotente Ausführung, Bestätigung nur beim ersten Lauf
- Config-Pattern: `config.default.sh` + gitignoriertes `config.local.sh`

## Lizenz

MIT

## Credits

Inspiriert durch und nutzt:

- [BassT23/Proxmox](https://github.com/BassT23/Proxmox) (GPL) — Ultimate Updater, wird via Installer als Dependency eingebunden
- [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) (MIT) — Vorbild für Post-Install-Struktur

Eigenständige Implementierung, keine Code-Übernahme.
Teile dieses Codes wurden mit Hilfe von KI generiert.
