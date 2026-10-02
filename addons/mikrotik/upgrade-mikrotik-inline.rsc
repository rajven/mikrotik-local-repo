add dont-require-permissions=no name=BackupAndUpdate owner=admin policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source="# ============================================================\
    \n# BackupAndUpdate (ROS6/ROS7 compatible + Server Policy Check)\
    \n# ============================================================\
    \n\
    \n:local scriptName \"BackupAndUpdate\"\
    \n:local dailySchedulerName \"BKPUPD-DAILY\"\
    \n:local rebootSchedulerName \"BKPUPD-REBOOT\"\
    \n:local updateChannel \"stable\"\
    \n:local backupName \"auto-backup\"\
    \n:local backupPassword \"\"\
    \n:local backupPath \"\"\
    \n:local backupFullPath \"\"\
    \n:local flashAvailable false\
    \n:local Httpmode \"http\"\
    \n\
    \n# Server URL for policy check\
    \n:local policyCheckUrl \"http://SERVER_NAME/routeros/force_update.php\"\
    \n\
    \n:local osUpdateNeeded false\
    \n:local firmwareUpdateNeeded false\
    \n:local routerboardAvailable false\
    \n:local currentFirmware \"\"\
    \n:local upgradeFirmware \"\"\
    \n:local currentVersion \"\"\
    \n:local latestVersion \"\"\
    \n\
    \n:log info \"BackupAndUpdate: === SCRIPT STARTED ===\"\
    \n\
    \n# ============================================================\
    \n# Step 1: Daily scheduler\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info \"BackupAndUpdate: Step 1 start\"\
    \n\
    \n    :if ([:len [/system scheduler find name=\$dailySchedulerName]] = 0) do={\
    \n        /system scheduler add \\\
    \n            name=\$dailySchedulerName \\\
    \n            start-time=05:00:00 \\\
    \n            interval=1d \\\
    \n            on-event=\$scriptName \\\
    \n            policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon\
    \n        :log info \"BackupAndUpdate: daily scheduler created\"\
    \n    } else={\
    \n        :log info \"BackupAndUpdate: daily scheduler exists\"\
    \n    }\
    \n\
    \n    :log info \"BackupAndUpdate: Step 1 OK\"\
    \n} on-error={\
    \n    :log error \"BackupAndUpdate: Step 1 FAILED\"\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 2: Check RouterOS updates\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info \"BackupAndUpdate: Step 2 start\"\
    \n\
    \n    # Check major ROS version to set mode=http only for ROS 7\
    \n    :local rosVersion [/system resource get version]\
    \n    :local majorVersion [:pick \$rosVersion 0 1]\
    \n\
    \n    :local setMode \"print\"\
    \n    :if (\$majorVersion = \"7\") do={\
    \n        :log info \"BackupAndUpdate: ROS 7 detected -> executing mode=http\"\
    \n        :local cmd \"/system package update set mode=\$Httpmode\"\
    \n        :execute \$cmd\
    \n        :delay 1s\
    \n    } else={\
    \n        :log info \"BackupAndUpdate: mode=http skipped (ROS6)\"\
    \n    }\
    \n\
    \n    /system package update set channel=\$updateChannel\
    \n    :log info \"BackupAndUpdate: channel set \$updateChannel\"\
    \n\
    \n    /system package update check-for-updates\
    \n    :log info \"BackupAndUpdate: check started, waiting 15s\"\
    \n\
    \n    :delay 15s\
    \n\
    \n    :set currentVersion [/system package update get installed-version]\
    \n    :log info (\"BackupAndUpdate: current=\" . \$currentVersion)\
    \n\
    \n    :set latestVersion [/system package update get latest-version]\
    \n    :log info (\"BackupAndUpdate: latest=\" . \$latestVersion)\
    \n\
    \n    :local updateStatus [/system package update get status]\
    \n    :log info (\"BackupAndUpdate: status=\" . \$updateStatus)\
    \n\
    \n    :if (\$updateStatus = \"New version is available\") do={\
    \n        :set osUpdateNeeded true\
    \n        :log info \"BackupAndUpdate: update IS available\"\
    \n    } else={\
    \n        :log info \"BackupAndUpdate: no update available\"\
    \n    }\
    \n\
    \n    :log info \"BackupAndUpdate: Step 2 OK\"\
    \n} on-error={\
    \n    :log error \"BackupAndUpdate: Step 2 FAILED\"\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 3: Check RouterBOARD firmware\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info \"BackupAndUpdate: Step 3 start\"\
    \n\
    \n    :set currentFirmware [/system routerboard get current-firmware]\
    \n    :log info (\"BackupAndUpdate: current-fw=\" . \$currentFirmware)\
    \n\
    \n    :set upgradeFirmware [/system routerboard get upgrade-firmware]\
    \n    :log info (\"BackupAndUpdate: upgrade-fw=\" . \$upgradeFirmware)\
    \n\
    \n    :set routerboardAvailable true\
    \n\
    \n    :if (\$currentFirmware != \$upgradeFirmware) do={\
    \n        :set firmwareUpdateNeeded true\
    \n        :log info \"BackupAndUpdate: firmware update needed\"\
    \n    } else={\
    \n        :log info \"BackupAndUpdate: firmware up to date\"\
    \n    }\
    \n\
    \n    :log info \"BackupAndUpdate: Step 3 OK\"\
    \n} on-error={\
    \n    :log error \"BackupAndUpdate: Step 3 FAILED\"\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 3.5: Check update policy on server (NEW)\
    \n# ============================================================\
    \n\
    \n:if (\$osUpdateNeeded = true) do={\
    \n    :do {\
    \n        :log info \"BackupAndUpdate: Step 3.5 start - checking server policy\"\
    \n\
    \n        :local checkUrl (\$policyCheckUrl . \"\?new_version=\" . \$latestVersion)\
    \n        :local checkFile \"force_update_check.txt\"\
    \n        :local serverResponse \"DISABLED\"\
    \n\
    \n        # Delete old check file if it still exists\
    \n        :foreach fileId in=[/file find name=\$checkFile] do={\
    \n            /file remove \$fileId\
    \n        }\
    \n\
    \n        # Download server response\
    \n        /tool fetch url=\$checkUrl mode=http dst-path=\$checkFile\
    \n        :delay 2s\
    \n\
    \n        # Read file contents\
    \n        :local fileId [/file find name=\$checkFile]\
    \n        :if ([:len \$fileId] > 0) do={\
    \n            :set serverResponse [/file get \$fileId contents]\
    \n            /file remove \$fileId\
    \n        }\
    \n\
    \n        :log info (\"BackupAndUpdate: server response for v\" . \$latestVersion . \": \" . \$serverResponse)\
    \n\
    \n        :if (\$serverResponse != \"ENABLED\") do={\
    \n            :log warning \"BackupAndUpdate: update NOT authorized by server. Aborting RouterOS update.\"\
    \n            :set osUpdateNeeded false\
    \n        } else={\
    \n            :log info \"BackupAndUpdate: update authorized by server.\"\
    \n        }\
    \n\
    \n        :log info \"BackupAndUpdate: Step 3.5 OK\"\
    \n    } on-error={\
    \n        :log error \"BackupAndUpdate: Step 3.5 FAILED (server unreachable or fetch error)\"\
    \n        :set osUpdateNeeded false\
    \n    }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 4: RouterOS update\
    \n# ============================================================\
    \n\
    \n:if (\$osUpdateNeeded = true) do={\
    \n    :do {\
    \n        :log info \"BackupAndUpdate: Step 4 start - RouterOS update\"\
    \n\
    \n        # Reboot scheduler\
    \n        :if ([:len [/system scheduler find name=\$rebootSchedulerName]] = 0) do={\
    \n            /system scheduler add \\\
    \n                name=\$rebootSchedulerName \\\
    \n                start-time=startup \\\
    \n                interval=0 \\\
    \n                on-event=\":delay 3m; /system script run BackupAndUpdate\" \\\
    \n                policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon\
    \n            :log info \"BackupAndUpdate: reboot scheduler created\"\
    \n        }\
    \n\
    \n        # ============================================================\
    \n        # Detect backup storage path\
    \n        # ============================================================\
    \n\
    \n        # ============================================================\
    \n        # Detect flash directory\
    \n        # ============================================================\
    \n\
    \n        :do {\
    \n            :local test [/file get flash name]\
    \n            :set flashAvailable true\
    \n            :set backupPath \"flash/\"\
    \n            :log info \"BackupAndUpdate: flash directory is available\"\
    \n        } on-error={\
    \n            :set flashAvailable false\
    \n            :set backupPath \"\"\
    \n            :log info \"BackupAndUpdate: flash directory not available, using root\"\
    \n        }\
    \n\
    \n        # ============================================================\
    \n        # Generate backup name from Serial Number and Date\
    \n        # ============================================================\
    \n\
    \n        :do {\
    \n            :local serial [/system routerboard get serial-number]\
    \n            :log info (\"BackupAndUpdate: device serial: \" . \$serial)\
    \n\
    \n            :local dateRaw [/system clock get date]\
    \n            :local day [:pick \$dateRaw 4 6]\
    \n            :local monthStr [:pick \$dateRaw 0 3]\
    \n            :local year [:pick \$dateRaw 7 11]\
    \n\
    \n            :local monthNum \"01\"\
    \n            :if (\$monthStr = \"jan\") do={ :set monthNum \"01\" }\
    \n            :if (\$monthStr = \"feb\") do={ :set monthNum \"02\" }\
    \n            :if (\$monthStr = \"mar\") do={ :set monthNum \"03\" }\
    \n            :if (\$monthStr = \"apr\") do={ :set monthNum \"04\" }\
    \n            :if (\$monthStr = \"may\") do={ :set monthNum \"05\" }\
    \n            :if (\$monthStr = \"jun\") do={ :set monthNum \"06\" }\
    \n            :if (\$monthStr = \"jul\") do={ :set monthNum \"07\" }\
    \n            :if (\$monthStr = \"aug\") do={ :set monthNum \"08\" }\
    \n            :if (\$monthStr = \"sep\") do={ :set monthNum \"09\" }\
    \n            :if (\$monthStr = \"oct\") do={ :set monthNum \"10\" }\
    \n            :if (\$monthStr = \"nov\") do={ :set monthNum \"11\" }\
    \n            :if (\$monthStr = \"dec\") do={ :set monthNum \"12\" }\
    \n\
    \n            :set backupName ( \"auto-backup-\" . \$serial . \"-\" . \$year . \"-\" . \$monthNum . \"-\" . \$day)\
    \n            :set backupFullPath (\$backupPath . \$backupName)\
    \n            :log info (\"BackupAndUpdate: backup full name: \" . \$backupFullPath)\
    \n        } on-error={\
    \n            :log error \"BackupAndUpdate: failed to generate backup name\"\
    \n        }\
    \n\
    \n        # Remove old backups (all files with prefix auto-backup- in the target directory)\
    \n        :log info \"BackupAndUpdate: removing old backup files\"\
    \n        :foreach fileId in=[/file find] do={\
    \n            :local fileName [/file get \$fileId name]\
    \n            :if ([:pick \$fileName 0 ([:len \$backupPath] + 7)] = (\$backupPath . \"auto-backup-\")) do={\
    \n                :if (([:pick \$fileName ([:len \$fileName] - 7) [:len \$fileName]] = \".backup\") || \\\
    \n                     ([:pick \$fileName ([:len \$fileName] - 4) [:len \$fileName]] = \".rsc\")) do={\
    \n                    /file remove \$fileId\
    \n                    :log info (\"BackupAndUpdate: removed old file: \" . \$fileName)\
    \n                }\
    \n            }\
    \n        }\
    \n\
    \n        # Binary backup\
    \n        :log info \"BackupAndUpdate: creating binary backup\"\
    \n        :if (\$backupPassword = \"\") do={\
    \n            /system backup save dont-encrypt=yes name=\$backupFullPath\
    \n        } else={\
    \n            /system backup save password=\$backupPassword name=\$backupFullPath\
    \n        }\
    \n        :log info \"BackupAndUpdate: binary backup done\"\
    \n\
    \n        # Config export\
    \n        :log info \"BackupAndUpdate: exporting config\"\
    \n        /export file=\$backupFullPath\
    \n        :log info \"BackupAndUpdate: config export done\"\
    \n\
    \n        # Wait for files\
    \n        :log info \"BackupAndUpdate: waiting for backup files\"\
    \n        :local backupReady false\
    \n        :local backupWait 0\
    \n\
    \n        :while ((\$backupReady = false) && (\$backupWait < 60)) do={\
    \n            :delay 1s\
    \n            :if (([:len [/file find name=(\$backupFullPath . \".backup\")]] > 0) && \\\
    \n                 ([:len [/file find name=(\$backupFullPath . \".rsc\")]] > 0)) do={\
    \n                :set backupReady true\
    \n            }\
    \n            :set backupWait (\$backupWait + 1)\
    \n        }\
    \n\
    \n        :if (\$backupReady = false) do={\
    \n            :log error \"BackupAndUpdate: backup timeout after 60s\"\
    \n            :return\
    \n        }\
    \n        :log info (\"BackupAndUpdate: backup files ready in \" . \$backupWait . \"s\")\
    \n\
    \n        # Install\
    \n        :log info (\"BackupAndUpdate: installing RouterOS \" . \$latestVersion)\
    \n        :log warning \"BackupAndUpdate: REBOOTING NOW\"\
    \n        /system package update install\
    \n        :return\
    \n\
    \n    } on-error={\
    \n        :log error \"BackupAndUpdate: Step 4 FAILED\"\
    \n    }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 5: RouterBOARD firmware update\
    \n# ============================================================\
    \n\
    \n:if (\$firmwareUpdateNeeded = true) do={\
    \n    :do {\
    \n        :log info \"BackupAndUpdate: Step 5 start - firmware update\"\
    \n\
    \n        :foreach schedulerId in=[/system scheduler find name=\$rebootSchedulerName] do={\
    \n            /system scheduler remove \$schedulerId\
    \n        }\
    \n\
    \n        /system scheduler add \\\
    \n            name=\$rebootSchedulerName \\\
    \n            start-time=startup \\\
    \n            interval=0 \\\
    \n            on-event=\":delay 3m; /system script run BackupAndUpdate\" \\\
    \n            policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon\
    \n\
    \n        :log info (\"BackupAndUpdate: upgrading firmware \" . \$currentFirmware . \" -> \" . \$upgradeFirmware)\
    \n        /system routerboard upgrade\
    \n\
    \n        :delay 5s\
    \n\
    \n        :log warning \"BackupAndUpdate: REBOOTING NOW\"\
    \n        /system reboot\
    \n        :return\
    \n\
    \n    } on-error={\
    \n        :log error \"BackupAndUpdate: Step 5 FAILED\"\
    \n    }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 6: Cleanup\
    \n# ============================================================\
    \n\
    \n:log info \"BackupAndUpdate: Step 6 - nothing to update or update aborted\"\
    \n\
    \n:foreach schedulerId in=[/system scheduler find name=\$rebootSchedulerName] do={\
    \n    /system scheduler remove \$schedulerId\
    \n}\
    \n\
    \n:log info \"BackupAndUpdate: === SCRIPT FINISHED ===\""
