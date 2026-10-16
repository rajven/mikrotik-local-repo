/system script
add dont-require-permissions=no name=BKPUPD-UPDATER policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source="# ============================================================\
    \n# BackupAndUpdate Updater (ROS6/ROS7 compatible, HTTPS)\
    \n# ============================================================\
    \n\
    \n:local scriptName \"BackupAndUpdate\"\
    \n:local scriptNameOld \"BackupAndUpdate.old\"\
    \n:local MyName \"BKPUPD-UPDATER\"\
    \n:local serverName \"http://SERVER_NAME\"\
    \n:local scriptBase (\$serverName . \"/routeros\")\
    \n:local md5Url (\$scriptBase . \"/BackupAndUpdate.md5\")\
    \n:local scriptUrl (\$scriptBase . \"/BackupAndUpdate.rsc\")\
    \n:local CAUrl (\$serverName . \"/fullchain.pem\")\
    \n:local CACertName \"globalSignCA.crt\"\
    \n:local tempMd5File \"updater-md5.txt\"\
    \n:local tempScriptFile \"updater-script.rsc\"\
    \n\
    \n:log info (\"BKPUPD-UPDATER: === UPDATER STARTED ===\")\
    \n\
    \n# ============================================================\
    \n# Step 1: Detect RouterOS version for HTTPS syntax\
    \n# ============================================================\
    \n\
    \n:local rosVersion [/system resource get version]\
    \n:local majorVersion [:pick \$rosVersion 0 1]\
    \n:global isRos7 (\$majorVersion = \"7\")\
    \n\
    \n:if (\$isRos7 = true) do={\
    \n    :log info \"BKPUPD-UPDATER: ROS 7 detected\"\
    \n} else={\
    \n    :log info \"BKPUPD-UPDATER: ROS 6 detected\"\
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
    \n    :global isRos7\
    \n\
    \n    # Determine if HTTPS is used\
    \n    :local isHttps false\
    \n    :local httpMode http\
    \n    :if ([:pick \$url 0 5] = \"https\") do={\
    \n        :set isHttps true\
    \n        :set httpMode https\
    \n    }\
    \n\
    \n    :if (\$isRos7 = false) do={\
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
    \n# Step 2: Download MD5 hash from server\
    \n# ============================================================\
    \n\
    \n:local serverMd5 \"\"\
    \n\
    \n:do {\
    \n    :log info (\"BKPUPD-UPDATER: fetching MD5 from \" . \$md5Url)\
    \n\
    \n    :foreach fileId in=[/file find name=\$tempMd5File] do={\
    \n        /file remove \$fileId\
    \n    }\
    \n\
    \n    \$fetchUrl \$md5Url \$tempMd5File \$CAUrl \$CACertName\
    \n    :delay 2s\
    \n\
    \n    :local fileId [/file find name=\$tempMd5File]\
    \n    :if ([:len \$fileId] > 0) do={\
    \n        :set serverMd5 [/file get \$fileId contents]\
    \n        :set serverMd5 [:pick \$serverMd5 0 32]\
    \n        /file remove \$fileId\
    \n        :log info (\"BKPUPD-UPDATER: server MD5 = \" . \$serverMd5)\
    \n    } else={\
    \n        :log error \"BKPUPD-UPDATER: failed to read MD5 file\"\
    \n    }\
    \n} on-error={\
    \n    :log error \"BKPUPD-UPDATER: failed to download MD5 (server unreachable or HTTPS error\?)\"\
    \n}\
    \n\
    \n:if (\$serverMd5 = \"\") do={\
    \n    :log error \"BKPUPD-UPDATER: no valid MD5 received - aborting\"\
    \n    :error \"No MD5\"\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 3: Read current MD5 from the main script's comment\
    \n# ============================================================\
    \n\
    \n:local currentMd5 \"\"\
    \n\
    \n:do {\
    \n    :set currentMd5 [/system script get \$MyName comment]\
    \n    :if ([:len \$currentMd5] > 0) do={\
    \n        :log info (\"BKPUPD-UPDATER: current MD5 = \" . \$currentMd5)\
    \n    } else={\
    \n        :log info \"BKPUPD-UPDATER: no current MD5 in script comment (first run\?)\"\
    \n    }\
    \n} on-error={\
    \n    :log warning \"BKPUPD-UPDATER: failed to read script comment\"\
    \n}\
    \n\
    \n# ============================================================\
    \n# Step 4: Compare hashes and update if needed\
    \n# ============================================================\
    \n\
    \n:if (\$serverMd5 != \$currentMd5) do={\
    \n    :log info \"BKPUPD-UPDATER: MD5 mismatch - updating script\"\
    \n    :do {\
    \n        :log info (\"BKPUPD-UPDATER: Rename current script to: \".\$scriptNameOld)\
    \n        /system script set [find name=\$scriptName] name=\$scriptNameOld\
    \n        }\
    \n\
    \n    :do {\
    \n        :foreach fileId in=[/file find name=\$tempScriptFile] do={\
    \n            /file remove \$fileId\
    \n        }\
    \n\
    \n        :log info (\"BKPUPD-UPDATER: downloading script from \" . \$scriptUrl)\
    \n        \$fetchUrl \$scriptUrl \$tempScriptFile \$CAUrl \$CACertName\
    \n        :delay 2s\
    \n\
    \n        :local fileId [/file find name=\$tempScriptFile]\
    \n        :if ([:len \$fileId] = 0) do={\
    \n            :log error \"BKPUPD-UPDATER: failed to download script file\"\
    \n            :error \"Download failed\"\
    \n        }\
    \n\
    \n        :log info \"BKPUPD-UPDATER: importing new script\"\
    \n        /import file=\$tempScriptFile\
    \n        :delay 1s\
    \n\
    \n        # Persist new MD5 in the main script's comment\
    \n        /system script set \$MyName comment=\$serverMd5\
    \n        :log info (\"BKPUPD-UPDATER: script updated successfully, new MD5 = \" . \$serverMd5)\
    \n\
    \n        # Cleanup temp file\
    \n        :foreach fileId in=[/file find name=\$tempScriptFile] do={\
    \n            /file remove \$fileId\
    \n        }\
    \n    :do {\
    \n        :log info (\"BKPUPD-UPDATER: Remove old script \".\$scriptNameOld)\
    \n        /system script remove [ find name=\$scriptNameOld ]\
    \n        }\
    \n    } on-error={\
    \n        :log error \"BKPUPD-UPDATER: script update FAILED\"\
    \n        :foreach fileId in=[/file find name=\$tempScriptFile] do={\
    \n            /file remove \$fileId\
    \n        }\
    \n       :do {\
    \n           :log info (\"BKPUPD-UPDATER: Restore old script \".\$scriptName)\
    \n           /system script set [find name=\$scriptNameOld] name=\$scriptName\
    \n           }\
    \n    }\
    \n} else={\
    \n    :log info \"BKPUPD-UPDATER: script is up to date\"\
    \n}\
    \n\
    \n:log info \"BKPUPD-UPDATER: === UPDATER FINISHED ===\"\
    \n"
