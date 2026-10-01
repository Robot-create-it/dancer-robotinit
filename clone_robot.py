#!/usr/bin/env python3
"""Clone GitHub repositories via the credential helper configured by gh."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

WORKSPACE = Path('/home/booster/Workspace')


def normalize(value):
    match = re.fullmatch(
        r'(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)'
        r'([A-Za-z0-9_-]+)/([A-Za-z0-9_.-]+)/?', value.strip())
    if not match:
        raise ValueError('仓库地址必须为 GitHub HTTPS 或 SSH 仓库地址，不能带 Token、查询参数或分支路径')
    owner, name = match.groups()
    if name.endswith('.git'):
        name = name[:-4]
    if not name or name in ('.', '..'):
        raise ValueError('仓库名称无效')
    return f'https://github.com/{owner}/{name}.git', name


def repositories(path):
    result = []
    destinations = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        url, name = normalize(line)
        key = name.casefold()
        if key in destinations:
            if destinations[key].casefold() == url.casefold():
                continue
            raise ValueError('多个不同仓库同名，无法放在同一个 Workspace 中，请调整 github_code.txt')
        destinations[key] = url
        result.append((url, name))
    if not result:
        raise ValueError('github_code.txt 至少需要一行仓库地址')
    return result


def clone_all(entries, workspace=WORKSPACE):
    workspace.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0')
    for url, name in entries:
        destination = workspace / name
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or not (destination / '.git').exists():
                raise ValueError(f'{destination} 已存在且不是可复用的 Git 仓库，请先自行处理')
            origin = subprocess.run(['git', '-C', str(destination), 'remote', 'get-url', 'origin'],
                                    check=True, capture_output=True, text=True, env=env).stdout.strip()
            if normalize(origin)[0].casefold() != url.casefold():
                raise ValueError(f'{destination} 的 origin 与配置不一致，停止克隆以保护已有文件')
            print(f'仓库已存在，跳过克隆并保留现有代码：{destination}')
            continue
        # Publish only a completed clone; failed downloads do not block the next run.
        temporary = Path(tempfile.mkdtemp(prefix='.robot-clone-', dir=workspace))
        try:
            print(f'克隆代码到：{destination}', flush=True)
            subprocess.run(['git', 'clone', '--', url, str(temporary / 'repo')], check=True, env=env)
            (temporary / 'repo').rename(destination)
        finally:
            shutil.rmtree(temporary)


def main():
    check = len(sys.argv) == 3 and sys.argv[1] == '--check'
    path = Path(sys.argv[2] if check else sys.argv[1])
    entries = repositories(path)
    if check:
        print(f'仓库地址检查通过，共 {len(entries)} 个仓库。')
    else:
        clone_all(entries)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as exc:
        print(f'克隆配置错误：{exc}', file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError:
        print('Git 操作失败：请检查网络、Token 权限及仓库访问权限。', file=sys.stderr)
        sys.exit(1)
