#!/usr/bin/env bash
# ============================================================================
#  sound_lab アナライザ起動スクリプト
#  - macOS: Finder でこのファイルをダブルクリック → Terminal で起動します
#  - 初回だけ仮想環境(.venv)の作成と依存(librosa 等)のインストールを自動で行います
#  - 起動後、ブラウザが自動で http://127.0.0.1:5005 を開きます
#  - 止めるにはこのウィンドウで Ctrl+C
# ============================================================================
set -e
cd "$(dirname "$0")"

PYBIN="python3"
command -v "$PYBIN" >/dev/null 2>&1 || PYBIN="python"
command -v "$PYBIN" >/dev/null 2>&1 || { echo "Python 3 が見つかりません。https://www.python.org/ からインストールしてください。"; exit 1; }

if [ ! -d .venv ]; then
  echo "▶ 初回セットアップ: 仮想環境を作成して依存をインストールします（数分かかります）…"
  "$PYBIN" -m venv .venv
  ./.venv/bin/python -m pip install --upgrade pip
  ./.venv/bin/python -m pip install -r requirements.txt
fi

# 依存が欠けていたら入れ直す
./.venv/bin/python -c "import flask, librosa, soundfile, numpy" >/dev/null 2>&1 || {
  echo "▶ 依存を再インストールします…"
  ./.venv/bin/python -m pip install -r requirements.txt
}

echo "▶ サーバを起動します。ブラウザが開かなければ http://127.0.0.1:5005 を手で開いてください。"
exec ./.venv/bin/python app.py
