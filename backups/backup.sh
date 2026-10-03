#!/bin/bash
# backup.sh — tars the volume over fly ssh, encrypted to the backup age key, so no
# plain copy of the database lands on disk. Decrypt with the identity from the password
# manager: age -d -i <identity file> <backup> | tar xz

set -euo pipefail

: "${BACKUP_AGE_RECIPIENT:?set it in .mise.local.toml}"

# Need to start container in fly.io if it was stopped by inactivity
curl -s -o /dev/null https://sarduty.com/

filename="backups/data_backup_$(date +%F).tar.gz.age"
fly ssh console -C 'tar cz /mnt/sarduty' -t "$FLY_SSH_TOKEN" | age -r "$BACKUP_AGE_RECIPIENT" > "$filename"
