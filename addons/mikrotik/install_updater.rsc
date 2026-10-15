/system script remove BKPUPD-UPDATER

:local result [/tool fetch mode=https url="https://SERVER_NAME/routeros/BKPUPD-UPDATER.rsc" check-certificate=no without-paging as-value]

/import file=BKPUPD-UPDATER.rsc

/file remove BKPUPD-UPDATER.rsc

/system script run BKPUPD-UPDATER
