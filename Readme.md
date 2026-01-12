# 🧟 Project Zomboid Docker Server (With Web Management)

这是一个自用的《僵尸毁灭工程》(Project Zomboid)  Docker 服务端方案。

## ✨ 1. 功能

* 🐳 全功能 Docker 化: 基于 Ubuntu 构建，内置 SteamCMD、Java 环境及中文语言环境支持。
* 🖥️ Web 可视化配置: 内置 Go 语言编写的 Web 后台，支持在线修改 servertest.ini (服务器设置) 和 sandbox.lua (沙盒设置)，支持热重载。
* 📂 网页文件管理: 集成 FileBrowser，无需 SSH/FTP 即可在网页端管理模组、地图存档及日志文件。
* 🔒 安全网关: 内置 Nginx 反向代理
* 🔐 自动 HTTPS: 集成 acme.sh，支持通过 Cloudflare DNS API 自动申请并续期 SSL 证书，亦支持自定义证书挂载。
* 🔄 自动更新:
  * 游戏更新: 容器启动/重启时自动检测并更新 PZ 服务端。
  * 面板更新: Web 面板支持在线一键检查更新并热重启。
* 🧱 持久化：游戏本体、存档、配置、面板数据与容器分离，方便改动以及保存。

## 🚀 2. 快速开始

### 2.1 环境要求：

* Docker
* Docker Compose
* WSL2

### 2.2 获取项目

```bash
git clone https://github.com/Asteroid77/pz-docker-server.git
# windows下直接打开目录即可
cd pz-docker-server
```

### 2.3 配置环境文件

> ⚠️ 注意: 请务必修改 .env 文件中的密码配置 (FILEBROWSERADMIN_PASSWORD, PZ_WEB_PASSWORD 等)，切勿使用默认密码！

打开项目目录下的`.env`文件，可选配置如下：

#### ⚙️ 环境变量配置 (.env)

在使用 `docker-compose up` 启动之前，请复制 `.env.example` 为 `.env` 并根据你的需求修改以下配置。



#### 📦 基础配置 (Basic)

| 变量名                       | 默认值                | 说明                                                         |
| :--------------------------- | :-------------------- | :----------------------------------------------------------- |
| `CONTAINER_NAME`             | `pz-automated-server` | Docker 容器的名称。                                          |
| `PORT_GAME_UDP`              | `16261`               | **主游戏端口 (UDP)**。玩家连接服务器时填写的端口。           |
| `PORT_GAME_HANDSHAKE`        | `16262`               | **握手端口 (UDP)**。用于 Steam 查询和直连。                  |
| `PORT_GAME_SETTING_EXT`      | `10888`               | **Web 面板端口**，默认为游戏配置，/filebrowser路径为文件管理。 |
| `FILEBROWSER_ADMIN_USERNAME` | `pzFileAdmin`         | **FileBrowser** 的默认管理员用户名。                         |
| `FILEBROWSER_ADMIN_PASSWORD` | `Adminadmin123`       | **FileBrowser** 的默认管理员密码。<br>⚠️ **注意**：必须 **>8位** 且包含字母数字，足够复杂，否则服务会启动失败。 |

#### 🛠️ 构建与网络 (Build & Network)

| 变量名                  | 默认值                             | 说明                                                         |
| :---------------------- | :--------------------------------- | :----------------------------------------------------------- |
| `PROXY_URL`             | `http://host.docker.internal:7890` | **HTTP 代理地址**。<br>用于加速 Docker 构建过程中的 SteamCMD 下载。<br>• **Windows/Mac**: `http://host.docker.internal:7890`<br>• **Linux**: 请填写宿主机局域网 IP (如 `192.168.1.5:7890`) |
| `USE_CN_MIRROR`         | `true`                             | 是否使用国内镜像源加速 `apt-get` 安装。<br>`true` = 使用阿里云源；`false` = 使用官方源。 |
| `GITHUB_PROXY_URL`      | `https://ghfast.top/`              | 配置GitHub专用加速前缀                                       |
| `DNS_SERVER_1`          | `223.5.5.5`                        | 容器内使用的DNS组1，此为阿里云的DNS，非国内构建无需填写。    |
| `DNS_SERVER_2`          | `119.29.29.29`                     | 容器内使用的DNS组2，此为腾讯云的DNS，非国内构建无需填写。    |
| `STEAMCMD_CN_MIRROR_ID` | `10`                               | Steam地区设置：<br />• **上海**: `44` <br />• **北京**: `23` <br />• **成都**: `45` <br />• **广州**: `43` <br />• **天津**：`47`（完美世界机房）<br />• **新加坡**：`10`<br />• **香港**：`11` |

#### 🔒 安全与 HTTPS (SSL/TLS)

设置`HTTPS`之后，脚本会自动帮你申请证书，并把申请到的`cert`以及`key`持久化到项目底下的`cert`文件夹中。

