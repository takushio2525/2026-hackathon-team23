"""音源解析ツールのバックエンド(Flask)。

- GET  /            : フロント(static/index.html)を返す
- POST /analyze     : アップロードされた音源を解析し {"instrument":..., "preview":...} を返す
- GET  /samples/<f> : analyzer/samples/ に置いたファイルをそのまま配る(動作確認用)

起動:
    pip install -r requirements.txt
    python app.py            # → http://127.0.0.1:5005
"""

from __future__ import annotations

import os
import tempfile
import threading
import traceback
import webbrowser

from flask import Flask, jsonify, request, send_from_directory

from analyzer import AnalysisError, analyze_file

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")
SAMPLES_DIR = os.path.join(BASE_DIR, "samples")
HOST, PORT = "127.0.0.1", 5005
URL = f"http://{HOST}:{PORT}"
DEBUG = True                       # コード変更を即反映したくない場合は False に
MAX_UPLOAD_MB = 32
ALLOWED_EXT = {".wav", ".flac", ".ogg", ".mp3", ".aiff", ".aif", ".m4a"}

app = Flask(__name__, static_folder=None)
app.config["MAX_CONTENT_LENGTH"] = MAX_UPLOAD_MB * 1024 * 1024


@app.get("/")
def index():
    return send_from_directory(STATIC_DIR, "index.html")


@app.get("/static/<path:filename>")
def static_files(filename: str):
    return send_from_directory(STATIC_DIR, filename)


@app.get("/samples/<path:filename>")
def samples(filename: str):
    return send_from_directory(SAMPLES_DIR, filename)


@app.post("/analyze")
def analyze():
    if "file" not in request.files:
        return jsonify(error="ファイルが添付されていません。"), 400
    f = request.files["file"]
    if not f.filename:
        return jsonify(error="ファイル名が空です。"), 400
    ext = os.path.splitext(f.filename)[1].lower()
    if ext not in ALLOWED_EXT:
        return jsonify(error=f"対応していない拡張子です({ext})。対応: {', '.join(sorted(ALLOWED_EXT))}"), 400

    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(suffix=ext)
        os.close(fd)
        f.save(tmp_path)
        result = analyze_file(tmp_path, name=os.path.splitext(os.path.basename(f.filename))[0])
        return jsonify(result)
    except AnalysisError as e:
        return jsonify(error=str(e)), 422
    except Exception as e:  # 想定外
        traceback.print_exc()
        return jsonify(error=f"解析中にエラーが発生しました: {e}"), 500
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.errorhandler(413)
def too_large(_e):
    return jsonify(error=f"ファイルが大きすぎます(上限 {MAX_UPLOAD_MB} MB)。"), 413


def _open_browser_later():
    threading.Timer(1.2, lambda: webbrowser.open(URL)).start()


if __name__ == "__main__":
    os.makedirs(SAMPLES_DIR, exist_ok=True)
    # debug=True だとリローダで子プロセスが立つ。ブラウザは実際に配信する側だけで一度だけ開く
    if not DEBUG or os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        _open_browser_later()
    print(f"sound_lab analyzer  ->  {URL}   (止めるには Ctrl+C)")
    app.run(host=HOST, port=PORT, debug=DEBUG)
