#!/usr/bin/env bash
# Usage: ./init_robot.sh [user@robot [SSH_PORT]], --inspect [user@robot [SSH_PORT]], or --local
set -Eeuo pipefail
umask 077
BASE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CODE=code_1.132.0-1785860155_arm64.deb
CLASH=Clash.Verge_2.5.2_arm64.deb
fail() { echo "错误：$*" >&2; exit 1; }
trap 'echo "初始化失败，请检查上方错误；修复后可以重新运行。" >&2' ERR
resolve_target() {
  [[ $# -le 2 ]] || fail '用法：./init_robot.sh [用户@IP [端口]] 或 ./init_robot.sh --inspect [用户@IP [端口]]'
  if [[ $# -eq 0 ]]; then
    read -r -p '请输入机器人 IP 或主机名：' robot_host || fail '未输入机器人地址'
    read -r -p '请输入机器人 SSH 用户名：' robot_user || fail '未输入 SSH 用户名'
    target="$robot_user@$robot_host"
  else
    target=$1
  fi
  port=${2:-22}
  [[ $target =~ ^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$ ]] || fail '请使用有效的 用户@IP 或 用户@主机名（不支持 IPv6）'
  [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] || fail 'SSH 端口无效'
}
if [[ ${1:-} == --inspect ]]; then
  shift
  resolve_target "$@"
  echo '只读检查：不上传文件、不调用 sudo、不安装或修改配置。'
  ssh -p "$port" "$target" 'printf "SYSTEM\n"; cat /etc/os-release; printf "ARCH\n"; uname -m; dpkg --print-architecture; printf "TOOLS\n"; command -v python3 git curl apt-get systemctl gh clash-verge verge-mihomo || true; printf "INIT\n"; ps -p 1 -o comm=; printf "DESKTOP\n"; ls /usr/share/xsessions /usr/share/wayland-sessions 2>/dev/null || true; printf "DEPENDENCIES\n"; apt-cache policy libwebkit2gtk-4.1-0 libgtk-3-0 gh python3-yaml; printf "ROUTES\n"; ip route show; printf "PORTS\n"; ss -ltn; printf "GITHUB_NETWORK\n"; if command -v curl >/dev/null; then curl -I -sS --max-time 15 https://api.github.com; else printf "curl 未安装，跳过网络检查\n"; fi'
  exit 0
fi
if [[ ${1:-} != --local ]]; then
  bash "$BASE/ensure_host_dependencies.sh" gpg curl python3 ssh scp sha256sum git tar
  resolve_target "$@"
fi
if [[ ${1:-} != --local ]]; then
  bash "$BASE/prepare_config.sh"
fi
if [[ ${1:-} != --local ]]; then
  bash "$BASE/fetch_installers.sh"
fi
[[ -s "$BASE/github_token.txt" ]] || fail '需要自动登录 GitHub：请先在本目录创建 github_token.txt，放一行 Token'
for file in "$CODE" "$CLASH" github_account.txt clash_URL.txt github_code.txt configure_robot.py clone_robot.py; do
  [[ -f "$BASE/$file" ]] || fail "缺少文件：$file"
done
if [[ ${1:-} != --local ]]; then
  command -v python3 >/dev/null || fail '电脑需要 Python 3 来检查仓库地址'
  python3 "$BASE/clone_robot.py" --check "$BASE/github_code.txt"
  # Reuse one authenticated connection so SSH/SCP do not repeatedly ask for a password.
  control_dir=$(mktemp -d /tmp/robot-init-ssh.XXXXXXXX)
  control="$control_dir/socket"
  remote=''
  ssh_opts=(-p "$port" -o ControlMaster=auto -o ControlPersist=10m -o "ControlPath=$control")
  cleanup() {
    if [[ -n $remote ]]; then
      ssh "${ssh_opts[@]}" "$target" "rm -rf -- '$remote'" || true
    fi
    ssh "${ssh_opts[@]}" -O exit "$target" >/dev/null 2>&1 || true
    rm -rf -- "$control_dir"
  }
  trap cleanup EXIT
  echo '连接机器人；如需密码，SSH 会提示输入，输入时不会显示字符。'
  ssh "${ssh_opts[@]}" -fN "$target"
  echo '检查机器人架构、系统和 sudo 权限……'
  ssh -t "${ssh_opts[@]}" "$target" 'test "$(dpkg --print-architecture)" = arm64 && command -v apt-get >/dev/null && command -v systemctl >/dev/null && sudo -v' || fail '需要 ARM64 Debian/Ubuntu、systemd 和 sudo 权限'
  remote=$(ssh "${ssh_opts[@]}" "$target" 'umask 077; mktemp -d /tmp/robot-init.XXXXXXXX')
  [[ $remote =~ ^/tmp/robot-init\.[a-zA-Z0-9]+$ ]] || fail '远端临时目录无效'
  files=(init_robot.sh configure_robot.py "$CODE" "$CLASH" github_account.txt clash_URL.txt github_code.txt clone_robot.py)
  [[ ! -f "$BASE/github_token.txt" ]] || files+=(github_token.txt)
  paths=(); for file in "${files[@]}"; do paths+=("$BASE/$file"); done
  echo '传输安装包和配置文件……'
  scp -P "$port" -o "ControlPath=$control" "${paths[@]}" "$target:$remote/"
  ssh -t "${ssh_opts[@]}" "$target" "bash '$remote/init_robot.sh' --local"
  exit 0
fi
[[ $# -eq 1 ]] || fail '--local 不接受其他参数'
[[ $(id -u) -ne 0 ]] || fail '请使用机器人普通桌面用户运行，脚本会按需调用 sudo'
[[ $(dpkg --print-architecture) == arm64 ]] || fail '安装包要求 ARM64 架构'
[[ -d /run/systemd/system ]] || fail '需要使用 systemd 的 Debian/Ubuntu 系统'
command -v python3 >/dev/null || fail '请先安装 python3：sudo apt-get install python3'
python3 "$BASE/configure_robot.py" --check "$BASE"
python3 "$BASE/clone_robot.py" --check "$BASE/github_code.txt"
if pgrep -u "$(id -u)" -x clash-verge >/dev/null; then
  fail '请先退出 Clash Verge，再运行脚本，避免应用覆盖配置'
fi
sudo -v
for file in "$CODE" "$CLASH"; do
  [[ $(dpkg-deb -f "$BASE/$file" Architecture) == arm64 ]] || fail '安装包架构不匹配'
done
echo '安装 VS Code、Clash Verge 和依赖……'
# Stage packages somewhere apt's sandbox user can read, even if the SSH upload is private.
stage=$(sudo mktemp -d /var/tmp/robot-init-debs.XXXXXXXX)
trap 'sudo rm -rf -- "$stage"' EXIT
sudo chmod 755 "$stage"
sudo install -m 644 "$BASE/$CODE" "$BASE/$CLASH" "$stage/"
sudo apt-get update
sudo apt-get install -y git curl ca-certificates python3-yaml gh "$stage/$CODE" "$stage/$CLASH"
python3 "$BASE/configure_robot.py" "$BASE"
proxy_dir="$HOME/.config/robot-init"
/usr/bin/verge-mihomo -t -d "$proxy_dir" -f "$proxy_dir/config.yaml" >"$proxy_dir/validation.log" 2>&1 || fail "代理配置校验失败，详情在 $proxy_dir/validation.log（可能含订阅信息）"
unit=$(mktemp)
trap 'rm -f -- "$unit"; sudo rm -rf -- "$stage"' EXIT
# Quote systemd paths; standard Linux account names are required for User=.
[[ $(id -un) =~ ^[a-zA-Z_][a-zA-Z0-9_-]*\$?$ ]] || fail '不支持的用户名'
[[ $HOME != *'"'* && $HOME != *'%'* && $HOME != *'\\'* ]] || fail '不支持的 HOME 路径'
cat > "$unit" <<UNIT
[Unit]
Description=Robot initialization HTTP/SOCKS proxy
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$(id -un)
ExecStart=/usr/bin/verge-mihomo -d "$proxy_dir" -f "$proxy_dir/config.yaml"
Restart=on-failure
RestartSec=5
UMask=0077
[Install]
WantedBy=multi-user.target
UNIT
sudo install -m 644 "$unit" /etc/systemd/system/robot-init-proxy.service
sudo systemctl daemon-reload
sudo systemctl enable robot-init-proxy.service
sudo systemctl stop robot-init-proxy.service
python3 - <<'PYPORT'
import socket
for port in (7890, 19090):
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'端口 {port} 已被其他程序占用，请释放后重新运行')
PYPORT
sudo systemctl start robot-init-proxy.service
ready=0
for attempt in {1..30}; do
  if curl --silent --fail --noproxy '*' --max-time 2 http://127.0.0.1:19090/version >/dev/null; then ready=1; break; fi
  sleep 1
done
[[ $ready == 1 ]] || fail '后台代理启动失败：sudo systemctl status robot-init-proxy'
# These apply only to this script; future interactive shells load robot-proxy.sh.
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
export all_proxy=socks5h://127.0.0.1:7890 no_proxy=localhost,127.0.0.1,::1
export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy" ALL_PROXY="$all_proxy" NO_PROXY="$no_proxy"
echo '配置 GitHub HTTPS 登录……'
gh auth login --hostname github.com --git-protocol https --with-token < "$BASE/github_token.txt" > "$proxy_dir/github-auth.log" 2>&1 || fail "GitHub 登录失败，查看 $proxy_dir/github-auth.log"
gh auth setup-git --hostname github.com

echo '下载 GitHub 仓库到 /home/booster/Workspace……'
python3 "$BASE/clone_robot.py" "$BASE/github_code.txt"

if curl -fsS --max-time 25 -o /dev/null https://api.github.com; then
  echo 'GitHub 网络连通检查通过。'
else
  echo '提示：代理已启动，但 GitHub 连通检查失败；请检查订阅节点、规则和机器人网络。'
fi
echo '初始化完成。后台代理：127.0.0.1:7890；Clash Verge 图形界面代理：127.0.0.1:7897。'
echo '重新 SSH 登录后终端代理自动生效；当前会话执行：source ~/.config/robot-init/robot-proxy.sh'
echo '后台代理状态：sudo systemctl status robot-init-proxy'
