source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="CasaOS"
var_tags="${var_tags:-cloud}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function set_custom_description() {
  local created_at os_label
  created_at=$(LC_TIME=C date '+%-d %B %Y %H:%M')
  os_label="${APP} LXC Container"
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
[ -t 1 ] || return 0
echo -e ""
echo -e "CasaOS LXC Container"
echo -e "    🌐  \033[m\033[33m Provided by: \033[1;92m INDONESIA TRANS NETWORK | itn.net.id \033[m"
os_display="Unknown OS"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  os_display="${PRETTY_NAME:-${NAME:-Unknown OS}}"
fi
echo -e "    🖥️  \033[m\033[33m OS: \033[1;92m${os_display}\033[m"
echo -e "    🏠  \033[m\033[33m Hostname: \033[1;92m$(hostname)\033[m"
echo -e "    💡  \033[m\033[33m IP Address: \033[1;92m$(hostname -I | awk '{print $1}')\033[m"
MOTDEOF
)
  pct exec "$CTID" -- bash -c "
    echo '${motd_b64}' | base64 -d > /etc/profile.d/00_lxc-details.sh
    rm -f /etc/profile.d/motd.sh
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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
