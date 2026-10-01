# 机器人一键初始化

没有默认机器人地址。无参数运行时依次输入机器人 IP（或主机名）和 SSH 用户名，随后按 SSH 提示输入密码（输入不显示）。支持无线或有线 SSH。

只读检查（不上传、不安装、不修改机器人配置、不调用 sudo）：

```bash
./init_robot.sh --inspect
```

正式安装与配置（会修改机器人，仅在准备好后由你执行）：

```bash
./init_robot.sh
```

指定其他目标：

```bash
./init_robot.sh robot@192.168.1.100
```

SSH 非默认端口示例：`./init_robot.sh robot@192.168.1.100 2222`。
脚本自动通过 SCP 上传目录中的两个 deb 和配置文件，SSH 登录机器人完成安装。
若已把这些文件和三个脚本放到机器人同一目录，也可以运行 `bash init_robot.sh --local`。
请使用机器人实际桌面用户登录，不能用 root；配置写入该用户的 HOME。
第一次 SSH 连接可能要求确认主机指纹，随后可能要求 SSH 密码和 sudo 密码。正式初始化复用一个 SSH 连接，避免上传和后续 SSH 步骤反复要求登录密码；sudo 密码仍可能单独要求。
若要完全无人值守，需要事先配置 SSH 密钥和适当的免密 sudo 权限。

## 执行后机器人会按顺序做什么

执行 `./init_robot.sh`，输入机器人 IP、用户名和密码后：

1. 接收电脑上的 VS Code、Clash Verge 安装包和配置文件。
2. 检查机器人是否满足安装条件。
3. 安装 VS Code 和 Clash Verge，以及需要的依赖软件。
4. 从 clash_URL.txt 中的地址下载代理订阅。
5. 配置 Clash Verge 的订阅和后台代理。
6. 配置 Git 的姓名和邮箱。
7. 配置终端，让以后登录机器人时自动使用代理。
8. 启动后台代理，并设置开机自动启动。
9. 使用 github_token.txt 中的 Token 自动登录 GitHub，配置 HTTPS 下载和推送认证。
10. 读取 github_code.txt 中的仓库地址，将代码克隆到 /home/booster/Workspace/仓库名。
11. 检查能否访问 GitHub，显示完成信息，删除临时安装文件。

VS Code 和 Clash Verge 的安装包已在电脑上，所以机器人接收后直接安装，无需重新从网上下载。GitHub 登录成功后会自动 clone github_code.txt 中配置的代码。

`./init_robot.sh --inspect` 只查看机器人信息，不进行以上安装和配置。

## 输入文件

安装包使用当前目录中的：

- `code_1.132.0-1785860155_arm64.deb`
- `Clash.Verge_2.5.2_arm64.deb`

这些文件已在电脑上，因此流程是上传并安装，不再从互联网下载同一安装包。
依赖包仍从机器人配置的 apt 软件源下载。

`github_account.txt`（当前文件格式已通过检查）：

```text
user.name: Your Name
user.email: your-email@example.com
```

这两个字段只设置 Git 提交身份，不代表登录 GitHub。
自动配置 GitHub HTTPS 推送认证需要在本目录新增 `github_token.txt`，
只放一行 GitHub classic Personal Access Token，赋予所需权限（gh 登录通常需要 repo、read:org、gist）。
先执行 `chmod 600 github_token.txt`，不要将 Token 发到聊天中。
脚本通过 stdin 传给 `gh auth login`，然后运行 `gh auth setup-git`。
缺少 Token 文件时脚本在上传和安装前直接退出。
无系统密钥环时 gh 可能将凭据保存到机器人上的明文配置文件，见官方说明：
https://cli.github.com/manual/gh_auth_login 。已有 SSH 仓库地址不因 HTTPS 登录自动改变。
VS Code 的 GitHub Settings Sync / 扩展登录仍需要其独立授权。

`clash_URL.txt`：一行 HTTPS Clash/Mihomo **YAML 订阅 URL**。
脚本不会将订阅 URL、订阅正文或 Token 输出到终端。
不支持直接返回 Base64 节点列表的订阅，请在订阅提供方取得 Clash 格式地址。

## 下载 GitHub 代码

在同目录的 `github_code.txt` 中填写仓库地址，每行一个，例如：

```text
https://github.com/用户名/仓库名.git
```

