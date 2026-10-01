# 机器人一键初始化

在电脑上 clone 本仓库，运行一个命令，按提示输入机器人地址和密码，即可安装 VS Code、Clash Verge，配置共享代理、登录共享 GitHub 账号，并下载机器人代码。

安装包由脚本自动从本仓库的 GitHub Releases 下载，不需要手动寻找 `.deb` 文件。共享 GitHub 账号和代理配置通过加密包提供，解密密码请向仓库维护者获取。

## 使用前准备

- **电脑**：推荐 Ubuntu/Debian，能够联网，并有 sudo 权限。脚本会检查所需工具，缺少 gpg、curl、Python 3、SSH 等工具时自动安装，可能需要输入电脑的 sudo 密码。
- **机器人**：ARM64 Ubuntu/Debian、systemd、Python 3，能够访问 apt 软件源和代理订阅服务器。已检查的机器人环境为 Ubuntu 22.04.5 LTS / ARM64。
- **登录信息**：准备机器人 IP、SSH 用户名和 SSH 密码；机器人登录用户需要 sudo 权限。下载代码的固定目录为 `/home/booster/Workspace`，建议使用 `booster` 用户，并确认该用户有该目录的写权限。
- **共享配置密码**：向维护者获取，用于解密仓库中的 `shared-config.tar.gz.gpg`。它与机器人 SSH 密码是两个不同的密码。
- **先退出机器人上正在运行的 Clash Verge**，否则脚本会停止并提示关闭应用后重试。

无线和有线 SSH 都可以。机器人也必须能联网：仅有 SSH 连接不能保证可以下载依赖和订阅。

## 第一步：运行初始化命令

在 clone 下来的 `dancer-robotinit` 目录执行：

```bash
bash init_robot.sh
```

按提示输入以下信息：

1. **电脑的 sudo 密码**：仅当电脑缺少工具、需要自动安装时出现。
2. **机器人 IP**：输入你当前要配置的机器人地址，没有默认 IP。
3. **机器人 SSH 用户名**：通常输入 `booster`。
4. **共享配置解密密码**：输入维护者提供的密码。脚本会得到共享 GitHub Token、Git 姓名邮箱和代理订阅，不需要自己再填写这些信息。
5. **SSH 主机指纹确认**：第一次连接可能出现；核对目标后输入 `yes`。
6. **机器人 SSH 密码**：用于登录机器人。
7. **机器人的 sudo 密码**：用于安装软件和配置后台服务，可能与 SSH 密码相同，也可能被多次询问。

密码输入时不会显示字符或星号，这是正常现象。电脑下载两个安装包后才连接机器人，请等待下载完成，不要提前关闭终端。

首次运行时共享配置会解密到电脑上的本仓库目录，之后会复用，因此再次运行通常不再询问解密密码。安装包已存在且校验通过时也不会重复下载。

如果没有收到解密密码，先联系维护者。如果脚本改为要求填写 Git 姓名、邮箱、Token 和订阅地址，说明当前 clone 的仓库没有共享加密包或包内配置不完整；请联系维护者更新仓库，或按提示填写自己的配置。

## 机器人会按顺序做什么

1. 接收电脑传来的 VS Code、Clash Verge 安装包和配置文件。
2. 检查安装条件，安装 VS Code、Clash Verge 和所需依赖。
3. 下载代理订阅，配置 Clash Verge 和后台代理。
4. 配置 Git 姓名和邮箱，配置终端代理环境。
5. 启动后台代理，并设置开机自动启动。
6. 使用共享 Token 登录 GitHub，配置 HTTPS 下载和推送认证。
7. 读取 `github_code.txt`，将仓库代码下载到 `/home/booster/Workspace/仓库名`。
8. 检查 GitHub 连通性，显示完成信息，清理临时安装文件。

默认下载 `github_code.txt` 中仓库的默认分支，不编译代码，也不自动下载子模块。目标目录已是同一仓库时跳过，不自动 pull；若目录被其他文件或不同仓库占用，会报错停止。

## 第二步：确认完成

脚本显示“初始化完成”后，重新 SSH 登录机器人，终端代理会自动生效。

