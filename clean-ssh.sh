#!/bin/bash

agent_pids=$(pgrep -u "$USER" ssh-agent)

if [ -n "$agent_pids" ]; then
    echo "找到以下SSH代理进程:"
    echo "$agent_pids" | while read pid; do
        ps -p "$pid" -o pid,ppid,args
    done
    echo ""
    echo "正在终止SSH代理进程..."
    kill $agent_pids 2>/dev/null
    sleep 1
    remaining=$(pgrep -u "$USER" ssh-agent)
    if [ -n "$remaining" ]; then
        echo "强制终止剩余SSH代理进程..."
        kill -9 $remaining 2>/dev/null
    fi
else
    echo "没有找到SSH代理进程"
fi

echo ""
echo "查找SSH隧道进程(排除git连接)..."

tunnel_pids=$(ps aux | grep -E 'ssh.*-[LR]' | grep -v grep | grep -v git@ | grep -v git-upload-pack | grep -v git-receive-pack | awk '{print $2}')

if [ -n "$tunnel_pids" ]; then
    echo "找到以下SSH隧道进程:"
    echo "$tunnel_pids" | while read pid; do
        ps -p "$pid" -o pid,ppid,args
    done
    echo ""
    echo "正在终止SSH隧道进程..."
    kill $tunnel_pids 2>/dev/null
    sleep 1
    remaining=$(ps aux | grep -E 'ssh.*-[LR]' | grep -v grep | grep -v git@ | grep -v git-upload-pack | grep -v git-receive-pack | awk '{print $2}')
    if [ -n "$remaining" ]; then
        echo "强制终止剩余SSH隧道进程..."
        kill -9 $remaining 2>/dev/null
    fi
else
    echo "没有找到SSH隧道进程"
fi

echo ""
echo "清理完成"