> ⚠️注意，请确定你提供的参数**正确无误**，申请证书是有频率限制的！
>
> 如果查看服务器启动日志时发现被证书机构拒绝，请你自行在你的电脑上面通过`win.acme`或者`acme.sh`之类的工具自行解决后把申请到的证书扔在`cert`文件夹内即可。
>
> **如果你没有公网IP，这一段可以略过，直接走内网穿透即可。**

| 变量名          | 默认值      | 说明                                                         |
| :-------------- | :---------- | :----------------------------------------------------------- |
| `SSL_MODE`      | `off`       | **HTTPS 模式选择**。<br>• `off`: 关闭 HTTPS (仅 HTTP)。<br>• `custom`: 使用自定义证书 (需挂载 `./certs` 目录)。<br>• `cloudflare`: 使用 Cloudflare API 自动申请证书。 |
| `DOMAIN_NAME`   | `localhost` | 你的服务器域名 (如 `pz.example.com`)。<br>仅当 SSL 模式开启时必须填写。 |
| `EMAIL`         | -           | 申请 SSL 证书时的联系邮箱 (用于到期通知)。<br>仅 `cloudflare` 模式需要。 |
| `SSL_CERT`      | `cert.pem`  | 自定义证书文件名 (位于 `./certs` 目录下)。<br>仅 `custom` 模式需要。 |
| `SSL_KEY`       | `key.pem`   | 自定义私钥文件名 (位于 `./certs` 目录下)。<br>仅 `custom` 模式需要。 |
| `CF_TOKEN`      | -           | Cloudflare API Token (需拥有 DNS 编辑权限)。                 |
| `CF_ACCOUNT_ID` | -           | Cloudflare Account ID。                                      |

#### 🎮 游戏配置 (Game Settings)

| 变量名                    | 默认值                          | 说明                                                         |
| :------------------------ | :------------------------------ | :----------------------------------------------------------- |
| `PZ_BRANCH`               | `public`                        | **游戏分支版本**。<br>• `public` / `latest`: 稳定版 (Build 41.78+)。<br>• `unstable` / `42.x.x`: 测试版 (Build 42)。 |
| `PZ_WEB_ACCOUNT`          | `pz`                            | **Nginx 基本认证用户名**。<br>用于保护 Web 管理面板的入口安全。 |
| `PZ_WEB_PASSWORD`         | `pzPassword123`                 | **Nginx 基本认证密码**。                                     |
| `PZ_SETTING_WEB_REPO`     | `Asteroid77/pz-web-backend`     | 面板依赖的仓库，你可以自行fork然后在此基础上修改，使用自己的Web面板。 |
| `PZ_WEB_BACKEND_FILENAME` | `pz-web-backend_linux_amd64Web` | 面板的文件名，根据这个检测最新的面板二进制文件。             |

#### 🌐 DDNS-GO（DDNS-GO Settings)

| 变量名              | 默认值 | 说明                   |
| ------------------- | ------ | ---------------------- |
| `PORT_DDNS_GO`      | `9876` | ddns-go暴露的端口      |
| `FREQUENCY_DDNS_GO` | `30`   | 单位秒，代表检测的频率 |

### 2.4 构建与启动

> ⚠️如果设置了代理，请开启代理的TUN模式

```bash
#先构建属于你自己的images
#时间可能会有点长（取决于你的网络环境）
docker-compose build
#启动
docker-compsoe up -d 
```

如果你使用的是`Docker-Desktop`，那可以直接点击查看你刚刚启动的容器，点进去即可查看日志，大致如下：

```bash
2026-01-11 11:23:43 --- 容器启动初始化 ---
2026-01-11 11:23:43 模式: SSL_MODE=off
2026-01-11 11:23:43 域名: DOMAIN_NAME=localhost
2026-01-11 11:23:43 正在给予文件权限...
2026-01-11 11:23:43 权限正确: /home/steam (跳过检查)
2026-01-11 11:23:43 权限正确: /opt/pzserver (跳过检查)
2026-01-11 11:23:43 权限正确: /opt/filebrowser (跳过检查)
2026-01-11 11:23:43 --- 初始化 Web 配置面板 ---
2026-01-11 11:23:43 检测到现有面板程序，跳过复制 (保留持久化版本)。
2026-01-11 11:23:43 提示: /certs 目录是只读的，跳过权限修改。
2026-01-11 11:23:43 --- 初始化 文件浏览器(FileBrowser)变量 ---
2026-01-11 11:23:43 --- FileBrowser 数据库已存在，跳过初始化 ---
2026-01-11 11:23:43 --- 启动进程管理器 ---
```

容器启动后，会在当前目录下生成 data 文件夹用于持久化数据：

