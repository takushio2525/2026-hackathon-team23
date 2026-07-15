// メインループ (main.cpp の loop() 関数) -- 本番動作の抜粋
// 計測ブロック (#if MOP_TEST) およびデバッグ出力 (#if SERIAL_DEBUG) を
// 除いた本番動作を示す。指揮者・楽器で構造が異なるため両方を掲載する。

// ======== 楽器ノード (node_02--node_06) ========

// 入力フェーズで呼ぶモジュール: WiFi受信, 受信処理(時計同期/発音予約登録)
IModule* gInputs[]  = { &gNet, &gRecv };
// 出力フェーズで呼ぶモジュール: NOTE送信, UI中継, LED, UDP送信
IModule* gOutputs[] = { &gNote, &gUi, &gLed, &gNet };

uint32_t gLastLoopMs = 0;

void loop() {
    const uint32_t now = millis();
    if (now - gLastLoopMs < ORC_RECEIVER_CONFIG.loopIntervalMs) {
        return;  // loopIntervalMs 周期を維持
    }
    gLastLoopMs = now;

    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    applyPattern(gData);
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
}

// ======== 指揮者ノード (node_01) ========
// 楽器と異なり明示的な周期制御はない。IMU モジュールの内部
// サンプリング周期 (約5 ms) がループの実効周期を決める。

// 入力フェーズで呼ぶモジュール: WiFi受信, IMU読取
IModule* gInputs[]  = { &gNet, &gImu };
// 出力フェーズで呼ぶモジュール: CTRL/BEAT送信, LED, UDP送信
IModule* gOutputs[] = { &gSender, &gLed, &gNet };

void loop() {
    for (auto* m : gInputs) {
        if (m->enabled) m->updateInput(gData);
    }
    applyPattern(gData);
    for (auto* m : gOutputs) {
        if (m->enabled) m->updateOutput(gData);
    }
}
