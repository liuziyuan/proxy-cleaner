#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLASH_VERGE_APP="/Applications/Clash Verge.app"
CLASH_PROCESS_NAME="clash-verge"

NETWORK_SERVICES=("AX88179A" "AX88179A 2" "AX88179A 3" "Thunderbolt Bridge" "Wi-Fi")

log_step() {
    echo -e "${YELLOW}➜ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

stop_clash_verge() {
    log_step "停止 Clash Verge..."
    
    if pgrep -x "$CLASH_PROCESS_NAME" > /dev/null; then
        pkill -x "$CLASH_PROCESS_NAME" 2>/dev/null || true
        sleep 2
        
        if pgrep -x "$CLASH_PROCESS_NAME" > /dev/null; then
            pkill -9 -x "$CLASH_PROCESS_NAME" 2>/dev/null || true
            sleep 1
        fi
        
        if ! pgrep -x "$CLASH_PROCESS_NAME" > /dev/null; then
            log_success "Clash Verge 已停止"
        else
            log_error "无法完全停止 Clash Verge"
        fi
    else
        echo "Clash Verge 未在运行"
    fi
}

reset_proxy_settings() {
    log_step "重置网络代理设置..."
    
    for service in "${NETWORK_SERVICES[@]}"; do
        if networksetup -getwebproxy "$service" &>/dev/null; then
            networksetup -setwebproxystate "$service" off 2>/dev/null || true
            networksetup -setsecurewebproxystate "$service" off 2>/dev/null || true
            networksetup -setsocksfirewallproxystate "$service" off 2>/dev/null || true
            networksetup -setwebproxy "$service" "" 0 2>/dev/null || true
            networksetup -setsecurewebproxy "$service" "" 0 2>/dev/null || true
            networksetup -setsocksfirewallproxy "$service" "" 0 2>/dev/null || true
            echo "  已重置: $service"
        fi
    done
    
    log_success "网络代理设置已重置"
}

flush_dns_cache() {
    log_step "清理 DNS 缓存..."
    
    sudo dscacheutil -flushcache 2>/dev/null || log_error "需要管理员权限刷新 DNS 缓存"
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    log_success "DNS 缓存已清理"
}

main() {
    echo "================================"
    echo "   代理清理工具 v1.0"
    echo "================================"
    echo ""
    
    stop_clash_verge
    echo ""
    
    reset_proxy_settings
    echo ""
    
    flush_dns_cache
    echo ""

    echo "================================"
    echo -e "${GREEN}✓ 清理完成！${NC}"
    echo "请手动激活 Clash Verge"
    echo "================================"
}

main
