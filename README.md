# 代理工具集

macOS + Clash Verge 代理环境的诊断与修复脚本集。

## 工具一览

| 脚本 | 定位 | 适用场景 |
|---|---|---|
| `net-doctor.sh` | **精准诊断修复**（日常首选） | 网站打不开、代理抽风；不停 Clash、不断 VPN，秒级幂等修复 |
| `clean_proxy.sh` | **全量重置**（彻底抽风时用） | 停 Clash → 关闭所有接口代理 → 清 DNS 缓存 → 手动重开 |

日常「打不开网站」先用 `net-doctor.sh`；反复抽风修不好时，再用 `clean_proxy.sh` 推倒重来。

## net-doctor.sh —— 一键诊断 + 修复

### 背景

Ivanti VPN 在线时会抢占系统 DNS 并使 Clash TUN 分流失效；Clash Verge 2.5.7 的系统代理开关存在
bug（sysproxy 损坏态：`Enabled: Yes` 但 Server 空、Port 0），浏览器随之裸奔直连，被墙网站
（GitHub / Google 等）报 `ERR_CONNECTION_RESET`。

### 故障全貌（2026-10-08 实战复盘）

**根因因果链**：

```
VPN 隧道建立
  └─ Pulse NC 服务（net.pulsesecure.pulse.nc.main）抢占系统主服务（PrimaryService）
       ├─ macOS 系统代理只看主服务 → verge sysproxy 报 "no active network service" 失效（开关点不动）
       └─ 主服务 State 层挂着 verge 历史遗留的坏代理字典（Enabled=1 但地址空/端口0）
            └─ 浏览器读到坏代理 → 全站打不开
```

**四层机制速查**：

| 层 | 诊断命令 | 谁在管 | 故障症状 |
|---|---|---|---|
| DNS 解析 | `scutil --dns` | VPN scoped DNS 抢占 | TUN fake-ip 劫持收不到查询 → 域名分流失效 |
| TUN 路由 | `netstat -rn` | mihomo（`0/1`+`128.0/1`） | VPN 在线时路由残缺（只剩 `128.0/1`） |
| 系统代理·配置层 | `networksetup -get*proxy` | verge（sysproxy 有 bug）/ net-doctor | Enabled 但 Server 空（写坏） |
| 系统代理·生效层 | `scutil --proxy`（主服务 Proxies 字典） | configd，**浏览器实际读取** | 全禁 / 坏字典 / 死代理 |

**修复手段矩阵**：

| 病灶 | 手段 | 权限 |
|---|---|---|
| Wi-Fi 等常规服务代理坏 | `networksetup -set{web,secureweb,socksfirewall}proxy` | 用户 |
| 主服务是 VPN NC 服务（networksetup 够不着，不在其服务列表） | `sudo scutil` 写 `State:/Network/Service/<主服务>/Proxies` | sudo |
| mihomo 未运行 | `open -a "Clash Verge"` | 用户 |

**scutil `d.add` 语法陷阱**：裸值即字符串（`d.add HTTPProxy 127.0.0.1`）；`#`=数字、`*`=数组。
多写一个 `s`（如 `d.add HTTPProxy s 127.0.0.1`）会把值写成 array，configd 校验类型失败**拒绝采纳**
——主服务字典看似写对，全局投影依然全禁，修了等于没修。

**修复成功的唯一验证标准**：`scutil --proxy` 出现 `HTTPEnable:1 / HTTPProxy 127.0.0.1 / HTTPPort 7897`。
主服务字典写对 ≠ 生效。

**关停场景行为**：

| 场景 | 行为 | 结果 |
|---|---|---|
| 只关 VPN（Clash 开着） | 主服务切回 Wi-Fi，其代理 7897 生效 | ✅ 干净 |
| 只关 Clash（VPN 开着） | 7897 死端口但代理配置仍启用 | ❌ 死代理断网 → 脚本安全网自动降级直连 |
| VPN + Clash 都关 | 死代理挂在 Wi-Fi 配置上 | ❌ 同上 |

### 功能

- ✓ 检测 Ivanti VPN / Clash 内核运行状态，识别「VPN 共存模式」与「TUN 分流模式」
- ✓ 实测代理端口 `127.0.0.1:7897`（mihomo 以 root 服务模式运行，lsof 看不到，必须 curl 实测）
- ✓ 检测并修复系统代理损坏态：**HTTP / HTTPS / SOCKS 三处都查**
  （Chromium 系浏览器如 Edge 优先走 SOCKS，SOCKS 损坏时全站打不开）
- ✓ 关键站点连通性实测（穿代理）：GitHub / Google / `api.anthropic.com`（Claude Code）/ `claude.ai`
- ✓ Clash 内核未运行时自动拉起 Clash Verge；拉起失败自动清除死代理降级直连（防断网安全网）
- ✓ 彩色输出；`-n` dry-run 只诊断不修改；幂等（已是正确值则零修改）

### 使用方法

```bash
~/proxy-cleaner/net-doctor.sh      # 诊断 + 安全修复
~/proxy-cleaner/net-doctor.sh -n   # 只诊断，不修改（dry-run）
```

也可直接双击 `net-doctor.command` 运行。

### 原则

1. **绝不断开 VPN**（办公必需）；VPN 在线时确保浏览器走系统代理即可正常上网
2. 只做可逆修复（`networksetup` 重置三处代理、`open -a "Clash Verge"`）；需要 sudo 的操作只提示命令，不自动执行

---

## clean_proxy.sh —— 全量重置

自动清理 macOS 代理设置的 Shell 脚本，适用于 Clash Verge VPN 客户端。

### 功能

- ✓ 自动停止 Clash Verge
- ✓ 重置所有网络接口的代理设置
- ✓ 清理 DNS 缓存
- ✓ 自动重启 Clash Verge
- ✓ 彩色输出，清晰的状态反馈

### 使用方法

#### 方法 1: 双击运行（推荐）

直接双击 `clean_proxy.command` 文件即可运行。

#### 方法 2: 终端运行

```bash
~/proxy-cleaner/clean_proxy.sh
```

#### 方法 3: 创建快捷方式

1. 打开 **Automator** 应用
2. 新建 **快速操作**
3. 选择 **运行 Shell 脚本**
4. 输入: `~/proxy-cleaner/clean_proxy.sh`
5. 保存为 "清理代理"
6. 在 **系统设置 > 键盘 > 键盘快捷键** 中添加快捷键

### 支持的网络接口

- AX88179A
- AX88179A 2
- AX88179A 3
- Thunderbolt Bridge
- Wi-Fi

### 系统要求

- macOS 10.15+
- Clash Verge 客户端

### 注意事项

- 清理 DNS 缓存需要管理员权限，会提示输入密码
- 脚本会尝试优雅关闭 Clash Verge，如失败则强制关闭
- 如果有其他 VPN 软件需要修改脚本中的进程名称

### 自定义配置

如果需要修改网络接口列表，编辑 `clean_proxy.sh` 中的 `NETWORK_SERVICES` 数组：

```bash
NETWORK_SERVICES=("接口1" "接口2" "Wi-Fi")
```

查看所有可用网络接口：

```bash
networksetup -listallnetworkservices
```

### 故障排查

如果脚本无法正常工作：

1. 检查 Clash Verge 路径是否正确：`/Applications/Clash Verge.app`
2. 检查进程名称：`pgrep clash-verge`
3. 手动清理 DNS：`sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`
