/system script remove BKPUPD-UPDATER

:local result [/tool fetch mode=http url="http://SERVER_NAME/routeros/BKPUPD-UPDATER.rsc" without-paging as-value]

/import file=BKPUPD-UPDATER.rsc

/file remove BKPUPD-UPDATER.rsc

/system script run BKPUPD-UPDATER