```bash
.
├── certs/                  # 存放 HTTPS 证书 (SSL_MODE=custom 或 cloudflare 生成)
├── data/
│   ├── game/               # 游戏本体安装目录 (避免每次重启重新下载)
│   ├── zomboid/            # 核心数据：地图存档、配置文件(Server/)、数据库(db/)
│   ├── steam/              # Steam数据存放（主要是缓存登录凭证）
| 	├── filebrowser/        # 文件管理器（不满意Web管理面板功能时使用）
| 	├── ddns-go/            # ddns-go的目录
│   └── web-backend/        # Web管理面板的二进制文件及缓存数据
├── entrypoint.sh           # 初始化脚本
├── start-pz.sh             # 僵毁服务器初始化脚本
├── supervisord.conf        # supervisord多任务管理配置
├── Dockerfile              # 构建docker的配置
├── .env              		# 设置
└── docker-compose.yml      # 启动容器的配置
```

### 2.5 📖 访问与使用

启动成功后，你可以通过浏览器访问服务器。

> 开启了HTTPS跟没开启HTTPS访问的前缀不一样，这里以HTTPS为例。

* **Web管理面板**（修改僵毁Server.ini/SandboxVar.lua，重启服务器，更新服务器，模组增删改）
  * 地址: https://你的域名 (或 https://服务器IP:设置的端口)

  * 安全验证：浏览器会弹出登录框（Nginx Basic Auth），懒得单独给这玩意儿写权限。

  * 用户名：`.env`中的`PZ_WEB_ACCOUNT`
  * 密码：`.env`中的`PZ_WEB_PASSWORD`
* **FileBrowser文件管理器**（僵毁游戏文件管理，在你不满意Web管理面板时使用，简单地说就是上传 Mods、备份 Saves 文件夹、查看 pz-stdout.log 日志）
  * 地址： https://你的域名/filebrowser (或 https://服务器IP:设置的端口/filebrowser)
  * 安全验证：自带有一套权限系统
  * 用户：`.env` 中的 `FILEBROWSER_ADMIN_USERNAME`
  * 密码：`.env`中的`FILEBROWSER_ADMIN_PASSWORD`
* **[DDNS-GO](https://github.com/jeessy2/ddns-go)**（动态家宽IP绑定域名，字面意思，家庭宽带会因为拨号而变更IP，其作用就是不停轮询IP网站询问自己的公网IP）
  * 地址：localhost:9876(默认端口)
  * 用户名：第一次启动会让你自己设置
  * 密码：同上
  * Token: `.env`中的`CF_TOKEN`
  * TTL: 自动（默认）
  * IPV4
    * 是否启用-启用
    * 通过接口获取
    * domains - 输入你的域名，可以同HTTPS设置的一样，也可以自己多建个子域名。
  * 其它
    * 禁止公网访问：禁止（建议）

* 游戏端口: 没有提供修改项，反正这个放在Docker内你端口是随便映射的，默认就是`16261`跟`16262`，追求开箱即用。

* 游戏分支: `.env`中的`PZ_BARNCH`，就是僵毁里面的测试版本，填入你想要进行游玩的版本即可。

## 🛠️ 3. 常见问题 (FAQ)

### Q1: 服务器一直在重启或者无法启动？

请检查日志`docker-compose logs -f`或直接在对应docker网页端管理工具中查看.

一般来说可能会是网络问题，或者`.env`文件设置问题，具体问题具体分析，源码都在项目里面，与LLM对话即可，推荐`Gemini 3 Pro`

### Q2: 如何手动更新游戏？

直接重启容器即可：`docker-compose restart` 。

启动脚本会自动校验并更新游戏版本。

### Q3: 如何添加模组 (Mods)？

进入 Web 面板  -> Server 设置 -> 模组管理 -> 使用 Web 面板自带的 模组管理 功能自动解析。

或者使用`FileBrowser`找到`Server.ini`：

找到 WorkshopItems (填 Mod ID) 和 Mods (填 Mod 名称)。

保存并点击“更新并重启”。

算了，都是千年狐狸谈什么聊斋，真不懂去问LLM。

### Q4: 为什么修改了 .env 里的密码重启没生效？

`FileBrowser` 和 `Nginx` 的密码在首次初始化后会写入数据库或文件。

如果需要强制重置：

`FileBrowser`: 删除 `./data/filebrowser/database.db` 然后重启。

`Web 设置面板`: 删除容器内的 `/etc/nginx/.htpasswd` (或进入容器执行 `rm /etc/nginx/.htpasswd`) 然后重启。

### Q5: Web配置面板问题

关于面板，我单独拆分出了一个[仓库](https://github.com/Asteroid77/pz-web-backend)。

有什么问题可以去那边提。

如果你科学上网工具质量不太好，经常触发`Github`的风控，想要更新新版的面板，可以直接从面板仓库那边的`Release`中下载build好的版本放到`data/web-backend`下面自行更名替换，也可以改了后自己编译自己替换。

## 📝 4. License

MIT License