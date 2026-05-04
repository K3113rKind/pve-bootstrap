# pve-bootstrap

Idempotentes Bootstrap- und Wartungs-Skript für Proxmox VE Hosts (Single-Node).

Setzt einen frisch installierten PVE-Server in einem Rutsch auf produktiven Stand und kann anschließend regelmäßig wiederholt werden, um neue LXCs/VMs mit Standardpaketen zu versorgen.

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

**Bei Folge-Aufrufen** (Drift-Run, ohne Prompts):

- LXC-Bootstrap auf neue Container anwenden
- Cronjob-Drift erkennen
- Ultimate-Updater-Config-Drift erkennen
- Init-only-Module werden übersprungen

## Voraussetzungen

- Proxmox VE 8.x (für 7.x ggf. Anpassungen nötig)
- Single-Node-Setup (für Cluster muss das Cron- und LXC-Modul angepasst werden)
- Root-Zugriff auf den PVE-Host
- Internetzugang

## Schnellstart

```bash
# Auf den PVE-Host kopieren (z.B. nach /root/)
git clone https://github.com/<USER>/pve-bootstrap.git
cd pve-bootstrap

# Lokale Config anlegen (NFS-Server, eigene Werte)
cp config.local.sh.example config.local.sh
nano config.local.sh

# Erstmal trocken laufen lassen
./pve-bootstrap.sh --dry-run

# Echt ausführen
./pve-bootstrap.sh
```

Beim ersten Lauf wird einmal bestätigt; danach läuft alles ohne weitere Prompts. Folgeläufe (z.B. nach Anlage neuer Container) sind komplett interaktionsfrei.

## Aufrufoptionen

```bash
./pve-bootstrap.sh                  # Auto-Detect (initial vs. drift)
./pve-bootstrap.sh --dry-run        # Nur anzeigen, nichts ändern
./pve-bootstrap.sh --force-initial  # Initial-Run erzwingen (z.B. nach manueller Änderung)
./pve-bootstrap.sh --skip=fail2ban,nag  # Module gezielt überspringen
./pve-bootstrap.sh --help
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

## State-Marker

Nach dem ersten erfolgreichen Lauf wird `/var/lib/pve-bootstrap/initialized` angelegt. Solange diese Datei existiert, läuft das Skript im Drift-Modus. Mit `--force-initial` lässt sich der Initial-Modus erzwingen, oder einfach den Marker löschen.

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

## Sicherheitshinweise

- Vor dem Erstaufruf auf einem Produktivsystem unbedingt `--dry-run` nutzen
- Backups der angefassten Configs werden mit Timestamp angelegt (`*.bak.<DATUM>`)
- Bei manuell geänderten Configs (`update.conf`, Cronjob) wird im Drift-Modus nur gewarnt, nicht überschrieben — Re-Bootstrap mit `--force-initial`

## Was bewusst NICHT enthalten ist

- **Netzwerkkonfiguration** — zu individuell
- **PVE-Backup-Jobs** — über die WebUI sauberer zu konfigurieren
- **Cluster/Corosync** — Skript ist Single-Node-only
- **CPU-Governor** — hardwareabhängig

## Lizenz

MIT

## Credits

Dieses Skript wurde inspiriert durch und nutzt:

- [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) (MIT) — 
  Vorbild für die Post-Install-Struktur (Repos, Nag, Postfix)
- [BassT23/Proxmox](https://github.com/BassT23/Proxmox) (GPL) — 
  wird via Installer als Dependency eingebunden (Ultimate Updater für die wöchentlichen Updates)

Eigenständige Implementierung, keine Code-Übernahme.
