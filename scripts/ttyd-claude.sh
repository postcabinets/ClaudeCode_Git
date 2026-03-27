#!/bin/bash
# ttyd-claude.sh — スマホからClaude Codeにアクセスするためのttyd起動スクリプト
# tmuxセッションに自動接続（なければ作成）

SESSION_NAME="claude"
WORK_DIR="$HOME/claude for me"

# tmuxセッションが存在しなければ作成
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SESSION_NAME" -c "$WORK_DIR"
    # 最初のウィンドウ名を設定
    tmux rename-window -t "$SESSION_NAME:0" "main"
fi

# 接続（既存セッションにattach）
exec tmux attach-session -t "$SESSION_NAME"
