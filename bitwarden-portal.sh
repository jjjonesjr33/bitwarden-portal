#!/bin/bash

# Configurations (from .env file)
SOURCE_ACCOUNT="$SOURCE_ACCOUNT"  # Email di Bitwarden
SOURCE_PASSWORD="$SOURCE_PASSWORD"  # Password di Bitwarden
SOURCE_CLIENT_ID="$SOURCE_CLIENT_ID"  # Client ID di Bitwarden
SOURCE_CLIENT_SECRET="$SOURCE_CLIENT_SECRET"  # Client Secret di Bitwarden
SOURCE_SERVER="$SOURCE_SERVER"

DEST_ACCOUNT="$DEST_ACCOUNT"  # Email di Vaultwarden
DEST_PASSWORD="$DEST_PASSWORD"  # Password di Vaultwarden
DEST_CLIENT_ID="$DEST_CLIENT_ID"  # Client ID di Vaultwarden
DEST_CLIENT_SECRET="$DEST_CLIENT_SECRET"  # Client Secret di Vaultwarden
DEST_SERVER="$DEST_SERVER"

#ARCHIVE_PASSWORD="xxxxxxxxxxxxxxxxxxxxxxxxx"

# Minimum backup file to mantain
MIN_FILES=5
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")



#------#
# INIT #
#------#

# Create folder if not exists 
SOURCE_FOLDER="/app/backups/source"
DEST_FOLDER="/app/backups/dest"

mkdir -p "$SOURCE_FOLDER"

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to create folder /backups/source"
    exit 1
fi

mkdir -p "$DEST_FOLDER"

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to create folder /backups/dest"
    exit 1
fi

echo "########## Start of Backup process ##########"
sleep 1

#--------#
# BACKUP #
#--------#

# Set the filename for our json export as variable
SOURCE_EXPORT_OUTPUT_BASE="bw_export_source_"
SOURCE_NEW_FILENAME="$SOURCE_EXPORT_OUTPUT_BASE$TIMESTAMP.json"
SOURCE_OUTPUT_FILE_PATH="$SOURCE_FOLDER/$SOURCE_NEW_FILENAME"

# Delete previous backups over 30 days old ######################################################################

#echo "# Deleting previous backups older than 30 days... "
#current_date=$(date +%Y-%m-%d)
#source_export_files=$(find /app/backups/source -type f -name "$SOURCE_EXPORT_OUTPUT_BASE*.tar.gz.enc")
#find $source_export_files -type f -mtime +30 -exec rm -f {} +
#rm -f -R $SOURCE_EXPORT_OUTPUT_BASE*.json

# Find all file in directory ordered by date (from most recend to oldest)
#FILES=$(find "$SOURCE_FOLDER" -type f -mtime +30 -printf "%T@ %p\n" | sort -n | awk '{print $2}')

# Count all files in directory
#TOTAL_FILES=$(find "$SOURCE_FOLDER" -type f | wc -l)

# Check if there are more file than minimum
#if [ "$TOTAL_FILES" -le "$MIN_FILES" ]; then
#    echo "# There are $TOTAL_FILES files, less than the minimum limit of $MIN_FILES. No file will be deleted."
#else
    # Calcola quanti file eliminare
#    FILES_TO_DELETE=$(($TOTAL_FILES - $MIN_FILES))

    # Elimina solo i file più vecchi di 90 giorni, rispettando il limite minimo
#    echo "$FILES" | head -n "$FILES_TO_DELETE" | xargs -I{} rm -f "{}"
#    echo "# Old backups purged"
#fi


#--------------#
# SOURCE LOGIN #
#--------------#

# Lets make sure we're logged out before we start
echo "# Logging out from Bitwarden..."
bw logout >/dev/null

export BW_CLIENTID=${SOURCE_CLIENT_ID}
export BW_CLIENTSECRET=${SOURCE_CLIENT_SECRET}

# Login to our Server
echo "# Logging into Source server..."
bw config server "$SOURCE_SERVER"

bw login "$SOURCE_ACCOUNT" --apikey --raw

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to log in to source server with account ${SOURCE_ACCOUNT} at ${SOURCE_SERVER}"
    exit 1
fi

printf '\n'

# By using an API Key, we need to unlock the vault to get a sessionID
echo "# Unlocking the vault..."
SOURCE_SESSION=$(bw unlock "$SOURCE_PASSWORD" --raw)

if [ -z "$SOURCE_SESSION" ]; then
    echo "✕ Error: No source session retrieved. Check your source credentials and try again."
    exit 1
fi

# Synchronizing the vault
echo "# Synchronizing the vault..."
bw sync --session "$SOURCE_SESSION"
printf '\n'


#---------------#
# SOURCE EXPORT #
#---------------#

echo "# Exporting all items..."
bw --session "$SOURCE_SESSION" export --raw --format json > "$SOURCE_OUTPUT_FILE_PATH"

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to export data."
    exit 1
fi

echo "# Exported items file: backups/source/$SOURCE_NEW_FILENAME"

sleep 1

#---------------#
# SOURCE LOGOUT #
#---------------#
echo "# Locking the vault..."
bw lock
echo ""

# Logout
echo "# Logging out from Bitwarden..."
bw logout >/dev/null

