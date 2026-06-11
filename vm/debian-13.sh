source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info {
  clear
  cat <<"EOF"
    ____       __    _                ________    _    ____  ___
   / __ \___  / /_  (_)___ _____     <  /__  /   | |  / /  |/  /
  / / / / _ \/ __ \/ / __ `/ __ \    / / /_ <    | | / / /|_/ /
 / /_/ /  __/ /_/ / / /_/ / / / /   / /___/ /    | |/ / /  / /
/_____/\___/_.___/_/\__,_/_/ /_/   /_//____/     |___/_/  /_/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="debian-13-vm"
var_os="debian"
var_version="13"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
CLOUD="${TAB}☁️${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${exit_code}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  local exit_code=$?
  popd >/dev/null
  if [[ "${POST_TO_API_DONE:-}" == "true" && "${POST_UPDATE_DONE:-}" != "true" ]]; then
    if [[ $exit_code -eq 0 ]]; then
      post_update_to_api "done" "none"
    else
      post_update_to_api "failed" "$exit_code"
    fi
  fi
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Debian 13 VM" --yesno "This will create a New Debian 13 VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x, 9.0 and 9.2
pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  # Check for Proxmox VE 8.x: allow 8.0–8.9
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 105
    fi
    return 0
  fi

  # Check for Proxmox VE 9.x: allow 9.0 and 9.2
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 2)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 9.0 – 9.2"
      exit 105
    fi
    return 0
  fi

  # All other unsupported versions
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0 – 9.2"
  exit 105
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
    echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function select_cloud_init() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n- User accounts and passwords\n- SSH keys\n- Network settings (DHCP/Static)\n- DNS configuration\n\nYou can also configure these settings later in Proxmox UI.\n\nNote: Without Cloud-Init, the nocloud image will be used with console auto-login." --defaultno 18 68); then
    CLOUD_INIT="yes"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    CLOUD_INIT="no"
    echo -e "${CLOUD}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_SIZE="8G"
  DISK_CACHE=""
  HN="debian"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  CIUSER="debian"
  CIPASSWORD=""
  CI_FORCE_SUDO="no"
  NETPLAN_IP=""
  NETPLAN_GW=""
  START_VM="yes"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 debian --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="debian"
    else
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ -z "$HN" ]; then HN="debian"; fi
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  else
    exit-script
  fi

  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"

  select_cloud_init

  if [ "$CLOUD_INIT" == "yes" ]; then
    while true; do
      if CIUSER=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Cloud-Init Username" 8 58 debian --title "CLOUD-INIT USER" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$CIUSER" ]; then CIUSER="debian"; fi
        if [[ "$CIUSER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
          echo -e "${INFO}${BOLD}${DGN}Cloud-Init User: ${BGN}$CIUSER${CL}"
          break
        fi
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Username must start with a lowercase letter or underscore, and may only contain lowercase letters, numbers, hyphen, or underscore." 9 58
      else
        exit-script
      fi
    done

    while true; do
      if CIPASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Enter Cloud-Init password for user '$CIUSER'" 8 58 --title "PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$CIPASSWORD" ]; then
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Password cannot be empty." 8 58
          continue
        fi
      else
        exit-script
      fi
      if CIPASSWORD_CONFIRM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Confirm Cloud-Init password" 8 58 --title "CONFIRM PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ "$CIPASSWORD" = "$CIPASSWORD_CONFIRM" ]; then
          echo -e "${INFO}${BOLD}${DGN}Cloud-Init Password: ${BGN}Set${CL}"
          break
        fi
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "PASSWORD MISMATCH" --msgbox "Passwords do not match. Please try again." 8 58
      else
        exit-script
      fi
    done
    CI_FORCE_SUDO="yes"

    if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "STATIC IP" --yesno "Configure a static IP address for this VM?\n\n(No = DHCP)" 10 62); then
      while true; do
        if NETPLAN_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Static IP Address (CIDR format)\ne.g., 192.168.1.100/24" 9 62 --title "STATIC IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
          if [[ "$NETPLAN_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then break; fi
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid format. Use: x.x.x.x/xx (e.g., 192.168.1.100/24)" 8 62
        else
          exit-script
        fi
      done
      while true; do
        if NETPLAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Default Gateway\ne.g., 192.168.1.1" 9 62 --title "GATEWAY" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
          if [[ "$NETPLAN_GW" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then break; fi
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid gateway. Use: x.x.x.x (e.g., 192.168.1.1)" 8 62
        else
          exit-script
        fi
      done
      echo -e "${GATEWAY}${BOLD}${DGN}Static IP: ${BGN}${NETPLAN_IP}${CL}"
      echo -e "${GATEWAY}${BOLD}${DGN}Gateway: ${BGN}${NETPLAN_GW}${CL}"
    else
      echo -e "${GATEWAY}${BOLD}${DGN}Network: ${BGN}DHCP${CL}"
    fi
  fi

  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 "$VMID" --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$MACH" = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 10, 20)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 10 or 10G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$DISK_CACHE" = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 debian --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="debian"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Invalid characters detected. Hostname has been adjusted to:\n\n  $HN" 10 58
      fi
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "KVM64 (Default)" ON \
    "1" "Host" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$CPU_TYPE1" = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  while true; do
    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$CORE_COUNT" ]; then CORE_COUNT="2"; fi
      if [[ "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer (e.g., 2)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 2048 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$RAM_SIZE" ]; then RAM_SIZE="2048"; fi
      if [[ "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM Size must be a positive integer in MiB (e.g., 2048)." 8 58
    else
      exit-script
    fi
  done

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$BRG" ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  while true; do
    if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 "$GEN_MAC" --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MAC1" ]; then
        MAC="$GEN_MAC"
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
        break
      fi
      if [[ "$MAC1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        MAC="$MAC1"
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid MAC address format. Use XX:XX:XX:XX:XX:XX (e.g., AA:BB:CC:DD:EE:FF)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan(leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VLAN1" ]; then
        VLAN1="Default"
        VLAN=""
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      if [[ "$VLAN1" =~ ^[0-9]+$ ]] && [ "$VLAN1" -ge 1 ] && [ "$VLAN1" -le 4094 ]; then
        VLAN=",tag=$VLAN1"
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "VLAN must be a number between 1 and 4094, or leave blank for default." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MTU1" ]; then
        MTU1="Default"
        MTU=""
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      if [[ "$MTU1" =~ ^[0-9]+$ ]] && [ "$MTU1" -ge 576 ] && [ "$MTU1" -le 65520 ]; then
        MTU=",mtu=$MTU1"
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "MTU Size must be a number between 576 and 65520, or leave blank for default." 8 58
    else
      exit-script
    fi
  done

  select_cloud_init

  CIUSER="debian"
  CIPASSWORD=""
  CI_FORCE_SUDO="no"
  NETPLAN_IP=""
  NETPLAN_GW=""

  if [ "$CLOUD_INIT" == "yes" ]; then
    while true; do
      if CIUSER=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Cloud-Init Username" 8 58 debian --title "CLOUD-INIT USER" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$CIUSER" ]; then CIUSER="debian"; fi
        if [[ "$CIUSER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
          echo -e "${INFO}${BOLD}${DGN}Cloud-Init User: ${BGN}$CIUSER${CL}"
          break
        fi
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Username must start with a lowercase letter or underscore, and may only contain lowercase letters, numbers, hyphen, or underscore." 9 58
      else
        exit-script
      fi
    done

    while true; do
      if CIPASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Enter Cloud-Init password for user '$CIUSER'" 8 58 --title "PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$CIPASSWORD" ]; then
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Password cannot be empty." 8 58
          continue
        fi
      else
        exit-script
      fi
      if CIPASSWORD_CONFIRM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Confirm Cloud-Init password" 8 58 --title "CONFIRM PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ "$CIPASSWORD" = "$CIPASSWORD_CONFIRM" ]; then
          echo -e "${INFO}${BOLD}${DGN}Cloud-Init Password: ${BGN}Set${CL}"
          break
        fi
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "PASSWORD MISMATCH" --msgbox "Passwords do not match. Please try again." 8 58
      else
        exit-script
      fi
    done
    CI_FORCE_SUDO="yes"

    if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "STATIC IP" --yesno "Configure a static IP address for this VM?\n\n(No = DHCP)" 10 62); then
      while true; do
        if NETPLAN_IP=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Static IP Address (CIDR format)\ne.g., 192.168.1.100/24" 9 62 --title "STATIC IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
          if [[ "$NETPLAN_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then break; fi
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid format. Use: x.x.x.x/xx (e.g., 192.168.1.100/24)" 8 62
        else
          exit-script
        fi
      done
      while true; do
        if NETPLAN_GW=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Default Gateway\ne.g., 192.168.1.1" 9 62 --title "GATEWAY" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
          if [[ "$NETPLAN_GW" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then break; fi
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid gateway. Use: x.x.x.x (e.g., 192.168.1.1)" 8 62
        else
          exit-script
        fi
      done
      echo -e "${GATEWAY}${BOLD}${DGN}Static IP: ${BGN}${NETPLAN_IP}${CL}"
      echo -e "${GATEWAY}${BOLD}${DGN}Gateway: ${BGN}${NETPLAN_GW}${CL}"
    else
      echo -e "${GATEWAY}${BOLD}${DGN}Network: ${BGN}DHCP${CL}"
    fi
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Debian 13 VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Debian 13 VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function create_cloudinit_user_config() {
  CICUSTOM=""
  if [ "${CI_FORCE_SUDO:-no}" != "yes" ]; then
    return
  fi

  local snippet_storage snippet_file snippet_ref snippet_path password_hash
  snippet_storage=$(pvesm status -content snippets 2>/dev/null | awk 'NR>1 {print $1; exit}')
  if [ -z "$snippet_storage" ]; then
    echo -e "${INFO}${BOLD}${YW}No snippets storage found; using Proxmox default Cloud-Init user handling${CL}"
    return
  fi

  snippet_file="${VMID}-debian13-user.yaml"
  snippet_ref="${snippet_storage}:snippets/${snippet_file}"
  if ! snippet_path=$(pvesm path "$snippet_ref" 2>/dev/null); then
    echo -e "${INFO}${BOLD}${YW}Unable to prepare Cloud-Init snippet; using Proxmox default Cloud-Init user handling${CL}"
    return
  fi
  mkdir -p "$(dirname "$snippet_path")"

  if [ -n "${CIPASSWORD:-}" ]; then
    password_hash=$(printf '%s' "$CIPASSWORD" | openssl passwd -6 -stdin)
    cat >"$snippet_path" <<CLOUDINIT_EOF
#cloud-config
hostname: $HN
manage_etc_hosts: true
ssh_pwauth: true
users:
  - name: $CIUSER
    gecos: $CIUSER
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: $password_hash
chpasswd:
  expire: false
CLOUDINIT_EOF
  else
    cat >"$snippet_path" <<CLOUDINIT_EOF
#cloud-config
hostname: $HN
manage_etc_hosts: true
ssh_pwauth: false
users:
  - name: $CIUSER
    gecos: $CIUSER
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
CLOUDINIT_EOF
  fi

  CICUSTOM="user=$snippet_ref"
  msg_ok "Configured Cloud-Init user ${CL}${BL}$CIUSER${CL}"
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

check_root
arch_check
pve_check
ssh_check
start_script

post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
  FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# ==============================================================================
# PREREQUISITES
# ==============================================================================
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  apt-get update >/dev/null 2>&1
  apt-get install -y libguestfs-tools >/dev/null 2>&1
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the Debian 13 Qcow2 Disk Image"
if [ "$CLOUD_INIT" == "yes" ]; then
  URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
else
  URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
fi
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
msg_info "Customizing ${FILE} image"

WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$FILE" "$WORK_FILE"

# Set hostname
virt-customize -q -a "$WORK_FILE" --hostname "${HN}" >/dev/null 2>&1

# Prepare for unique machine-id on first boot
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1

# Disable systemd-firstboot to prevent interactive prompts blocking the console
virt-customize -q -a "$WORK_FILE" --run-command "systemctl disable systemd-firstboot.service 2>/dev/null; rm -f /etc/systemd/system/sysinit.target.wants/systemd-firstboot.service; ln -sf /dev/null /etc/systemd/system/systemd-firstboot.service" >/dev/null 2>&1 || true

# Pre-seed firstboot settings so it won't prompt even if triggered
virt-customize -q -a "$WORK_FILE" --run-command "echo 'Etc/UTC' > /etc/timezone && ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "touch /etc/locale.conf" >/dev/null 2>&1 || true

if [ "$CLOUD_INIT" == "yes" ]; then
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
fi

msg_ok "Customized image"

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="-format raw"
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK"${i}"=vm-"${VMID}"-disk-"${i}"${DISK_EXT:-}
  eval DISK"${i}"_REF="${STORAGE}":"${DISK_REF:-}"${!disk}
done

msg_info "Creating a Debian 13 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags vm-auto-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${WORK_FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
if [ "$CLOUD_INIT" == "yes" ]; then
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -scsi1 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
else
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
fi

rm -f "$WORK_FILE"

if [ "$CLOUD_INIT" == "yes" ]; then
  create_cloudinit_user_config
  qm set $VMID -ciuser "${CIUSER:-debian}" >/dev/null
  if [ -n "${CICUSTOM:-}" ]; then
    qm set $VMID -cicustom "$CICUSTOM" >/dev/null
  elif [ -n "${CIPASSWORD:-}" ]; then
    qm set $VMID -cipassword "$CIPASSWORD" >/dev/null
  fi
  if [ -n "${NETPLAN_IP:-}" ] && [ -n "${NETPLAN_GW:-}" ]; then
    qm set $VMID -ipconfig0 "ip=${NETPLAN_IP},gw=${NETPLAN_GW}" >/dev/null
    msg_ok "Configured static IP ${CL}${BL}${NETPLAN_IP}${CL} via ${BL}${NETPLAN_GW}${CL}"
  else
    qm set $VMID -ipconfig0 "ip=dhcp" >/dev/null
  fi
fi

CREATED_AT=$(LC_TIME=C date '+%-d %B %Y %H:%M')
DESCRIPTION=$(cat <<EOF
<div align='center'>
  <a href='https://itn.net.id' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/starbox3/PROXMOX-VM-SCRIPT/main/images/logo-itn.png' alt='Logo' style='width:81px;height:81px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Debian 13 VM</h2>

  <p style='margin: 16px 0;'>
    VM Created AT ${CREATED_AT}
  </p>
</div>
EOF
)
qm set $VMID -description "$DESCRIPTION" >/dev/null
if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
fi

msg_ok "Created a Debian 13 VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Debian 13 VM"
  qm start $VMID
  msg_ok "Started Debian 13 VM"
fi

msg_ok "Completed successfully!\n"
echo "More Info at https://github.com/community-scripts/ProxmoxVE/discussions/836"