#!/usr/bin/env bash
# Wazuh Central Components Backup Script 
# Based on Wazuh documentation:https://documentation.wazuh.com/current/migration-guide/creating/wazuh-central-components.html

set -euo pipefail
IFS=$'\n\t'

TIMESTAMP=$(date +%F_%H%M)
BACKUP_DIR="/var/backups/wazuh-$TIMESTAMP"
LOG_FILE="/var/log/wazuh_backup_$TIMESTAMP.log"
WAZUH_VERSION=$(cat /etc/wazuh/VERSION 2>/dev/null || echo "unknown")

# Set to 1 to skip indexer data archive (recommended to use snapshots for production clusters).
USE_INDEXER_SNAPSHOT=0

mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

if [ "$(id -u)" -ne 0 ]; then
  log "This script must be run as root. Exiting."
  exit 1
fi

log "Starting Wazuh backup (version: $WAZUH_VERSION) -> $BACKUP_DIR"

# --- Manager backup (configs + DBs) ---
backup_manager() {
  log "Backing up Wazuh Manager configuration files."

  rsync -a --numeric-ids /etc/filebeat/ "$BACKUP_DIR/etc-filebeat/" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /etc/postfix/ "$BACKUP_DIR/etc-postfix/" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/api/configuration/ "$BACKUP_DIR/api-configuration/" 2>>"$LOG_FILE" || true

  rsync -a --numeric-ids /var/ossec/etc/ossec.conf "$BACKUP_DIR/ossec.conf" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/etc/*.pem "$BACKUP_DIR/ossec-pems/" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/etc/client.keys "$BACKUP_DIR/client.keys" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/etc/local_rules.xml "$BACKUP_DIR/local_rules.xml" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/etc/local_decoder.xml "$BACKUP_DIR/local_decoder.xml" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/etc/shared/ "$BACKUP_DIR/shared/" 2>>"$LOG_FILE" || true
  rsync -a --numeric-ids /var/ossec/logs/ "$BACKUP_DIR/logs/" 2>>"$LOG_FILE" || true

  if systemctl is-active --quiet wazuh-manager; then
    log "Stopping wazuh-manager to safely copy DB files..."
    systemctl stop wazuh-manager
    MANAGER_STOPPED=1
  else
    MANAGER_STOPPED=0
  fi

  log "Backing up Wazuh manager DBs (queue/db)..."
  tar -czf "$BACKUP_DIR/wazuh_manager_db.tar.gz" -C /var/ossec queue/db/ 2>>"$LOG_FILE" || true

  if [ "$MANAGER_STOPPED" -eq 1 ]; then
    log "Starting wazuh-manager..."
    systemctl start wazuh-manager
  fi

  log "Wazuh Manager backup finished."
}

# --- Indexer backup (configs + data fallback) ---
backup_indexer() {
  if ! systemctl list-unit-files --type=service | grep -q wazuh-indexer; then
    log "wazuh-indexer service not detected; skipping indexer backup."
    return
  fi

  log "Backing up Wazuh Indexer configuration files..."
  tar -czf "$BACKUP_DIR/wazuh_indexer_config.tar.gz" -C /etc wazuh-indexer/ 2>>"$LOG_FILE" || true

  if [ -d /etc/wazuh-indexer/opensearch-security ]; then
    tar -czf "$BACKUP_DIR/wazuh_indexer_security.tar.gz" -C /etc/wazuh-indexer opensearch-security/ 2>>"$LOG_FILE" || true
  fi

  if [ "$USE_INDEXER_SNAPSHOT" -eq 1 ]; then
    log "Index data backup skipped (snapshots recommended for production)."
    return
  fi

  if systemctl is-active --quiet wazuh-indexer; then
    log "Stopping wazuh-indexer to archive data (single-node fallback; snapshots recommended)..."
    systemctl stop wazuh-indexer
    tar -czf "$BACKUP_DIR/wazuh_indexer_data.tar.gz" -C /var/lib wazuh-indexer/ 2>>"$LOG_FILE" || true
    systemctl start wazuh-indexer
    log "Wazuh Indexer data archived."
  else
    log "wazuh-indexer not active; skipping indexer data archive."
  fi
}

# --- Dashboard backup ---
backup_dashboard() {
  if systemctl list-unit-files --type=service | grep -q wazuh-dashboard; then
    log "Backing up Wazuh Dashboard config and data..."
    tar -czf "$BACKUP_DIR/wazuh_dashboard_config.tar.gz" -C /etc wazuh-dashboard/ 2>>"$LOG_FILE" || true
    if [ -d /usr/share/wazuh-dashboard/data ]; then
      tar -czf "$BACKUP_DIR/wazuh_dashboard_data.tar.gz" -C /usr/share/wazuh-dashboard/data . 2>>"$LOG_FILE" || true
    fi
    log "Wazuh Dashboard backup finished."
  else
    log "wazuh-dashboard service not present; skipping."
  fi
}

# Run backups
backup_manager
backup_indexer
backup_dashboard

log "Creating checksums for archives..."
sha256sum "$BACKUP_DIR"/*.tar.gz > "$BACKUP_DIR/backup_checksums.sha256" 2>>"$LOG_FILE" || true

BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "Backup finished: $BACKUP_DIR (size: $BACKUP_SIZE)"
log "Backup log: $LOG_FILE"
