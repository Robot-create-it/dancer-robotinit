#!/usr/bin/env bash
# Run once on the owner's computer, then commit shared-config.tar.gz.gpg.
set -Eeuo pipefail
umask 077
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$base/ensure_host_dependencies.sh" gpg tar
for name in github_account.txt github_token.txt clash_URL.txt; do
  [[ -s "$base/$name" ]] || { echo "缺少 $name" >&2; exit 1; }
done
[[ -t 0 ]] || { echo '请在交互终端运行' >&2; exit 1; }
read -rs -p '设置共享配置解密密码：' pass; echo
read -rs -p '再次输入密码：' confirm; echo
[[ -n $pass && $pass == "$confirm" ]] || { echo '两次密码不一致或为空' >&2; exit 1; }
unset confirm
output="$base/shared-config.tar.gz.gpg"
temporary=$(mktemp "$base/.shared-config.XXXXXXXX.gpg")
trap 'rm -f -- "$temporary"' EXIT
# Pass the secret through a file descriptor, never through command arguments.
tar -C "$base" -czf - github_account.txt github_token.txt clash_URL.txt |
  gpg --batch --yes --pinentry-mode loopback --cipher-algo AES256 --symmetric \
      --passphrase-fd 3 --output "$temporary" 3<<<"$pass"
unset pass
mv -f -- "$temporary" "$output"
echo '已生成 shared-config.tar.gz.gpg。只提交该加密文件；密码单独发给受信任的人。'
