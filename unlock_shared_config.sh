#!/usr/bin/env bash
# Invoked by init_robot.sh on the operator's computer before SSH.
set -Eeuo pipefail
umask 077
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
archive="$base/shared-config.tar.gz.gpg"
[[ -s $archive ]] || { echo '缺少 shared-config.tar.gz.gpg' >&2; exit 1; }
bash "$base/ensure_host_dependencies.sh" gpg tar
[[ -t 0 ]] || { echo '解密密码需要在交互终端输入' >&2; exit 1; }
read -rs -p '请输入共享配置解密密码：' pass; echo
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
if ! gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
       --decrypt --output "$stage/config.tar.gz" "$archive" 3<<<"$pass" 2>/dev/null; then
  unset pass
  echo '解密失败：密码不正确或加密文件损坏' >&2
  exit 1
fi
unset pass
# Check archive members before extracting and never overwrite existing local credentials.
actual=$(tar -tzf "$stage/config.tar.gz" | sort)
expected=$(printf '%s\n' github_account.txt github_token.txt clash_URL.txt | sort)
[[ $actual == "$expected" ]] || { echo '加密包内容不符合预期' >&2; exit 1; }
tar -C "$stage" -xzf "$stage/config.tar.gz" --no-same-owner --no-same-permissions
for name in github_account.txt github_token.txt clash_URL.txt; do
  [[ -s "$stage/$name" ]] || { echo "加密包内缺少 $name" >&2; exit 1; }
  if [[ -e "$base/$name" ]]; then
    echo "本地 $name 已存在，保留现有文件" >&2
  else
    install -m 600 "$stage/$name" "$base/$name"
  fi
done
echo '已在本机准备好配置文件；继续初始化。'
