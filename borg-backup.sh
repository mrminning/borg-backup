#!/usr/bin/env bash

# load values from .env
set -o allexport
eval $(cat '.env' | sed -e '/^#/d;/^\s*$/d' -e 's/\(\w*\)[ \t]*=[ \t]*\(.*\)/\1=\2/' -e "s/=['\"]\(.*\)['\"]/=\1/g" -e "s/'/'\\\''/g" -e "s/=\(.*\)/='\1'/g")
set +o allexport

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=${ENV_BORG_REPO}
# See the section "Passphrase notes" for more infos.
export BORG_PASSPHRASE=${ENV_BORG_PASSPHRASE}
export BORG_RESTORE_MOUNT=${ENV_BORG_RESTORE_MOUNT}
LOG=${ENV_BORG_LOG_DIRECTORY}${ENV_BORG_LOG_FILE}

##
## write output to log file
##

exec > >(tee -i ${LOG})
exec 2>&1

# first try to unmount repository if existting
if borg umount ${BORG_RESTORE_MOUNT}; then
    echo "Restore folder unmounted"
else
    echo "No restore folder mounted!"
fi


# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

info "Starting backup"

# Backup the most important directories into an archive named after
# the machine this script is currently running on:
# check the file patterns.lst for including and excluding stuff

borg create                         \
    --verbose                       \
    --filter AME                    \
    --list                          \
    --stats                         \
    --show-rc                       \
    --compression lz4               \
    --exclude-caches                \
    --exclude '/home/*/.cache/*'    \
    --exclude '/var/tmp/*'          \
    ::'{hostname}-{now}'            \
    --patterns-from './patterns.lst'

backup_exit=$?

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                          \
    --list                          \
    --prefix '{hostname}-'          \
    --show-rc                       \
    --keep-daily    7               \
    --keep-weekly   4               \
    --keep-monthly  6               \

prune_exit=$?


# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup, Prune, and Compact finished successfully"
elif [ ${global_exit} -eq 1 ]; then
    info "Backup, Prune, and/or Compact finished with warnings"
else
    info "Backup, Prune, and/or Compact finished with errors"
fi