unset BW_CLIENTID
unset BW_CLIENTSECRET

echo "########## End of Backup process ##########"

sleep 1


#---------#
# RESTORE #
#---------#

# Restoring process
echo "########## Start of Restore process ##########"

# We want to remove items later, so we set a base filename now
DEST_EXPORT_OUTPUT_BASE="bw_export_dest_"
DEST_NEW_FILENAME="$DEST_EXPORT_OUTPUT_BASE$TIMESTAMP.json" #DEST_OUTPUT_FILE
DEST_OUTPUT_FILE_PATH="$DEST_FOLDER/$DEST_NEW_FILENAME"


#------------#
# DEST LOGIN #
#------------#

export BW_CLIENTID=${DEST_CLIENT_ID}
export BW_CLIENTSECRET=${DEST_CLIENT_SECRET}


# Login to our Server
echo "# Logging into Dest server..."
bw config server "$DEST_SERVER"

bw login "$DEST_ACCOUNT" --apikey --raw

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to log in to destination server with account ${DEST_ACCOUNT} at ${DEST_SERVER}"
    exit 1
fi

printf '\n'

# By using an API Key, we need to unlock the vault to get a sessionID
echo "# Unlocking the vault..."
DEST_SESSION=$(bw unlock $DEST_PASSWORD --raw)

if [ -z "$DEST_SESSION" ]; then
    echo "✕ Error: No destination session retrieved. Check your source credentials and try again."
    exit 1
fi

# Synchronizing the vault
echo "# Synchronizing the vault..."
bw sync --session "$DEST_SESSION"
printf '\n'


#-------------#
# DEST EXPORT #
#-------------#

# Export what's currently in the vault, so we can remove it
echo "# Exporting current items from destination vault..."
bw --session $DEST_SESSION export --raw --format json > "$DEST_OUTPUT_FILE_PATH"

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to export data."
    exit 1
fi

echo "# Exported items file: backups/dest/$DEST_NEW_FILENAME"

sleep 1

#--------------#
# DEST REMOMVE #
#--------------#

# Find and remove all folders, items, attachments, and org collections
echo "# Removing items from the destination vault... This might take some time."

### FOLDERS
total_folders=$(jq '.folders | length' "$DEST_OUTPUT_FILE_PATH")

if [ -z "$total_folders" ] || [ "$total_folders" -eq 0 ]; then
    echo "# No folders found to delete"
else
    current_folder=0

    # Loop on folders to remove
    for id in $(jq -r '.folders[]? | .id' "$DEST_OUTPUT_FILE_PATH"); do
        current_folder=$((current_folder + 1))
        echo "# Deleting folder [$current_folder/$total_folders]"
    
        # Delete folder
        bw --session "$DEST_SESSION" --raw delete -p folder "$id"
    done

    echo "# Folders deleted successfully"
fi

sleep 1

### ITEMS
total_items=$(jq '.items | length' "$DEST_OUTPUT_FILE_PATH")

if [ -z "$total_items" ] || [ "$total_items" -eq 0 ]; then
    echo "# No items found to delete"
else
    current_item=0

    # Loop sugli ID con progresso
    for id in $(jq -r '.items[]? | .id' "$DEST_OUTPUT_FILE_PATH"); do
        current_item=$((current_item + 1))
        echo "# Deleting item [$current_item/$total_items]"

        # Rimuovi l'elemento
        bw --session "$DEST_SESSION" --raw delete -p item "$id"
    done

    echo "# Items deleted successfully"
fi

sleep 1

### ATTACHMENTS
total_attach=$(jq '.attachments | length' "$DEST_OUTPUT_FILE_PATH")

if [ -z "$total_attach" ] || [ "$total_attach" -eq 0 ]; then
    echo "# No attachments found to delete."
else
    current_attach=0

    # Loop sugli ID con progresso
    for id in $(jq -r '.attachments[]? | .id' "$DEST_OUTPUT_FILE_PATH"); do
        current_attach=$((current_attach + 1))
        echo "# Deleting attachment [$current_attach/$total_attach]"

        # Rimuovi l'elemento
        bw --session "$DEST_SESSION" --raw delete -p attachment "$id"
    done

    echo "# Attachments deleted successfully"
fi


echo "# Vault purged successfully"
echo "# Total removed -> Folders:[${total_folders:-"0"}] - Items:[${total_items:-"0"}] - Attachments:[${total_attach:-"0"}]"

sleep 1

#-------------#
# DEST IMPORT #
#-------------#

DEST_LATEST_BACKUP="$SOURCE_OUTPUT_FILE_PATH"

# Import the latest backup
echo "# Importing the latest backup: $DEST_LATEST_BACKUP"
bw --session "$DEST_SESSION" --raw import bitwardenjson "$DEST_LATEST_BACKUP"

if [ $? -ne 0 ]; then
    echo "✕ Error: Failed to import data"
    exit 1
fi


#-------------#
# DEST LOGOUT #
#-------------#

echo "# Locking the vault and logout from destination server..."
bw lock > /dev/null

bw logout > /dev/null

echo "########## End of Restore Process ##########"

unset BW_CLIENTID
unset BW_CLIENTSECRET