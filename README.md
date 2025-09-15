# Wazuh Central Components Backup Script

A Bash script to back up **Wazuh Manager, Indexer, and Dashboard** configurations and data.  
This tool automates the manual steps described in the Wazuh Documentation https://documentation.wazuh.com/current/migration-guide/creating/wazuh-central-components.html

## ✨ Features
- Backup of:
  - **Wazuh Manager**
    - Config files, rules, decoders, keys, logs
    - Manager databases (`queue/db`) with safe stop/start
  - **Wazuh Indexer**
    - Configs and security settings
    - Optionally archive indexer data (for single-node labs)
    - ⚠️ For production clusters, use **snapshots** instead
  - **Wazuh Dashboard**
    - Configs and data folder
- Logging (`/var/log/wazuh_backup_*.log`)
- Checksums (`sha256sum` file for integrity verification)
- Timestamped backup directories

---

## 🚀 Usage
1. Make the script executable:
   chmod +x wazuh-backup.sh
   
2. Rund as root
  sudo ./wazuh-backup.sh

   Backups will be created in:
  /var/backups/wazuh-YYYY-MM-DD_HHMM/

   Logs will be stored in:
   /var/log/wazuh_backup_YYYY-MM-DD_HHMM.log


