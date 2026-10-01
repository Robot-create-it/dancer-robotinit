#!/usr/bin/env python3
"""Private configuration writer. Never prints subscription URLs or credentials."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.request


def inputs(base):
    account = {}
    for line in (base / 'github_account.txt').read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'(user\.name|user\.email)\s*(?:[:=：]\s*|\s+)(.+)', line)
        if not match:
            raise ValueError('github_account.txt 每行应为 user.name: 姓名 或 user.email: 邮箱')
        account[match[1]] = match[2].strip().strip('"\'')
    if not all(account.get(k) for k in ('user.name', 'user.email')):
        raise ValueError('github_account.txt 缺少 user.name 或 user.email')
    lines = [l.strip() for l in (base / 'clash_URL.txt').read_text(encoding='utf-8-sig').splitlines()
             if l.strip() and not l.lstrip().startswith('#')]
    if len(lines) != 1 or not lines[0].startswith('https://'):
        raise ValueError('clash_URL.txt 应只包含一行 HTTPS Clash/Mihomo YAML 订阅地址')
    return account, lines[0]


def write_private(path, content):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.exists():
        backup = path.with_name(path.name + '.bak.' + str(time.time_ns()))
        shutil.copy2(path, backup)
        backup.chmod(0o600)
    temporary = path.with_name(path.name + '.robot-init.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        os.chmod(temporary, 0o600)
        stream.write(content)
    temporary.replace(path)


def main():
    os.umask(0o077)
    check = sys.argv[1] == '--check'
    base = Path(sys.argv[2] if check else sys.argv[1])
    account, url = inputs(base)
    if check:
        print('配置文件格式检查通过（未显示敏感信息）。')
        return
    import yaml
    home = Path.home()
    private = home / '.config/robot-init'
    private.mkdir(parents=True, exist_ok=True, mode=0o700)
    request = urllib.request.Request(url, headers={'User-Agent': 'clash-verge/v2.5.2'})
    # Do not inherit a stale proxy from an earlier initialization.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=60) as response:
            content = response.read(16 * 1024 * 1024 + 1)
        if len(content) > 16 * 1024 * 1024:
            raise ValueError('subscription too large')
        config = yaml.safe_load(content)
        if not isinstance(config, dict) or not (config.get('proxies') or config.get('proxy-providers')):
            raise ValueError('not a Clash subscription')
    except Exception:
        raise ValueError('订阅下载或解析失败：检查直连网络、订阅有效期及 Clash YAML 格式（URL 已隐藏）') from None
    # Keep the provider's groups/rules. Isolate listeners from the Verge GUI core.
    config.update({'mixed-port': 7890, 'allow-lan': False, 'bind-address': '127.0.0.1',
                   'external-controller': '127.0.0.1:19090', 'secret': '',
                   'tun': {'enable': False}})
    for key in ('port', 'socks-port', 'redir-port', 'tproxy-port', 'listeners',
                'external-controller-tls', 'external-controller-unix', 'external-controller-pipe'):
        config.pop(key, None)
    if isinstance(config.get('dns'), dict):
        config['dns'].pop('listen', None)
    write_private(private / 'config.yaml', yaml.safe_dump(config, allow_unicode=True, sort_keys=False))
    app = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config'))) / 'io.github.clash-verge-rev.clash-verge-rev'
    def load(path):
        if not path.exists():
            return {}
        value = yaml.safe_load(path.read_text())
        if value is None:
            return {}
        if not isinstance(value, dict):
            raise ValueError('现有 Clash Verge 配置格式不正确，请备份后处理')
        return value
    profiles = load(app / 'profiles.yaml')
    uid = 'RRobotInit'
    items = profiles.get('items') or []
    if not isinstance(items, list):
        raise ValueError('现有 Clash Verge profiles.yaml items 格式不正确')
    items = [item for item in items if item.get('uid') != uid]
    items.append({'uid': uid, 'type': 'remote', 'name': 'Robot subscription',
                  'file': uid + '.yaml', 'url': url, 'updated': int(time.time()),
                  'option': {'update_interval': 1440, 'allow_auto_update': True}})
    profiles.update(current=uid, items=items)
    # GUI gets its own ports. It is started manually in a desktop session.
    gui = yaml.safe_load(content)
    gui.update({'mixed-port': 7897, 'allow-lan': False, 'tun': {'enable': False}})
    write_private(app / 'profiles' / (uid + '.yaml'), yaml.safe_dump(gui, allow_unicode=True, sort_keys=False))
    write_private(app / 'profiles.yaml', yaml.safe_dump(profiles, allow_unicode=True, sort_keys=False))
    verge = load(app / 'verge.yaml')
    verge.update(enable_system_proxy=False, enable_auto_launch=False, enable_tun_mode=False, verge_mixed_port=7897)
    write_private(app / 'verge.yaml', yaml.safe_dump(verge, allow_unicode=True, sort_keys=False))
    clash = load(app / 'clash.yaml')
    clash.update({'mixed-port': 7897, 'external-controller': '127.0.0.1:19097', 'allow-lan': False})
    write_private(app / 'clash.yaml', yaml.safe_dump(clash, allow_unicode=True, sort_keys=False))
    for key, value in account.items():
        subprocess.run(['git', 'config', '--global', key, value], check=True)
    snippet = '''# Managed by init_robot.sh
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=socks5h://127.0.0.1:7890
export no_proxy=localhost,127.0.0.1,::1
export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy" ALL_PROXY="$all_proxy" NO_PROXY="$no_proxy"
'''
    write_private(private / 'robot-proxy.sh', snippet)
    source = '\n# Robot initialization proxy\n[ ! -f "$HOME/.config/robot-init/robot-proxy.sh" ] || . "$HOME/.config/robot-init/robot-proxy.sh"\n'
    for name in ('.bashrc', '.profile'):
        path = home / name
        old = path.read_text() if path.exists() else ''
        if '# Robot initialization proxy' not in old:
            write_private(path, old + source)
    print('Git 身份、Clash Verge 订阅和终端代理配置已写入；原配置已备份。')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        # Network/YAML exceptions may contain private subscription data.
        if isinstance(exc, ValueError):
            print('错误：' + str(exc), file=sys.stderr)
        else:
            print('配置失败（敏感信息已隐藏），请检查文件权限和配置格式。', file=sys.stderr)
        sys.exit(1)
