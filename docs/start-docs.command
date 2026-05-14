#!/usr/bin/env bash
# このファイルをダブルクリックすると、ドキュメントサイトのローカルサーバーが立ち上がり、
# ブラウザ（Google Chrome があれば Chrome、無ければデフォルトブラウザ）が自動で開く。
# 終了するときはこのターミナルウィンドウで Ctrl+C → 閉じる。

set -e
cd "$(dirname "$0")"

# 初回のみ依存ライブラリをインストール
if [ ! -d node_modules ]; then
    echo "================================================================"
    echo "  初回起動: npm install を実行します（数分かかります）"
    echo "================================================================"
    npm install
    echo ""
fi

# サーバー起動後にブラウザを自動で開く（3 秒待ってから）
open_url() {
    sleep 3
    if [ -d "/Applications/Google Chrome.app" ]; then
        open -a "Google Chrome" "http://localhost:4321"
    else
        open "http://localhost:4321"
    fi
}
open_url &

echo "================================================================"
echo "  ドキュメントサイトを起動します"
echo "  URL: http://localhost:4321"
echo "  終了するには Ctrl+C を押してください"
echo "================================================================"
echo ""

npm run dev