在机器人终端执行以下命令，可检查代理服务、GitHub 登录和下载目录：

```bash
sudo systemctl status robot-init-proxy --no-pager
gh auth status
ls /home/booster/Workspace
```

若想让当前机器人终端立即使用代理，可以执行：

```bash
source ~/.config/robot-init/robot-proxy.sh
```

后台代理地址为 `127.0.0.1:7890`，开机自动启动。Clash Verge 图形界面使用独立端口 `7897`，请在机器人桌面中手动打开；VS Code 同样在桌面中使用。

Clash Verge 图形界面与后台代理分别运行，在界面中切换节点或更新订阅不会自动同步到后台代理。后台订阅随每次初始化刷新，没有定时刷新。GitHub 登录配置用于 Git/gh 的 HTTPS 操作，VS Code Settings Sync 和扩展登录仍需要各自授权。

## 其他常用命令

如果只想查看机器人信息，在电脑的本仓库目录执行：

```bash
bash init_robot.sh --inspect
```

输入机器人 IP、用户名和密码即可。此模式只读，不上传、不安装，也不修改机器人配置；不会自动安装电脑依赖。

SSH 不是默认的 22 端口时，直接指定用户名、IP 和端口：

```bash
bash init_robot.sh booster@机器人IP 2222
```

## 遇到问题怎么办

| 提示或现象 | 处理方法 |
| --- | --- |
| 下载失败、Release 附件 404 | 联系维护者确认 `installers-v1` Release 已发布且两个附件上传完成；同时检查电脑能否访问 GitHub。 |
| 解密失败 | 检查维护者提供的解密密码是否正确，必要时重新获取最新加密包。 |
| 提示退出 Clash Verge | 在机器人桌面退出 Clash Verge，再重新运行初始化命令。 |
| 订阅下载失败 | 检查机器人是否可以直连订阅服务器，以及订阅是否过期。此时新的后台代理尚未启动。 |
| GitHub 登录或 clone 失败 | 联系维护者检查 Token 是否过期，以及共享账号是否有对应仓库的权限。 |
| 已有目录或 origin 不一致 | 检查 `/home/booster/Workspace` 下同名目录，保留需要的代码后自行处理冲突，再重试。 |
| 7890 或 19090 被占用 | 在机器人上检查占用端口的程序，处理后重试。 |

出现错误时脚本通常会停止，修复问题后重新执行 `bash init_robot.sh`。已经完成的软件安装和配置修改会保留，不会自动回滚。GitHub 连通检查失败仅提示，所以还需留意最后的网络检查结果。

## 仓库维护者的发布检查

供其他人完整执行之前，需要完成以下准备：

1. 执行 `bash make_shared_config.sh`，将生成的 `shared-config.tar.gz.gpg` 提交并推送，将解密密码单独发给使用者。
2. 推送所有脚本：`init_robot.sh`、`ensure_host_dependencies.sh`、`prepare_config.sh`、`unlock_shared_config.sh`、`fetch_installers.sh`、`configure_robot.py`、`clone_robot.py`、`make_shared_config.sh`。
3. 推送 `README.md`、`.gitignore`、`github_code.txt` 和 `installers.sha256`。
4. 在本仓库创建并发布 **`installers-v1`** Release，上传以下两个原名附件：

```text
code_1.132.0-1785860155_arm64.deb
Clash.Verge_2.5.2_arm64.deb
```

加密配置包和 Release 附件都发布完成后，使用者才可以按上面的命令完整执行。当前下载方式要求这些 Release 附件能通过公开 HTTPS 访问。

Token 或订阅变更后，重新制作并推送加密包；更换安装包时同时更新 `installers.sha256` 和下载脚本。明文 Token、订阅和解密密码不提交到仓库。能够解密配置的人会取得其中的账号凭据。

## 验证情况

已完成本机 Bash 语法检查、模拟配置生成、克隆流程测试、模拟凭据加解密、安装包校验及电脑依赖自动安装的模拟测试。已收到机器人只读环境检查结果；尚未在真实机器人上完整执行初始化，最终安装和节点连通性需在目标机器人上确认。
