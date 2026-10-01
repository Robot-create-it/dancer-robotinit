#!/usr/bin/env bash
# Check and, on Ubuntu/Debian, install tools on the computer running this script.
set -Eeuo pipefail
missing=()
packages=()
for tool in "$@"; do
  command -v "$tool" >/dev/null 2>&1 && continue
  missing+=("$tool")
  case "$tool" in
    gpg) package=gnupg ;;
    curl) package=curl ;;
    python3) package=python3 ;;
    ssh|scp) package=openssh-client ;;
    sha256sum|mktemp|install) package=coreutils ;;
    git) package=git ;;
    tar) package=tar ;;
    awk) package=mawk ;;
    *) echo "无法自动安装未知工具：$tool" >&2; exit 1 ;;
  esac
  if [[ " ${packages[*]} " != *" $package "* ]]; then packages+=("$package"); fi
done
[[ ${#missing[@]} -gt 0 ]] || exit 0
[[ -r /etc/os-release ]] || { echo "缺少工具：${missing[*]}；请手动安装" >&2; exit 1; }
. /etc/os-release
if [[ ${ID:-} != ubuntu && ${ID:-} != debian && ! ${ID_LIKE:-} =~ (^|[[:space:]])(ubuntu|debian)($|[[:space:]]) ]]; then
  echo "电脑缺少工具：${missing[*]}；该系统暂不支持自动安装，请手动安装" >&2
  exit 1
fi
command -v apt-get >/dev/null || { echo '电脑没有 apt-get，无法自动安装依赖' >&2; exit 1; }
privilege=()
if [[ $(id -u) -ne 0 ]]; then
  command -v sudo >/dev/null || { echo '自动安装电脑依赖需要 sudo 权限' >&2; exit 1; }
  privilege=(sudo)
fi
echo "电脑缺少 ${missing[*]}，自动安装软件包：${packages[*]}（可能需要电脑的 sudo 密码）"
"${privilege[@]}" apt-get update
"${privilege[@]}" apt-get install -y "${packages[@]}"
for tool in "${missing[@]}"; do
  command -v "$tool" >/dev/null || { echo "安装后仍找不到 $tool，请检查电脑的 PATH" >&2; exit 1; }
done
