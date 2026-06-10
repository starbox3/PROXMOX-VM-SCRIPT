source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="n8n"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/n8n.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies build-essential python3-setuptools graphicsmagick
  NODE_VERSION="24" setup_nodejs

  msg_info "Updating n8n"
  if [ ! -f /opt/n8n.env ]; then
    sed -i 's|^Environment="N8N_SECURE_COOKIE=false"$|EnvironmentFile=/opt/n8n.env|' /etc/systemd/system/n8n.service
    mkdir -p /opt
    cat <<EOF >/opt/n8n.env
N8N_SECURE_COOKIE=false
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_HOST=$LOCAL_IP
EOF
    systemctl daemon-reload
  fi

  $STD npm update -g n8n
  systemctl restart n8n
  msg_ok "Updated n8n"
  msg_ok "Updated successfully!"
  exit
}

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
echo -e "n8n LXC Container"
echo -e "    🌐  Provided by: itn.net.id"
echo -e ""
os_display="Unknown OS"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  os_display="${PRETTY_NAME:-${NAME:-Unknown OS}}"
fi
echo -e "    🖥️  \033[m\033[33m OS: \033[1;92m${os_display}\033[m"
echo -e "    🏠  Hostname: $(hostname)"
echo -e "    💡  IP Address: $(hostname -I | awk '{print $1}')"
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
echo -e "${GATEWAY}${BGN}http://${IP}:5678${CL}"
