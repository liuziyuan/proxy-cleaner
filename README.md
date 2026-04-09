# 代理清理工具

自动清理 macOS 代理设置的 Shell 脚本，适用于 Clash Verge VPN 客户端。

## 功能

- ✓ 自动停止 Clash Verge
- ✓ 重置所有网络接口的代理设置
- ✓ 清理 DNS 缓存
- ✓ 自动重启 Clash Verge
- ✓ 彩色输出，清晰的状态反馈

## 使用方法

### 方法 1: 双击运行（推荐）

直接双击 `clean_proxy.command` 文件即可运行。

### 方法 2: 终端运行

```bash
~/proxy-cleaner/clean_proxy.sh
```

### 方法 3: 创建快捷方式

1. 打开 **Automator** 应用
2. 新建 **快速操作**
3. 选择 **运行 Shell 脚本**
4. 输入: `~/proxy-cleaner/clean_proxy.sh`
5. 保存为 "清理代理"
6. 在 **系统设置 > 键盘 > 键盘快捷键** 中添加快捷键

## 支持的网络接口

- AX88179A
- AX88179A 2
- AX88179A 3
- Thunderbolt Bridge
- Wi-Fi

## 系统要求

- macOS 10.15+
- Clash Verge 客户端

## 注意事项

- 清理 DNS 缓存需要管理员权限，会提示输入密码
- 脚本会尝试优雅关闭 Clash Verge，如失败则强制关闭
- 如果有其他 VPN 软件需要修改脚本中的进程名称

## 自定义配置

如果需要修改网络接口列表，编辑 `clean_proxy.sh` 中的 `NETWORK_SERVICES` 数组：

```bash
NETWORK_SERVICES=("接口1" "接口2" "Wi-Fi")
```

查看所有可用网络接口：

```bash
networksetup -listallnetworkservices
```

## 故障排查

如果脚本无法正常工作：

1. 检查 Clash Verge 路径是否正确：`/Applications/Clash Verge.app`
2. 检查进程名称：`pgrep clash-verge`
3. 手动清理 DNS：`sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`
