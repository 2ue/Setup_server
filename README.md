# Debian/Ubuntu 服务器自动初始化脚本

> 当前维护仓库：[2ue/Setup_server](https://github.com/2ue/Setup_server) <br>
> Fork 自：[Tsanfer/Setup_server](https://github.com/Tsanfer/Setup_server) <br>
> 原项目 License 保持不变，原始版权声明见 [LICENSE](./LICENSE)

> Linux 发行版：Debian 及其衍生版 <br>
> Linux 发行版版本：Debian 11 及以上 LTS 支持版本 <br>
> CPU 指令集架构：x86-64

> 安装时，可选择国内 Github 镜像加速

<!-- 正在计划使用 Kubernetes 来平替此脚本中的 Docker 相关部署 -->

- APT 软件更新、默认软件安装（可选择是否更换系统软件源）
  > 调用 LinuxMirrors 脚本完成软件仓库换源（需使用 ROOT 用户执行此脚本才能换元成功）
  > 
  > 此处给出官方的软件仓库换源脚本
  > ```bash
  > if command -v curl >/dev/null 2>&1; then
  >     bash <(curl -sSL https://linuxmirrors.cn/main.sh)
  > elif command -v wget >/dev/null 2>&1; then
  >     wget -qO- https://linuxmirrors.cn/main.sh | bash
  > else
  >     echo "请先安装 curl 或 wget" >&2
  > fi
  > ```
  
  |部分默认软件|功能|命令|
  |--|--|--|
  |[rsync](https://github.com/WayneD/rsync)|文件同步|`rsync`|
  |[bottom](https://github.com/ClementTsang/bottom)|图形化系统监控|`btm`|
  |[fastfetch](https://github.com/fastfetch-cli/fastfetch)|系统信息工具|`fastfetch`|
  
- 配置 swap 内存

- 服务器测试
  - [VPS融合怪服务器测试脚本](https://github.com/oneclickvirt/ecs)
  
- 配置终端
  - [Oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) 及插件安装（加强 zsh 的功能）
  - [Oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh) 安装（终端提示符美化）
  
- 自选软件安装/卸载
  |自选软件|功能|命令|
  |--|--|--|
  |[mdserver-web](https://github.com/midoks/mdserver-web)|一款简单Linux面板服务（宝塔翻版）|`mw`|
  |[aaPanel](https://www.aapanel.com/new/index.html)|宝塔国外版|`bt`|
  |[1Panel](https://github.com/1Panel-dev/1Panel)|现代化、开源的 Linux 服务器运维管理面板|`1pctl`|

- 开发工具链安装/更新
  |工具|来源|说明|
  |--|--|--|
  |[Volta](https://docs.volta.sh/guide/getting-started/)|官方安装脚本|安装/更新 Volta 本身|
  |Node.js 22|Volta|执行 `volta install node@22`，用于统一 Node 运行时|
  |[ccman](https://github.com/2ue/ccman)|Volta / npm|安装后可选配置 WebDAV 同步并执行 `ccman sync download --yes`|
  |[Codex CLI](https://developers.openai.com/codex/quickstart)|Volta / npm|执行 `volta install @openai/codex`|
  |[Claude Code](https://docs.anthropic.com/en/docs/claude-code/quickstart)|Volta / npm|执行 `volta install @anthropic-ai/claude-code`|
  
- 安装和更新 Docker
  > 调用 LinuxMirrors 脚本完成操作

- 安装/删除 docker 容器
  |Docker 容器|功能|端口|
  |--|--|--|
  |[code-server](https://github.com/coder/code-server)|在线 Web IDE|`8443`|
  |[nginx](https://hub.docker.com/_/nginx)|Web 服务器|`80`|
  |[pure-ftpd](https://hub.docker.com/r/stilliard/pure-ftpd)|FTP 服务器|主动端口：`21`|
  |[web_object_detection](https://github.com/Tsanfer/web_object_detection)|在线 web 目标识别|前端端口：`8000`<br/>后端端口：`4000`|
  |[zfile](https://github.com/zfile-dev/zfile)|在线网盘（可从服务器同步配置信息）|`8080`|
  |[subconverter](https://github.com/tindy2013/subconverter)|订阅转换后端|`25500`|
  |[subweb](https://github.com/CareyWang/sub-web)|订阅转换前端|`58080`|
  |[mdserver-web](https://github.com/midoks/mdserver-web)|一款简单 Linux 面板服务|`7200` `80` `443` `888`|
  |[青龙面板](https://github.com/whyour/qinglong)|定时任务管理面板|`5700`|
  |[webdav-client](https://github.com/efrecon/docker-webdav-client)|Webdav 客户端，同步映射到宿主文件系统||
  |[watchtower](https://github.com/containrrr/watchtower)|自动化更新 Docker 镜像和容器||
  |[jsxm](https://github.com/a1k0n/jsxm)|Web 在线 xm 音乐播放器|`8081`|
  |[Caddy](https://caddyserver.com/)|反向代理服务，可将某个域名转发到宿主机本地服务|`80` `443`|
  |[codex2api](https://github.com/yyssp/codex2api)|Codex2API，一键拉取 compose 和 `.env.example`，自动生成密钥并在首次安装时分配空闲随机端口|随机|
  |[sub2api](https://github.com/Wei-Shaw/sub2api)|Sub2API，使用项目内置的 compose / `.env.example` / `Caddyfile` 参考模板，自动生成部署密钥并分配空闲随机端口|随机|

  所有通过 `docker compose` 安装的服务都会统一部署到 `/root/docker-compose/<service>/`，例如 `caddy` 会使用 `/root/docker-compose/caddy/docker-compose.yml`，`nginx` 会使用 `/root/docker-compose/nginx/docker-compose.yml`。

  这些服务的挂载目录也都收敛在各自目录下，compose 文件统一使用相对路径。例如 `code-server` 会使用 `/root/docker-compose/code-server/config/`，`nginx` 会使用 `/root/docker-compose/nginx/html/`，`caddy` 会使用 `/root/docker-compose/caddy/Caddyfile`、`/root/docker-compose/caddy/data/`、`/root/docker-compose/caddy/config/`。

  `caddy` 的部署目录为 `/root/docker-compose/caddy/`。安装时脚本会自动生成 `Caddyfile`，你只需要输入域名和本地服务地址，例如 `host.docker.internal:3000`。如果你是给 `sub2api` 做反代，安装/更新时还可以选择“适配 sub2api 的 Caddy 配置模板”，它会额外带上静态资源缓存、健康检查、来源 IP 透传、连接池和访问日志配置。请确保域名已解析到当前服务器，且 `80/443` 端口已放行并未被其他服务占用。

  `codex2api` 的部署目录默认在 `/root/docker-compose/codex2api/`，脚本会自动下载远程 `docker-compose.yml`、`.env.example`，首次部署时生成 `.env`，并补齐 `ADMIN_SECRET`、`DATABASE_PASSWORD`。首次安装会分配一个当前未占用的随机端口；如果本地已存在部署，则安装流程会直接提示改用更新；更新时默认沿用当前端口，仅在端口缺失或冲突时重新分配。

  `sub2api` 的部署目录默认在 `/root/docker-compose/sub2api/`。项目已将 `docker-compose.yml`、`docker-compose.local.yml`、`.env.example` 和 `Caddyfile` 参考模板内置到 `src/assets/sub2api/`，安装和更新时不再从上游仓库下载这些文件。首次部署会创建 `.env`，同时补齐 `POSTGRES_PASSWORD`、`JWT_SECRET`、`TOTP_ENCRYPTION_KEY`、管理员邮箱/密码，并同步一份 `Caddyfile.sub2api.example` 供反向代理参考。首次安装会分配一个当前未占用的随机端口；如果检测到已有部署文件，安装会直接停止，避免覆盖现有部署，并提示改用更新或先清理后重装。对于旧的本地目录版 `sub2api` 部署，脚本更新时会继续沿用原 compose 模式，避免在升级时自动切换到命名卷导致数据失联。
  
- 清理 APT 空间

## 一键脚本

国内加速：

```sh
if ! command -v sudo >/dev/null 2>&1; then
  echo "请先安装 sudo" >&2
  exit 1
fi
if command -v curl >/dev/null 2>&1; then
  sudo bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/2ue/Setup_server/main/Setup.sh)"
elif command -v wget >/dev/null 2>&1; then
  sudo bash -c "$(wget -qO- https://ghfast.top/https://raw.githubusercontent.com/2ue/Setup_server/main/Setup.sh)"
else
  echo "请先安装 curl 或 wget" >&2
  exit 1
fi
```

国外直连：

```sh
if ! command -v sudo >/dev/null 2>&1; then
  echo "请先安装 sudo" >&2
  exit 1
fi
if command -v curl >/dev/null 2>&1; then
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/2ue/Setup_server/main/Setup.sh)"
elif command -v wget >/dev/null 2>&1; then
  sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/2ue/Setup_server/main/Setup.sh)"
else
  echo "请先安装 curl 或 wget" >&2
  exit 1
fi
```

## 下载源偏好配置

脚本运行时会将下载源相关偏好写入 `~/.setup_server/preferences.conf`，也可以通过主菜单里的 `source_settings` 修改。

可用配置项：

- `SETUP_SERVER_GITHUB_PROXY=ask|on|off`
- `SETUP_SERVER_APT_MIRROR=ask|cn|skip`
- `SETUP_SERVER_DOCKER_INSTALL_SOURCE=ask|cn|official`
- `SETUP_SERVER_OH_MY_ZSH_SOURCE=ask|tuna|github`

## 源码结构

项目现在分成两层：

- `src/lib/`: 公共能力，例如下载、菜单注册、用户目录识别、交互提示。
- `src/modules/`: 业务模块，新增功能优先放这里。
- `src/assets/`: 内置资源，构建时直接打进最终脚本。
- `scripts/build.sh`: 纯 Bash 构建脚本，用来生成发布版 `Setup.sh`。

日常维护时不要直接改仓库根目录下的 `Setup.sh`，它是构建产物。

## 构建

```sh
./scripts/build.sh
```

构建后会生成：

- `Setup.sh`
- `dist/Setup.sh`

## 维护说明

- 当前仓库发布地址和一键安装入口都应使用 `2ue/Setup_server`。
- 上游仓库仍可作为功能来源参考，但不要再把 README 和发布命令写回 `Tsanfer/Setup_server`。
- 如修改了 `src/` 下源码，请先运行 `./scripts/build.sh` 再提交生成后的 `Setup.sh`。
- 新增的 `dev_toolchain` 模块会按官方方式执行 `curl https://get.volta.sh | bash`，因此目标机器需要可用的 `curl`。
