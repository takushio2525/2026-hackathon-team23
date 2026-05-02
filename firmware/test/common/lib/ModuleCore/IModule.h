// EMA 準拠の入出力モジュール抽象基底クラス
// SystemData は各ノードが include/SystemData.h で定義する前方宣言型
#pragma once

struct SystemData;

class IModule {
public:
    bool enabled = true;
    virtual ~IModule() = default;

    // ハードウェア初期化。成功で true。
    virtual bool init() { return true; }

    // 入力フェーズで呼ばれる。センサ値や受信結果を data に書く。
    virtual void updateInput(SystemData& data) { (void)data; }

    // 出力フェーズで呼ばれる。data の値をハードウェア／送信に反映する。
    virtual void updateOutput(SystemData& data) { (void)data; }

    // 後始末。基底側は空実装。
    virtual void deinit() {}
};
