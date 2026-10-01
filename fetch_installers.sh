#!/usr/bin/env bash
# Download exact checked package versions from this repository's installers-v1 release.
set -Eeuo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
manifest="$base/installers.sha256"
[[ -f $manifest ]] || { echo '缺少 installers.sha256' >&2; exit 1; }
bash "$base/ensure_host_dependencies.sh" curl sha256sum awk
for name in code_1.132.0-1785860155_arm64.deb Clash.Verge_2.5.2_arm64.deb; do
  expected=$(awk -v file="$name" '$2 == file {print $1}' "$manifest")
  [[ $expected =~ ^[0-9a-f]{64}$ ]] || { echo "缺少 $name 的校验值" >&2; exit 1; }
  if [[ -f "$base/$name" ]] && printf '%s  %s\n' "$expected" "$base/$name" | sha256sum -c --status; then
    echo "已校验本地安装包：$name"
    continue
  fi
  echo "下载安装包：$name"
  temporary=$(mktemp "$base/.download.XXXXXXXX")
  trap 'rm -f -- "$temporary"' EXIT
  if ! curl -fL --retry 3 --connect-timeout 15 --max-time 1800 \
      -o "$temporary" "https://github.com/Robot-create-it/dancer-robotinit/releases/download/installers-v1/$name"; then
    echo "下载失败：请确认 GitHub Releases 的 installers-v1 已包含 $name" >&2
    exit 1
  fi
  printf '%s  %s\n' "$expected" "$temporary" | sha256sum -c --status || {
    echo "安装包校验失败：$name" >&2; exit 1;
  }
  mv -f -- "$temporary" "$base/$name"
  trap - EXIT
done
