# mikrotik-local-repo

Get packages from mikrotik repo to you local repo

### Configure architecture & versions

Change in script:

#You local repo path 
TARGET_DIR="/mnt/mirror/routeros"

#6 - stable release 

#6fix - LTS release

versions6=("6" "6fix")

#7 - stable

#7fix - LTS (not available now)

versions7=("7")

#select needed architecture

firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

### Share TARGET_DIR by you web-server

Need share dir without "/routeros". That is, the /routeros directory should be at the root of the site!

### Create symlink's in target directory

touch LATEST.6fix
touch LATEST.6

ln -s LATEST.6fix NEWEST6.long-term
ln -s LATEST.6 NEWEST6.stable

### Change at our mikrotik device dns names for download packages to you web-server

/ip dns static add address=192.168.0.1 name=download.mikrotik.com

/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
