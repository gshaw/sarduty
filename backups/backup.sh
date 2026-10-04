#!/bin/bash
# backup.sh — a consistent snapshot of the database plus the team logos, tarred over
# fly ssh and encrypted to the backup age key, so no plain copy lands on disk. Decrypt
# with the identity from the password manager: age -d -i <identity file> <backup> | tar xz

set -euo pipefail

: "${BACKUP_AGE_RECIPIENT:?set it in .mise.local.toml}"

# Need to start container in fly.io if it was stopped by inactivity
curl -s -o /dev/null https://sarduty.com/

# Tarring the live database can catch the WAL mid-write. VACUUM INTO, run by the app,
# writes a consistent copy instead; the image has no sqlite3 to do it.
snapshot=/tmp/backup.db
fly ssh console -a sarduty -C "/app/bin/sarduty rpc \"File.rm(\\\"$snapshot\\\"); App.Repo.query!(\\\"VACUUM INTO ?1\\\", [\\\"$snapshot\\\"])\"" > /dev/null

# A timestamp, so a second backup on one day doesn't overwrite the first.
filename="backups/data_backup_$(date +%F-%H%M).tar.gz.age"
fly ssh console -a sarduty -C "sh -c 'tar cz -C / ${snapshot#/} mnt/sarduty/team-logos && rm $snapshot'" |
  age -r "$BACKUP_AGE_RECIPIENT" > "$filename"

echo "$filename"
