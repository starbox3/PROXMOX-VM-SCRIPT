source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Ubuntu"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

# function update_script() {
#   header_info
#   check_container_storage
#   check_container_resources
#   if [[ ! -d /var ]]; then
#     msg_error "No ${APP} Installation Found!"
#     exit
#   fi
#   msg_info "Updating ${APP} LXC"
#   $STD apt-get update
#   $STD apt-get -y upgrade
#   msg_ok "Updated ${APP} LXC"
#   msg_ok "Updated successfully!"
#   exit
# }

function set_custom_description() {
  local created_at os_label
  created_at=$(LC_TIME=C date '+%-d %B %Y %H:%M')
  os_label="${APP} ${var_version} LXC Container"
  local desc
  desc=$(cat <<HTMLEOF
<div align='center'>
  <a href='https://itn.net.id' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/starbox3/PROXMOX-VM-SCRIPT/main/images/logo-itn.png' alt='Logo' style='width:81px;height:81px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>${os_label}</h2>

  <p style='margin: 16px 0;'>
    CT Created AT ${created_at}
  </p>
</div>
HTMLEOF
)
  pct set "$CTID" -description "$desc" >/dev/null
}

function set_custom_motd() {
  local motd_b64
  motd_b64=$(base64 -w 0 <<'MOTDEOF'
#!/bin/bash
BL="\033[36m"
GN="\033[1;92m"
YW="\033[33m"
CL="\033[m"

IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
OS=$(. /etc/os-release && echo "$PRETTY_NAME")

echo -e ""
echo -e "  ${BL}Ubuntu LXC Container${CL}"
echo -e "  🌐${CL}  Provided by: ${YW}itn.net.id${CL}"
echo -e "  🖥️ ${CL}  OS: ${GN}${OS}${CL}"
echo -e "  🏠${CL}  Hostname: ${GN}${HOSTNAME}${CL}"
echo -e "  💡${CL}  IP Address: ${GN}${IP}${CL}"
echo -e ""
MOTDEOF
)
  pct exec "$CTID" -- bash -c "
    echo '${motd_b64}' | base64 -d > /etc/profile.d/motd.sh
    chmod +x /etc/profile.d/motd.sh
    truncate -s 0 /etc/motd
  "
}

start
build_container
description

msg_info "Applying custom branding"
set_custom_description
set_custom_motd
msg_ok "Custom branding applied"

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