支持多个仓库、空行和以 `#` 开头的注释。GitHub SSH 地址会自动转换为 HTTPS，所以无需配置 SSH 密钥。文件会随安装包一起上传，并在安装前检查格式。

代理启动、GitHub Token 登录成功后，代码下载到 **`/home/booster/Workspace/仓库名`**。Workspace 不存在时自动创建；登录用户需要对此路径有写权限，使用 booster 用户即可按通常的 HOME 权限创建。私有仓库需要账号本身具有访问权限，Token 具有 repo 权限。

重复执行时，如果目标目录已经是同一个 origin 的 Git 仓库，则跳过，不自动 pull、不覆盖本地修改；若目录被其他文件或不同仓库占用，则报错退出。不同所有者的同名仓库不能同时配置。克隆失败会停止初始化，并清理未完成的克隆临时目录；已成功下载的仓库会保留。

只下载仓库默认分支，不执行编译、依赖安装或仓库中的脚本，也不自动下载子模块。

## 代理行为

- 下载订阅，保留其中的节点、代理组和规则，导入并选中 Clash Verge 配置。
- 同时用 deb 内的 `verge-mihomo` 建立 systemd 服务 `robot-init-proxy`，开机启动。
- SSH 终端使用本机 `127.0.0.1:7890`；HTTP 和 SOCKS5 共用该端口。
- `.bashrc` 和 `.profile` 会加载代理环境变量；重新 SSH 登录后生效。
  当前机器人会话可执行 `source ~/.config/robot-init/robot-proxy.sh`。
- 代理控制接口仅绑定 `127.0.0.1:19090`；关闭 TUN 和 LAN 监听，避免改动机器人网络路由。
- Clash Verge 桌面界面手动打开，使用独立端口 7897，不自动开启桌面系统代理或 GUI 自启动。
  其配置与后台服务分别运行；GUI 中改节点或更新订阅不会同步到后台服务。
- 后台订阅在每次初始化时刷新，**没有定时刷新**；订阅过期或变更后重新运行脚本。
- 沿用订阅默认规则和默认节点，不保证所有请求都会经远端代理。
  服务启动后脚本额外检查 GitHub 连通性，失败会明确提示。

VS Code 和 Clash Verge 是桌面应用，安装可以通过 SSH 完成，使用界面需要机器人具有图形桌面。
GUI 配置前请退出正在运行的 Clash Verge。没有桌面的机器人也可以使用后台代理和 Git，
但桌面应用本身无法在纯 SSH 终端显示。

## 前提与限制

机器人须为 ARM64 Debian/Ubuntu，使用 systemd，安装 Python 3，登录用户拥有 sudo 权限。
操作系统的软件源必须提供安装包所需的库；Clash Verge 需要 `libwebkit2gtk-4.1-0`，
旧版系统可能无法安装，请先确认机器人系统版本（例如 `cat /etc/os-release`）。
无线或有线 SSH 连通不等于机器人能联网：初始化前机器人必须能访问 apt 软件源和订阅服务器。
脚本不改 IP、路由、SSH 配置，不自动重启机器人。

重复执行会更新这些配置；被修改的已有文件旁会生成 `.bak.时间戳` 备份。
远端上传临时目录结束后删除；订阅/代理配置和认证日志保存在机器人用户目录，权限限制为用户本人。
脚本失败会退出，不提供全流程事务回滚；已经安装的软件和写入的配置可能保留。

检查和停止后台代理：

```bash
sudo systemctl status robot-init-proxy
sudo journalctl -u robot-init-proxy -n 50
sudo systemctl disable --now robot-init-proxy
```

日志可能包含节点或订阅信息，分享前请自行脱敏。
停止服务后终端代理环境变量仍在，如需停用，删除 `.bashrc`/`.profile` 的 Robot initialization proxy
加载行，重新登录（或在当前会话 unset 对应大小写代理环境变量）。

## 已做验证

本机验证 Bash 语法、输入文件格式，并以模拟订阅在临时 HOME 验证配置生成及重复执行。
代理配置生成使用模拟订阅测试；用户提供了机器人只读检查结果。未在本机安装 ARM64 软件，也未使用真实订阅或 GitHub Token 发起请求。
最终安装和实际节点连通性必须在目标机器人上验证。

Clash Verge 2.5.2 配置字段参考官方源码：
https://github.com/clash-verge-rev/clash-verge-rev/tree/v2.5.2/src-tauri/src/config

