#!/usr/bin/env bash
# Prepare private local inputs; never overwrite existing files.
set -Eeuo pipefail
umask 077
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
missing=0
for name in github_account.txt github_token.txt clash_URL.txt; do
  [[ -s "$base/$name" ]] || missing=1
done
[[ $missing == 1 ]] || exit 0
if [[ -s "$base/shared-config.tar.gz.gpg" ]]; then
  bash "$base/unlock_shared_config.sh"
fi
if [[ ! -s "$base/github_account.txt" ]]; then
  read -r -p '请输入 Git 提交姓名：' git_name
  read -r -p '请输入 Git 提交邮箱：' git_email
  [[ -n $git_name && -n $git_email ]] || { echo '姓名和邮箱不能为空' >&2; exit 1; }
  printf 'user.name: %s\nuser.email: %s\n' "$git_name" "$git_email" > "$base/github_account.txt"
fi
if [[ ! -s "$base/github_token.txt" ]]; then
  read -rs -p '请输入 GitHub Token（输入不显示）：' github_token
  echo
  [[ -n $github_token ]] || { echo 'Token 不能为空' >&2; exit 1; }
  printf '%s\n' "$github_token" > "$base/github_token.txt"
  unset github_token
fi
if [[ ! -s "$base/clash_URL.txt" ]]; then
  read -rs -p '请输入 HTTPS Clash YAML 订阅地址（输入不显示）：' subscription
  echo
  [[ $subscription == https://* ]] || { echo '订阅地址必须以 https:// 开头' >&2; exit 1; }
  printf '%s\n' "$subscription" > "$base/clash_URL.txt"
  unset subscription
fi
chmod 600 "$base/github_account.txt" "$base/github_token.txt" "$base/clash_URL.txt"
echo '个人配置已保存在本机，下次运行会复用。'
