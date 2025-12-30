#!/bin/bash
# backup.sh

# Need to start container in fly.io if it was stopped by inactivity
curl -s -o /dev/null https://sarduty.com/

filename="backups/data_backup_$(date +%F).tar.gz"
fly ssh console -C 'tar cvz /mnt/sarduty' -t $FLY_SSH_TOKEN > $filename
