/system script
add dont-require-permissions=no name=BackupAndUpdate policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source="# ============================================================\
    \n# BackupAndUpdate (ROS6/ROS7 compatible + Server Policy Check)\
    \n#\
    \n# reboot-safe + reboot-loop protection:\
    \n#  - flow control via flags (:return inside :do{} only exits block)\
    \n#  - reboot commands are the very last statements\
    \n#  - persistent failure counters in BKPUPD-DAILY comment: \"fw,os,osver\"\
    \n#    after \$maxTries consecutive failures the script STOPS initiating\
    \n#    reboots (manual reset: /system scheduler set BKPUPD-DAILY comment=\"\")\
    \n# ============================================================\
    \n\
    \n:local scriptName \"BackupAndUpdate\"\
    \n:local dailySchedulerName \"BKPUPD-DAILY\"\
    \n:local rebootSchedulerName \"BKPUPD-REBOOT\"\
    \n:local backupName \"auto-backup\"\
    \n:local backupPassword \"\"\
    \n:local backupPath \"\"\
    \n:local backupFullPath \"\"\
    \n:local flashAvailable false\
    \n\
    \n# Server URL for policy check\
    \n:local policyServerName \"http://SERVER_NAME\"\
    \n:local CAUrl (\$policyServerName . \"/fullchain.pem\")\
    \n:local CACertName \"globalSignCA.crt\"\
    \n:local policyCheckUrl (\$policyServerName . \"/routeros/force_update.php\")\
    \n\
    \n:local osUpdateNeeded false\
    \n:local firmwareUpdateNeeded false\
    \n:local routerboardAvailable false\
    \n:local currentVersion \"\"\
    \n:local latestVersion \"\"\
    \n\
    \n# ----- flow control flags -----\
    \n:local readyToInstall false\
    \n:local readyToReboot  false\
    \n:local backupFailed   false\
    \n\
    \n# ----- reboot-loop protection -----\
    \n:local maxTries 2\
    \n:local fwTries 0\
    \n:local osTries 0\
    \n:local osTriedVer \"\"\
    \n:local countersDirty false\
    \n\
    \n# Detect RouterOS version\
    \n:global rosVersion [/system resource get version]\
    \n:global majorVersion [:pick \$rosVersion 0 1]\
    \n:global isRos7 (\$majorVersion = \"7\")\
    \n:global isRos6 (\$majorVersion = \"6\")\
    \n\
    \n# Obtain the device model, serial number and firmware versions\
    \n:global rawModel [/system resource get board-name]\
    \n:global deviceSerial [/system routerboard get serial-number]\
    \n:global deviceName [/system identity get name]\
    \n:global currentFirmware [/system routerboard get current-firmware]\
    \n:global upgradeFirmware [/system routerboard get upgrade-firmware]\
    \n\
    \n# Deterministic delay of 0\E2\80\93599s based on serial number\
    \n:local seed 0\
    \n:for i from=0 to=([:len \$deviceSerial] - 1) do={\
    \n    :set seed ((\$seed * 31) + [:tonum [:pick \$deviceSerial \$i (\$i + 1)]])\
    \n}\
    \n:local delaySec (\$seed % 600)\
    \n:log info (\"BackupAndUpdate: scheduled delay \" . \$delaySec . \"s for serial \" . \$deviceSerial)\
    \n:delay (\$delaySec . \"s\")\
    \n\
    \n:log info (\"BackupAndUpdate: === SCRIPT STARTED ===\")\
    \n\
    \n# ============================================================\
    \n# Step 1: Daily scheduler\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info (\"BackupAndUpdate: Step 1 start\")\
    \n\
    \n    :if ([:len [/system scheduler find name=\$dailySchedulerName]] = 0) do={\
    \n        /system scheduler add \\\
    \n            name=\$dailySchedulerName \\\
    \n            start-time=05:00:00 \\\
    \n            interval=1d \\\
    \n            on-event=\$scriptName \\\
    \n            policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon\
    \n        :log info (\"BackupAndUpdate: daily scheduler created\")\
    \n    } else={\
    \n        :log info (\"BackupAndUpdate: daily scheduler exists\")\
    \n    }\
    \n\
    \n    :log info (\"BackupAndUpdate: Step 1 OK\")\
    \n} on-error={\
    \n    :log error (\"BackupAndUpdate: Step 1 FAILED\")\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 1.5: Read persistent failure counters from scheduler comment\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :local cmt [/system scheduler get \$dailySchedulerName comment]\
    \n    :if ([:len \$cmt] > 0) do={\
    \n        :local p1 [:find \$cmt \",\"]\
    \n        :set fwTries [:tonum [:pick \$cmt 0 \$p1]]\
    \n        :local rest [:pick \$cmt (\$p1 + 1) [:len \$cmt]]\
    \n        :local p2 [:find \$rest \",\"]\
    \n        :set osTries [:tonum [:pick \$rest 0 \$p2]]\
    \n        :set osTriedVer [:pick \$rest (\$p2 + 1) [:len \$rest]]\
    \n    }\
    \n    :log info (\"BackupAndUpdate: counters fw=\" . \$fwTries . \" os=\" . \$osTries . \" osver=\" . \$osTriedVer)\
    \n} on-error={\
    \n    :set fwTries 0\
    \n    :set osTries 0\
    \n    :set osTriedVer \"\"\
    \n    :log info (\"BackupAndUpdate: counters empty or malformed - starting from zero\")\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 2: Check RouterOS updates\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info (\"BackupAndUpdate: Step 2 start\")\
    \n\
    \n    :local rosVersion [/system resource get version]\
    \n    :local majorVersion [:pick \$rosVersion 0 1]\
    \n\
    \n    :if (\$majorVersion = \"7\") do={\
    \n        :log info (\"BackupAndUpdate: ROS 7 detected -> executing mode=http\")\
    \n        :local cmd \"/system package update set mode=http\"\
    \n        :execute \$cmd\
    \n        :delay 1s\
    \n    } else={\
    \n        :log info (\"BackupAndUpdate: mode=http skipped (ROS6)\")\
    \n    }\
    \n\
    \n    /system package update check-for-updates\
    \n    :log info (\"BackupAndUpdate: check started, waiting 15s\")\
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
    \n        :log info (\"BackupAndUpdate: update IS available\")\
    \n    } else={\
    \n        :log info (\"BackupAndUpdate: no update available\")\
    \n    }\
    \n\
    \n    # ----- OS counter maintenance -----\
    \n    :if (\$osUpdateNeeded = true) do={\
    \n        # Target version changed since last attempts -> legitimate retry\
    \n        :if (\$latestVersion != \$osTriedVer) do={\
    \n            :if (\$osTries > 0) do={\
    \n                :log info (\"BackupAndUpdate: new target \" . \$latestVersion . \" (was \" . \$osTriedVer . \") - resetting OS counter\")\
    \n            }\
    \n            :set osTries 0\
    \n            :set osTriedVer \"\"\
    \n            :set countersDirty true\
    \n        }\
    \n    } else={\
    \n        :if (\$osTries > 0) do={\
    \n            :log info (\"BackupAndUpdate: OS is up to date - resetting OS counter\")\
    \n            :set osTries 0\
    \n            :set osTriedVer \"\"\
    \n            :set countersDirty true\
    \n        }\
    \n    }\
    \n\
    \n    :log info (\"BackupAndUpdate: Step 2 OK\")\
    \n} on-error={\
    \n    :log error (\"BackupAndUpdate: Step 2 FAILED\")\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 3: Check RouterBOARD firmware\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info (\"BackupAndUpdate: Step 3 start\")\
    \n    :log info (\"BackupAndUpdate: current-fw=\" . \$currentFirmware)\
    \n    :log info (\"BackupAndUpdate: upgrade-fw=\" . \$upgradeFirmware)\
    \n\
    \n    :set routerboardAvailable true\
    \n\
    \n    :if (\$currentFirmware != \$upgradeFirmware) do={\
    \n        :set firmwareUpdateNeeded true\
    \n        :log info (\"BackupAndUpdate: firmware update needed\")\
    \n    } else={\
    \n        :log info (\"BackupAndUpdate: firmware up to date\")\
    \n        # ----- firmware counter maintenance -----\
    \n        :if (\$fwTries > 0) do={\
    \n            :log info (\"BackupAndUpdate: firmware in sync - resetting FW counter\")\
    \n            :set fwTries 0\
    \n            :set countersDirty true\
    \n        }\
    \n    }\
    \n\
    \n    :log info (\"BackupAndUpdate: Step 3 OK\")\
    \n} on-error={\
    \n    :log error (\"BackupAndUpdate: Step 3 FAILED\")\
    \n}\
    \n\
    \n# Persist counter resets (if any)\
    \n:if (\$countersDirty = true) do={\
    \n    :do {\
    \n        /system scheduler set \$dailySchedulerName comment=(\$fwTries . \",\" . \$osTries . \",\" . \$osTriedVer)\
    \n        :set countersDirty false\
    \n    } on-error={\
    \n        :log error (\"BackupAndUpdate: failed to persist counters\")\
    \n    }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Helper: fetch with HTTPS (version-aware)\
    \n# For ROS6: auto-imports CA certificate from server if missing\
    \n# ============================================================\
    \n\
    \n:local fetchUrl do={\
    \n    :local url \$1\
    \n    :local dst \$2\
    \n    :local urlCA \$3\
    \n    :local caName \$4\
    \n    :global isRos6\
    \n\
    \n    # Determine if HTTPS is used\
    \n    :local isHttps false\
    \n    :local httpMode http\
    \n    :if ([:pick \$url 0 5] = \"https\") do={\
    \n        :set isHttps true\
    \n        :set httpMode https\
    \n    }\
    \n\
    \n    :if (\$isRos6 = true) do={\
    \n        :if (\$isHttps = true) do={\
    \n            # ROS6: check if CA certificate exists\
    \n            :local certExists false\
    \n            :foreach certId in=[/certificate find where name ~\"^\$caName\" ] do={\
    \n                :set certExists true\
    \n            }\
    \n            :if (\$certExists = false) do={\
    \n                :log info (\"BKPUPD-UPDATER: CA certificate \" . \$caName . \" not found - downloading from server \" . \$urlCA)\
    \n                :do {\
    \n                    # Remove old fullchain.pem if exists \
    \n                    /file remove [ find name=\"fullchain.pem\"]\
    \n                    # Download CA certificate (insecure, no cert yet)\
    \n                    /tool fetch url=\$urlCA mode=https check-certificate=no dst-path=fullchain.pem\
    \n                    :delay 2s\
    \n                    # Verify file exists\
    \n                    :local fileId [/file find name=\"fullchain.pem\"]\
    \n                    :if ([:len \$fileId] = 0) do={\
    \n                        :log error \"BKPUPD-UPDATER: failed to download CA certificate\"\
    \n                        :error \"CA download failed\"\
    \n                    }\
    \n                    # Import certificate\
    \n                    /certificate import file-name=fullchain.pem passphrase=\"\" name=\$caName\
    \n                    :delay 1s\
    \n                    :log info (\"BKPUPD-UPDATER: CA certificate \" . \$caName . \" imported successfully\")\
    \n                    # Cleanup temp file\
    \n                    /file remove [ find name=\"fullchain.pem\"]\
    \n                } on-error={\
    \n                    :log error \"BKPUPD-UPDATER: CA certificate setup FAILED\"\
    \n                    /file remove [ find name=\"fullchain.pem\"]\
    \n                    :error \"CA setup failed\"\
    \n                }\
    \n            }\
    \n        }\
    \n      }\
    \n\
    \n  :if (\$isHttps = true) do={\
    \n            #disable crl\
    \n            /certificate settings set crl-download=no crl-use=no\
    \n            # Now fetch with certificate validation\
    \n            /tool fetch url=\$url mode=https check-certificate=yes dst-path=\$dst\
    \n            } else={\
    \n            # Now fetch by http\
    \n            /tool fetch url=\$url mode=http dst-path=\$dst\
    \n            }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Helper: URL-encode a string (percent-encoding)\
    \n# Usage: :local encoded [\$urlEncode \"some string\"]\
    \n# ============================================================\
    \n:local urlEncode do={\
    \n    :local input \$1\
    \n    :local result \"\"\
    \n    :local enc \"\"\
    \n    :for i from=0 to=([:len \$input] - 1) do={\
    \n        :local char [:pick \$input \$i (\$i + 1)]\
    \n        :set enc \$char\
    \n        :if (\$char = \"%\") do={ :set enc \"%25\" }\
    \n        :if (\$char = \" \") do={ :set enc \"%20\" }\
    \n        :if (\$char = \"&\") do={ :set enc \"%26\" }\
    \n        :if (\$char = \"+\") do={ :set enc \"%2B\" }\
    \n        :if (\$char = \"#\") do={ :set enc \"%23\" }\
    \n        :if (\$char = \"=\") do={ :set enc \"%3D\" }\
    \n        :if (\$char = \"\?\") do={ :set enc \"%3F\" }\
    \n        :if (\$char = \";\") do={ :set enc \"%3B\" }\
    \n        :if (\$char = \"/\") do={ :set enc \"%2F\" }\
    \n        :if (\$char = \":\") do={ :set enc \"%3A\" }\
    \n        :if (\$char = \"@\") do={ :set enc \"%40\" }\
    \n        :if (\$char = \"'\") do={ :set enc \"%27\" }\
    \n        :if (\$char = \"\\\"\") do={ :set enc \"%22\" }\
    \n        :if (\$char = \"<\") do={ :set enc \"%3C\" }\
    \n        :if (\$char = \">\") do={ :set enc \"%3E\" }\
    \n        :set result (\$result . \$enc)\
    \n    }\
    \n    :return \$result\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 3.5: ALWAYS report device state to server\
    \n#           (+ policy check if RouterOS update is pending)\
    \n# ============================================================\
    \n\
    \n:do {\
    \n    :log info \"BackupAndUpdate: Step 3.5 start - reporting state to server\"\
    \n\
    \n    :local safeModel [\$urlEncode \$rawModel]\
    \n    :local safeName  [\$urlEncode \$deviceName]\
    \n\
    \n    :local reportVersion \$latestVersion\
    \n    :if ([:len \$reportVersion] = 0) do={ :set reportVersion \$currentVersion }\
    \n    :if ([:len \$reportVersion] = 0) do={ :set reportVersion \"unknown\" }\
    \n\
    \n    :local checkUrl (\$policyCheckUrl . \"\?new_version=\" . \$reportVersion . \"&model=\" . \$safeModel . \"&serial=\" . \$deviceSerial . \"&name=\" . \$safeName . \"&currentFirmware=\" . \$currentFirmware . \"&upgradeFirmware=\" . \$upgradeF\
    irmware)\
    \n    :local checkFile \"force_update_check.txt\"\
    \n    :local serverResponse \"DISABLED\"\
    \n\
    \n    :foreach fileId in=[/file find name=\$checkFile] do={\
    \n        /file remove \$fileId\
    \n    }\
    \n\
    \n    :log info (\"BackupAndUpdate: fetching policy from: \" . \$checkUrl)\
    \n    \$fetchUrl \$checkUrl \$checkFile \$CAUrl \$CACertName\
    \n    :delay 5s\
    \n\
    \n    :local fileId [/file find name=\$checkFile]\
    \n    :if ([:len \$fileId] > 0) do={\
    \n        :set serverResponse [/file get \$fileId contents]\
    \n        /file remove \$fileId\
    \n    }\
    \n\
    \n    :log info (\"BackupAndUpdate: server response for v\" . \$reportVersion . \": \" . \$serverResponse)\
    \n\
    \n    :if (\$osUpdateNeeded = true) do={\
    \n        :if (\$serverResponse != \"ENABLED\") do={\
    \n            :log warning (\"BackupAndUpdate: update NOT authorized by server. Aborting RouterOS update.\")\
    \n            :set osUpdateNeeded false\
    \n        } else={\
    \n            :log info (\"BackupAndUpdate: update authorized by server.\")\
    \n        }\
    \n    }\
    \n\
    \n    :log info (\"BackupAndUpdate: Step 3.5 OK\")\
    \n} on-error={\
    \n    :log error (\"BackupAndUpdate: Step 3.5 FAILED (server unreachable or fetch error)\")\
    \n    :set osUpdateNeeded false\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 4: RouterOS update PREPARATION (backup etc.)\
    \n#         Gated by OS failure counter to prevent reboot loops\
    \n# ============================================================\
    \n\
    \n:if ((\$osUpdateNeeded = true) && (\$osTries >= \$maxTries)) do={\
    \n    :log error (\"BackupAndUpdate: OS install failed \" . \$osTries . \" consecutive times - SKIPPING (reboot loop protection). Manual reset: /system scheduler set \" . \$dailySchedulerName . \" comment=\\\"\\\"\")\
    \n}\
    \n\
    \n:if ((\$osUpdateNeeded = true) && (\$osTries < \$maxTries)) do={\
    \n    :do {\
    \n        :log info (\"BackupAndUpdate: Step 4 start - RouterOS update preparation\")\
    \n\
    \n        # Reboot scheduler FIRST - safety net in case script dies mid-way\
    \n        :if ([:len [/system scheduler find name=\$rebootSchedulerName]] = 0) do={\
    \n            /system scheduler add \\\
    \n                name=\$rebootSchedulerName \\\
    \n                start-time=startup \\\
    \n                interval=0 \\\
    \n                on-event=\":delay 3m; /system script run BackupAndUpdate\" \\\
    \n                policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon\
    \n            :log info (\"BackupAndUpdate: reboot scheduler created\")\
    \n        }\
    \n\
    \n        # Detect flash directory\
    \n        :do {\
    \n            :local test [/file get flash name]\
    \n            :set flashAvailable true\
    \n            :set backupPath \"flash/\"\
    \n            :log info (\"BackupAndUpdate: flash directory is available\")\
    \n        } on-error={\
    \n            :set flashAvailable false\
    \n            :set backupPath \"\"\
    \n            :log info (\"BackupAndUpdate: flash directory not available, using root\")\
    \n        }\
    \n\
    \n        # Generate backup name from Serial Number, Version and Date\
    \n        :do {\
    \n            :local serial [/system routerboard get serial-number]\
    \n\
    \n            :local dateRaw [/system clock get date]\
    \n\
    \n            :local year \"\"\
    \n            :local monthNum \"\"\
    \n            :local day \"\"\
    \n\
    \n            :if ([:pick \$dateRaw 0 1] ~ \"[0-9]\") do={\
    \n                :set year     [:pick \$dateRaw 0 4]\
    \n                :set monthNum [:pick \$dateRaw 5 7]\
    \n                :set day      [:pick \$dateRaw 8 10]\
    \n            } else={\
    \n                :set day  [:pick \$dateRaw 4 6]\
    \n                :set year [:pick \$dateRaw 7 11]\
    \n\
    \n                :local monthStr [:pick \$dateRaw 0 3]\
    \n                :set monthNum \"01\"\
    \n                :if (\$monthStr = \"jan\") do={ :set monthNum \"01\" }\
    \n                :if (\$monthStr = \"feb\") do={ :set monthNum \"02\" }\
    \n                :if (\$monthStr = \"mar\") do={ :set monthNum \"03\" }\
    \n                :if (\$monthStr = \"apr\") do={ :set monthNum \"04\" }\
    \n                :if (\$monthStr = \"may\") do={ :set monthNum \"05\" }\
    \n                :if (\$monthStr = \"jun\") do={ :set monthNum \"06\" }\
    \n                :if (\$monthStr = \"jul\") do={ :set monthNum \"07\" }\
    \n                :if (\$monthStr = \"aug\") do={ :set monthNum \"08\" }\
    \n                :if (\$monthStr = \"sep\") do={ :set monthNum \"09\" }\
    \n                :if (\$monthStr = \"oct\") do={ :set monthNum \"10\" }\
    \n                :if (\$monthStr = \"nov\") do={ :set monthNum \"11\" }\
    \n                :if (\$monthStr = \"dec\") do={ :set monthNum \"12\" }\
    \n            }\
    \n\
    \n            :local safeVersion \"unknown\"\
    \n            :if ([:len \$currentVersion] > 0) do={\
    \n                :set safeVersion \$currentVersion\
    \n            }\
    \n\
    \n            :set backupName ( \"auto-backup-\" . \$serial . \"-\" . \$safeVersion . \"-\" . \$year . \"-\" . \$monthNum . \"-\" . \$day)\
    \n            :set backupFullPath (\$backupPath . \$backupName)\
    \n            :log info (\"BackupAndUpdate: backup full name: \" . \$backupFullPath)\
    \n        } on-error={\
    \n            :log error (\"BackupAndUpdate: failed to generate backup name\")\
    \n            :set backupFailed true\
    \n        }\
    \n\
    \n        :if (\$backupFailed = false) do={\
    \n            # Remove old backups\
    \n            :local prefixLen ([:len \$backupPath] + 12)\
    \n            :local prefix (\$backupPath . \"auto-backup-\")\
    \n\
    \n            :foreach fileId in=[/file find] do={\
    \n                :local fileName [/file get \$fileId name]\
    \n                :local fileLen [:len \$fileName]\
    \n\
    \n                :if (\$fileLen >= \$prefixLen) do={\
    \n                    :if ([:pick \$fileName 0 \$prefixLen] = \$prefix) do={\
    \n                        :if (([:pick \$fileName (\$fileLen - 7) \$fileLen] = \".backup\") || \\\
    \n                             ([:pick \$fileName (\$fileLen - 4) \$fileLen] = \".rsc\")) do={\
    \n                            /file remove \$fileId\
    \n                            :log info (\"BackupAndUpdate: removed old file: \" . \$fileName)\
    \n                        }\
    \n                    }\
    \n                }\
    \n            }\
    \n\
    \n            # Binary backup\
    \n            :log info (\"BackupAndUpdate: creating binary backup\")\
    \n            :if (\$backupPassword = \"\") do={\
    \n                /system backup save dont-encrypt=yes name=\$backupFullPath\
    \n            } else={\
    \n                /system backup save password=\$backupPassword name=\$backupFullPath\
    \n            }\
    \n\
    \n            # Config export\
    \n            :export file=\$backupFullPath\
    \n\
    \n            # Wait for files\
    \n            :local backupReady false\
    \n            :local backupWait 0\
    \n\
    \n            :while ((\$backupReady = false) && (\$backupWait < 60)) do={\
    \n                :delay 1s\
    \n                :if (([:len [/file find name=(\$backupFullPath . \".backup\")]] > 0) && \\\
    \n                     ([:len [/file find name=(\$backupFullPath . \".rsc\")]] > 0)) do={\
    \n                    :set backupReady true\
    \n                }\
    \n                :set backupWait (\$backupWait + 1)\
    \n            }\
    \n\
    \n            :if (\$backupReady = false) do={\
    \n                :log error (\"BackupAndUpdate: backup timeout after 60s - aborting update\")\
    \n                :set backupFailed true\
    \n            } else={\
    \n                :log info (\"BackupAndUpdate: backup files ready in \" . \$backupWait . \"s\")\
    \n\
    \n                # Count this install attempt BEFORE issuing install\
    \n                :set osTries (\$osTries + 1)\
    \n                :set osTriedVer \$latestVersion\
    \n                :do {\
    \n                    /system scheduler set \$dailySchedulerName comment=(\$fwTries . \",\" . \$osTries . \",\" . \$osTriedVer)\
    \n                } on-error={\
    \n                    :log error (\"BackupAndUpdate: failed to persist OS counter\")\
    \n                }\
    \n\
    \n                :set readyToInstall true\
    \n            }\
    \n        }\
    \n\
    \n    } on-error={\
    \n        :log error (\"BackupAndUpdate: Step 4 FAILED\")\
    \n        :set backupFailed true\
    \n        :set readyToInstall false\
    \n    }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 5: RouterBOARD firmware update (flash only, NO reboot here)\
    \n#         Gated by FW failure counter to prevent reboot loops\
    \n# ============================================================\
    \n\
    \n:if ((\$firmwareUpdateNeeded = true) && (\$fwTries >= \$maxTries)) do={\
    \n    :log error (\"BackupAndUpdate: firmware upgrade failed \" . \$fwTries . \" consecutive times - SKIPPING (reboot loop protection). Manual reset: /system scheduler set \" . \$dailySchedulerName . \" comment=\\\"\\\"\")\
    \n}\
    \n\
    \n:if ((\$firmwareUpdateNeeded = true) && (\$readyToInstall = false) && (\$backupFailed = false) && (\$fwTries < \$maxTries)) do={\
    \n    :do {\
    \n        :log info (\"BackupAndUpdate: Step 5 start - firmware update\")\
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
    \n        # Count this attempt BEFORE flashing\
    \n        :set fwTries (\$fwTries + 1)\
    \n        :do {\
    \n            /system scheduler set \$dailySchedulerName comment=(\$fwTries . \",\" . \$osTries . \",\" . \$osTriedVer)\
    \n        } on-error={\
    \n            :log error (\"BackupAndUpdate: failed to persist FW counter\")\
    \n        }\
    \n\
    \n        :log info (\"BackupAndUpdate: upgrading firmware \" . \$currentFirmware . \" -> \" . \$upgradeFirmware . \" (attempt \" . \$fwTries . \"/\" . \$maxTries . \")\")\
    \n        /system routerboard upgrade\
    \n\
    \n        :delay 5s\
    \n\
    \n        :set readyToReboot true\
    \n\
    \n    } on-error={\
    \n        :log error (\"BackupAndUpdate: Step 5 FAILED\")\
    \n        :set readyToReboot false\
    \n    }\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 6: Cleanup - ONLY when no reboot is pending.\
    \n#         Reboot scheduler is removed ONLY if firmware is in sync.\
    \n# ============================================================\
    \n\
    \n:if ((\$readyToInstall = false) && (\$readyToReboot = false)) do={\
    \n    :log info (\"BackupAndUpdate: Step 6 - cleanup\")\
    \n\
    \n    :if (\$currentFirmware = \$upgradeFirmware) do={\
    \n        :foreach schedulerId in=[/system scheduler find name=\$rebootSchedulerName] do={\
    \n            /system scheduler remove \$schedulerId\
    \n        }\
    \n        :log info (\"BackupAndUpdate: firmware in sync - reboot scheduler removed\")\
    \n    } else={\
    \n        :log warning (\"BackupAndUpdate: firmware NOT in sync (\" . \$currentFirmware . \" != \" . \$upgradeFirmware . \") - keeping reboot scheduler\")\
    \n    }\
    \n} else={\
    \n    :log info (\"BackupAndUpdate: Step 6 skipped - reboot pending, cleanup untouched\")\
    \n}\
    \n\
    \n:log info (\"BackupAndUpdate: === SCRIPT FINISHED ===\")\
    \n\
    \n# ============================================================\
    \n# FINAL: reboot-inducing commands are the VERY LAST statements.\
    \n# ============================================================\
    \n\
    \n:if (\$readyToInstall = true) do={\
    \n    :log info (\"BackupAndUpdate: installing RouterOS \" . \$latestVersion . \" (attempt \" . \$osTries . \"/\" . \$maxTries . \")\")\
    \n    :log warning (\"BackupAndUpdate: REBOOTING NOW (OS install)\")\
    \n    /system package update install\
    \n}\
    \n\
    \n:if (\$readyToReboot = true) do={\
    \n    :log warning (\"BackupAndUpdate: REBOOTING NOW (firmware activation, attempt \" . \$fwTries . \"/\" . \$maxTries . \")\")\
    \n    /system reboot\
    \n}\
    \n"
