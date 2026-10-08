#!/usr/bin/env bash
# net-doctor.sh —— 诊断并修复「Ivanti VPN × Clash Verge」共存环境的网络
#
# 背景：Ivanti VPN 在线时会抢占系统 DNS 并使 Clash TUN 分流失效；
#       Clash Verge 2.5.7 的系统代理开关偶发写坏（Enabled 但 Server 空/Port 0），
#       浏览器随之裸奔直连，被墙网站（GitHub 等）报 ERR_CONNECTION_RESET。
#
# 用法：
#   net-doctor.sh          诊断 + 安全修复（修复系统代理损坏态、拉起未运行的 Clash Verge）
#   net-doctor.sh -n       只诊断，不做任何修改（dry-run）
#
# 原则：
#   1. 绝不断开 VPN（办公必需）；VPN 在线时确保浏览器走系统代理 127.0.0.1:7897
#   2. 只做可逆修复；需要 sudo 的操作只提示命令，不自动执行
set -uo pipefail

PROXY_HOST="127.0.0.1"
PROXY_PORT="7897"
PROXY_ADDR="${PROXY_HOST}:${PROXY_PORT}"
TEST_URL="https://github.com"
# 关键站点诊断清单：浏览器与日常 AI 工具的入口域名（穿代理逐个实测）
DIAG_URLS=(
  "https://github.com"
  "https://www.google.com"
  "https://api.anthropic.com"   # Claude Code API 端点
  "https://claude.ai"
)
DRY_RUN=0
[[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ---------- 输出工具 ----------
if [[ -t 1 ]]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi
ok()   { printf '  %s[ OK ]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %s[WARN]%s %s\n' "$C_Y" "$C_0" "$*"; }
bad()  { printf '  %s[FAIL]%s %s\n' "$C_R" "$C_0" "$*"; }
info() { printf '  %s[ .. ]%s %s\n' "$C_B" "$C_0" "$*"; }
fix()  { printf '  %s[FIX ]%s %s\n' "$C_G" "$C_0" "$*"; }
hdr()  { printf '\n%s== %s ==%s\n'  "$C_B" "$*" "$C_0"; }

FIXED=0   # 本次是否做过修改

# ---------- 环境探测 ----------
# 当前默认路由对应的网络服务名（避免硬编码 "Wi-Fi"）
detect_net_service() {
  local iface svc
  iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  if [[ -n "$iface" ]]; then
    svc=$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$iface" '
      /^Hardware Port: / { p=substr($0,16) }
      /^Device: / && $2==dev { print p; exit }')
    [[ -n "$svc" ]] && { NET_SERVICE="$svc"; return; }
  fi
  NET_SERVICE="Wi-Fi"   # 兜底
}

# mihomo 内核是否在跑（root 服务模式，ps 能看到）
mihomo_running() { pgrep -fq "verge-mihomo"; }

# Clash Verge GUI 是否在跑
verge_gui_running() { pgrep -fq "Clash Verge.app/Contents/MacOS/clash-verge"; }

# 代理端口实测（普通用户 lsof 看不到 root 进程的监听端口，必须 curl 实测）
# 注意：curl 失败时 -w 也会输出 000，不能用 "|| echo 000" 兜底（会产生 000\n000 混淆判等），
# 用正则 ^[1-9][0-9]{2}$ 只认真实的三位非零状态码
proxy_alive() {
  local code
  code=$(curl -s --max-time 6 -x "http://${PROXY_ADDR}" -o /dev/null \
         -w '%{http_code}' "$TEST_URL" 2>/dev/null)
  [[ "$code" =~ ^[1-9][0-9]{2}$ ]]
}

# 读系统代理配置，输出 "enabled|server|port"；$1 = webproxy | securewebproxy
read_sysproxy() {
  local out en srv prt
  out=$(networksetup -get"$1" "$NET_SERVICE" 2>/dev/null)
  en=$(awk -F': ' '/^Enabled:/{print $2}' <<<"$out")
  srv=$(awk -F': ' '/^Server:/{print $2}' <<<"$out")
  prt=$(awk -F': ' '/^Port:/{print $2}' <<<"$out")
  echo "${en:-}|${srv:-}|${prt:-}"
}

# 单项系统代理检查；$1 = webproxy | securewebproxy；$2 = 中文标签
# 返回 0 = 无需修复，1 = 需要修复
check_sysproxy_one() {
  local kind="$1" label="$2" en srv prt
  IFS='|' read -r en srv prt <<<"$(read_sysproxy "$kind")"
  if [[ "$en" == "Yes" && "$srv" == "$PROXY_HOST" && "$prt" == "$PROXY_PORT" ]]; then
    ok "系统代理（${label}）已正确 → ${PROXY_ADDR}"
    return 0
  elif [[ "$en" == "Yes" && ( -z "$srv" || "$prt" == "0" ) ]]; then
    # verge 2.5.7 sysproxy bug 的典型损坏态
    bad "系统代理（${label}）处于损坏态：Enabled=Yes 但 Server='${srv:-空}' Port='${prt:-空}'"
    return 1
  else
    warn "系统代理（${label}）：Enabled=${en:-无} Server='${srv:-空}' Port='${prt:-空}'"
    return 1
  fi
}

# ---------- 主流程 ----------
detect_net_service

hdr "1. 运行环境"
if pgrep -fq "Ivanti Secure Access|Pulse Secure"; then
  VPN_ON=1
  info "Ivanti VPN：在线（TUN 域名分流预期失效，属正常共存现象）"
else
  VPN_ON=0
  ok "Ivanti VPN：未运行"
fi
if mihomo_running; then
  ok "Clash 内核（verge-mihomo）：运行中"
else
  bad "Clash 内核（verge-mihomo）：未运行"
fi
if [[ "$VPN_ON" == "1" ]]; then
  warn "当前为「VPN 共存模式」：Clash TUN 分流不生效是预期行为，浏览器依赖系统代理"
else
  info "当前为「TUN 分流模式」"
fi

hdr "2. 代理端口与系统代理"
if proxy_alive; then
  ok "代理端口 ${PROXY_ADDR}：可用（穿代理访问 ${TEST_URL} 成功）"

  need_fix=0
  check_sysproxy_one webproxy     "HTTP"  || need_fix=1
  check_sysproxy_one securewebproxy "HTTPS" || need_fix=1
  # SOCKS 也必须查：Chromium 系浏览器在 SOCKS 启用时会优先走 SOCKS，
  # verge sysproxy bug 同样会把它写成 Enabled 但 Server 空，导致全站打不开
  check_sysproxy_one socksfirewallproxy "SOCKS" || need_fix=1

  if (( need_fix )); then
    if (( DRY_RUN )); then
      warn "[dry-run] 将执行：networksetup -setwebproxy/-setsecurewebproxy/-setsocksfirewallproxy \"${NET_SERVICE}\" ${PROXY_HOST} ${PROXY_PORT}"
    else
      networksetup -setwebproxy     "$NET_SERVICE" "$PROXY_HOST" "$PROXY_PORT"
      networksetup -setsecurewebproxy "$NET_SERVICE" "$PROXY_HOST" "$PROXY_PORT"
      networksetup -setsocksfirewallproxy "$NET_SERVICE" "$PROXY_HOST" "$PROXY_PORT"
      FIXED=1
      fix "系统代理（HTTP+HTTPS）已重置为 ${PROXY_ADDR}"
    fi
  fi
else
  bad "代理端口 ${PROXY_ADDR}：不可用"
  if mihomo_running; then
    warn "内核在跑但端口不通 → 请在 Clash Verge 界面「设置 → 重启内核」（需 sudo 的操作不自动执行）"
  elif verge_gui_running; then
    warn "Clash Verge 界面在跑但内核未启动 → 请在界面里重选订阅/重启内核"
  elif (( DRY_RUN )); then
    warn "[dry-run] 将执行：open -a \"Clash Verge\" 拉起 Clash Verge"
  else
    info "尝试拉起 Clash Verge..."
    open -a "Clash Verge" 2>/dev/null || bad "无法拉起 Clash Verge，请手动打开"
    for i in {1..15}; do
      sleep 2
      mihomo_running && proxy_alive && break
    done
    if proxy_alive; then
      FIXED=1
      fix "Clash Verge 已拉起，代理端口 ${PROXY_ADDR} 恢复可用"
    else
      bad "拉起后 ${PROXY_ADDR} 仍不可用，请手动打开 Clash Verge 检查订阅"
    fi
  fi
fi

hdr "3. 主服务生效层（scutil State，浏览器实际读取的数据源）"
# macOS 系统代理只看「主服务」（PrimaryService）的 Proxies 字典。
# Ivanti VPN 隧道建立后其 Pulse NC 服务会成为主服务，verge sysproxy 对此报
# "no active network service" 而失效；主服务上的坏字典 networksetup 够不着
# （不在其服务列表），只能 scutil 写 State 层（需 root）。
PRIMARY_SVC=$(echo 'show State:/Network/Global/IPv4' | scutil | awk -F': ' '/PrimaryService/{gsub(/ /,"",$2); print $2}')
if [[ -z "$PRIMARY_SVC" ]]; then
  bad "无法读取系统主服务"
else
  info "系统主服务：${PRIMARY_SVC}"
  PDICT=$(echo "show State:/Network/Service/${PRIMARY_SVC}/Proxies" | scutil)
  http_en=$(awk  -F': ' '/HTTPEnable/{gsub(/ /,"",$2); print $2}'   <<<"$PDICT")
  http_px=$(awk  -F': ' '/^ *HTTPProxy /{gsub(/ /,"",$2); print $2}' <<<"$PDICT")
  http_pt=$(awk  -F': ' '/HTTPPort/{gsub(/ /,"",$2); print $2}'     <<<"$PDICT")
  socks_en=$(awk -F': ' '/SOCKSEnable/{gsub(/ /,"",$2); print $2}'  <<<"$PDICT")
  socks_px=$(awk -F': ' '/^ *SOCKSProxy /{gsub(/ /,"",$2); print $2}' <<<"$PDICT")
  socks_pt=$(awk -F': ' '/SOCKSPort/{gsub(/ /,"",$2); print $2}'    <<<"$PDICT")

  PDIRTY=0
  if [[ "$http_en" == "1" && ( -z "$http_px" || "$http_pt" == "0" ) ]]; then
    bad "主服务 HTTP 代理损坏态：Enabled=1 但 Server='${http_px:-空}' Port='${http_pt:-空}'"
    PDIRTY=1
  elif [[ "$socks_en" == "1" && ( -z "$socks_px" || "$socks_pt" == "0" ) ]]; then
    bad "主服务 SOCKS 代理损坏态：Enabled=1 但 Server='${socks_px:-空}' Port='${socks_pt:-空}'"
    PDIRTY=1
  elif [[ "$http_en" == "1" && "$http_px" == "$PROXY_HOST" && "$http_pt" == "$PROXY_PORT" ]]; then
    ok "主服务生效层代理正确 → ${PROXY_ADDR}"
  elif [[ "$http_en" != "1" ]]; then
    if [[ "$VPN_ON" == "1" ]]; then
      warn "主服务生效层代理关闭 + VPN 在线 → 浏览器将裸奔直连被墙站"
      PDIRTY=1
    else
      info "主服务生效层代理关闭（无 VPN 时由 TUN 分流接管，正常）"
    fi
  fi

  if (( PDIRTY )); then
    if (( DRY_RUN )); then
      warn "[dry-run] 将执行：sudo scutil 改写 State:/Network/Service/${PRIMARY_SVC}/Proxies"
    else
      info "需要管理员权限改写生效层（将提示输入密码）..."
      if sudo scutil <<EOF
d.init
d.add FTPPassive # 1
d.add HTTPEnable # 1
d.add HTTPPort # ${PROXY_PORT}
d.add HTTPProxy s ${PROXY_HOST}
d.add HTTPSEnable # 1
d.add HTTPSPort # ${PROXY_PORT}
d.add HTTPSProxy s ${PROXY_HOST}
d.add SOCKSEnable # 1
d.add SOCKSPort # ${PROXY_PORT}
d.add SOCKSProxy s ${PROXY_HOST}
set State:/Network/Service/${PRIMARY_SVC}/Proxies
EOF
      then
        FIXED=1
        fix "主服务生效层代理已改写为 ${PROXY_ADDR}（VPN 重连后若复发，重跑本脚本即可）"
      else
        bad "sudo 改写失败（取消或失败），生效层未修复"
      fi
    fi
  fi
fi

hdr "4. 关键站点连通性（穿代理实测）"
SITES_ALL_OK=1
if proxy_alive; then
  info "说明：401/403/404 等响应均代表网络层可达（服务端正常应答，如 API 拒绝无凭证请求属正常）"
  for u in "${DIAG_URLS[@]}"; do
    code=$(curl -s --max-time 8 -x "http://${PROXY_ADDR}" -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
    if [[ "$code" =~ ^[1-9][0-9]{2}$ ]]; then
      ok "${u} → HTTP ${code}"
    else
      bad "${u} → 不通（当前节点对此站点异常，尝试切换节点）"
      SITES_ALL_OK=0
    fi
  done
else
  SITES_ALL_OK=0
  bad "代理不可用，跳过站点测试"
fi

hdr "5. 直连对照（展示用，不作修复依据）"
dcode=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "$TEST_URL" 2>/dev/null)
if [[ ! "$dcode" =~ ^[1-9][0-9]{2}$ ]]; then
  info "裸直连 ${TEST_URL}：被阻断（GFW 常态，正因如此必须走代理）"
else
  info "裸直连 ${TEST_URL}：HTTP ${dcode}"
fi

hdr "结论"
if (( FIXED )); then
  echo "  已做修复。请【完全退出并重启浏览器】（Edge: Cmd+Q）后重试。"
elif (( SITES_ALL_OK )); then
  echo "  网络环境正常，全部关键站点可达。"
else
  echo "  存在异常项：代理不可用→见第 2 节；主服务生效层损坏→见第 3 节（需输密码）；单站点不通→切换节点。"
fi
exit 0
