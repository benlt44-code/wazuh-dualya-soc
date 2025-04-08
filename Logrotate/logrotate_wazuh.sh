#!/bin/bash

LOG_DIR="/var/log/wazuh/syslog"
ARCHIVE_DIR="/mnt/wazuh_archives"
SMB_SHARE="//10.44.110.213/besafe/SIEM_WAZUH_ARCHIVE"
SMB_USER="besafe"
SMB_PASS="BeSafe"
MAX_SIZE=200000000  # Taille maximale en kilo-octets (200 Go)
DATE=$(date +'%Y%m%d-%H%M%S')
LOG_FILE="/var/log/wazuh/syslog/logrotate_wazuh.log"

# Fonction pour calculer la taille totale des logs
calculate_total_size() {
    du -sk "$LOG_DIR" | awk '{print $1}'
}

# Fonction pour archiver et transférer les logs
archive_and_transfer_logs() {
    echo "$(date) - ⚙️ Taille limite atteinte : déclenchement de l'archivage et du transfert." >> "$LOG_FILE"

    # Effectuer le logrotate
    logrotate -f /etc/logrotate.d/wazuh >> "$LOG_FILE" 2>&1

    # Monter le partage SMB si nécessaire
    if ! mountpoint -q "$ARCHIVE_DIR"; then
        mount -t cifs -o username=$SMB_USER,password=$SMB_PASS "$SMB_SHARE" "$ARCHIVE_DIR" >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            echo "$(date) - ❌ Erreur de montage du partage SMB." >> "$LOG_FILE"
            exit 1
        fi
    fi

    # Transférer chaque répertoire machine vers le partage SMB avec la date
    for machine_dir in "$LOG_DIR"/*; do
        if [ -d "$machine_dir" ]; then
            machine_name=$(basename "$machine_dir")
            dest_dir="$ARCHIVE_DIR/$machine_name/$DATE"
            mkdir -p "$dest_dir"
            mv "$machine_dir"/*.gz "$dest_dir" 2>/dev/null
        fi
    done

    # Vérifier la réussite du transfert
    if [ $? -eq 0 ]; then
        echo "$(date) - ✅ Transfert des logs réussi pour toutes les machines." >> "$LOG_FILE"
    else
        echo "$(date) - ❌ Échec du transfert des logs." >> "$LOG_FILE"
    fi

    # Supprimer les fichiers logs locaux
    find "$LOG_DIR" -type f -name "*.gz" -delete
    echo "$(date) - 🧹 Logs locaux supprimés." >> "$LOG_FILE"
}

# Vérifier régulièrement la taille totale des logs
while true; do
    total_size=$(calculate_total_size)

    if [ "$total_size" -gt "$MAX_SIZE" ]; then
        archive_and_transfer_logs
    else
        echo "$(date) - 💾 Espace utilisé : $(($total_size / 1024)) Mo / $(($MAX_SIZE / 1024)) Mo" >> "$LOG_FILE"
    fi

    # Vérifier toutes les 1 minute
    sleep 60
done
