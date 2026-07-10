// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/production/node_01     # 指揮者ノード (SoftAp)
//   pio run -d firmware/production/node_02     # 楽器 1 (Sta)

#include "OrcNetModule.h"
#include "SystemData.h"  // 各ノードが提供 (build_flags = -I include)
#include "SerialDebug.h"
#include <string.h>

#if defined(ARDUINO_ARCH_ESP32)
#include <esp_wifi.h>  // SoftAp のビーコン間隔調整 (esp_wifi_get_config / esp_wifi_set_config)
#endif

bool OrcNetModule::init() {
    bool ok = (cfg_.mode == WifiMode::SoftAp) ? startSoftAp() : connectSta();
    if (ok) started_ = true;
    // 起動直後のリンク状態を控えておく。これをしないと最初の updateInput() で
    // 「false→true 遷移」と誤認して不要な再 join が 1 回走る。
    wasLinkUp_ = isLinkUp();
    return ok;
}

bool OrcNetModule::startSoftAp() {
#if defined(ARDUINO_ARCH_ESP32)
    WiFi.mode(WIFI_AP);
    if (!WiFi.softAP(cfg_.ssid, cfg_.pass, cfg_.channel, 0, 6)) {
        return false;
    }
    // SoftAP のマルチキャストは省電力 STA がいると DTIM ビーコンまでバッファされ、
    // 既定ビーコン間隔 100TU (102.4ms) では実測 204.8ms (2 ビーコン) 周期のバースト
    // 配送になる (tools/verification/results/MOP5_systematic_shift_analysis_20260710.md §3/§8 案2)。
    // ビーコン間隔を 50TU に短縮してフラッシュ周期を ~51ms 程度へ縮める。
    // 注意:
    //   - この arduino-esp32 2.0.17 (IDF 4.4) の wifi_ap_config_t には dtim_period
    //     フィールドが存在しない (IDF 5.x で追加) ため、DTIM=1 の明示設定は不可。
    //   - ヘッダ記載のレンジは 100〜60000TU で、50 は範囲外として拒否される可能性が
    //     ある。get/set のどちらが失敗しても既定 (100TU) のまま続行し、AP 起動自体は
    //     成功扱いにする (演奏は従来どおり成立し、バースト周期だけ 204.8ms に戻る)。
    //   - 効果 (バースト周期の短縮) は STA 側モジュールのリッスン間隔にも依存する
    //     ため、実機の再計測ログで到着周期を確認すること。
    {
        wifi_config_t wcfg;
        if (esp_wifi_get_config(WIFI_IF_AP, &wcfg) == ESP_OK) {
            wcfg.ap.beacon_interval = 50;
            const esp_err_t err = esp_wifi_set_config(WIFI_IF_AP, &wcfg);
            DBG_PRINTF("[NET] softAP beacon_interval=50TU -> %s\n",
                       (err == ESP_OK) ? "OK" : "REJECTED (100TU のまま)");
        } else {
            DBG_PRINTLN("[NET] esp_wifi_get_config failed (beacon 既定のまま)");
        }
    }
    delay(100);
    // SoftAp 側は送信が主目的だが、自身でループバック確認するため受信も開く
    if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
        udp_.begin(cfg_.udpPort);
    }
    return true;
#else
    // node_01 は ESP32-S3 を前提とする。他アーキでは SoftAp 不可。
    return false;
#endif
}

bool OrcNetModule::connectSta() {
#if defined(ARDUINO_ARCH_ESP32)
    WiFi.mode(WIFI_STA);
    WiFi.begin(cfg_.ssid, cfg_.pass);
#else
    WiFi.begin(cfg_.ssid, cfg_.pass);
#endif
    uint32_t startMs = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startMs < 8000) {
        delay(100);
    }
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }
    // マルチキャスト join。失敗時はユニキャスト/ブロードキャスト受信にフォールバック
    if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
        udp_.begin(cfg_.udpPort);
    }
    return true;
}

bool OrcNetModule::isLinkUp() const {
    if (cfg_.mode == WifiMode::SoftAp) {
        return started_;  // SoftAp は起動できれば常時 up 扱い
    }
    return WiFi.status() == WL_CONNECTED;
}

void OrcNetModule::updateInput(SystemData& data) {
    data.orcNet.hasNewCtrl = false;
    data.orcNet.hasNewBeat = false;

    // 前サイクルの pollReceive で退避された 2 つ目のビートを昇格させる。
    // この時点で lastBeat/hasNewBeat はクリア済みなので安全に上書きできる。
    if (data.orcNet.hasDeferredBeat) {
        data.orcNet.lastBeat    = data.orcNet.deferredBeat;
        data.orcNet.hasNewBeat  = true;
        data.orcNet.hasDeferredBeat = false;
    }

    bool linkUp = isLinkUp();
    data.orcNet.wifiConnected = linkUp;

    // Sta 側のみ自動再接続を試みる
    if (cfg_.mode == WifiMode::Sta && !linkUp && started_) {
        uint32_t now = millis();
        if (now - lastReconnectMs_ >= cfg_.reconnectIntervalMs) {
            lastReconnectMs_ = now;
            WiFi.disconnect();
            WiFi.begin(cfg_.ssid, cfg_.pass);
        }
    }

    // Sta 側: WiFi が down→up に復帰した瞬間に UDP マルチキャスト購読を貼り直す。
    // 再接続でリンクが戻っても購読は無効化されたままになり得るため、リンク復活後も
    // BEAT/CTRL を受信できなくなる。遷移を検出して udp を一度閉じ beginMulticast し直す。
    // SoftAp 側は isLinkUp() が started_ 依存で常時 true のままなので、この遷移は
    // 起きず無影響 (購読の貼り直しは走らない)。
    if (cfg_.mode == WifiMode::Sta && linkUp && !wasLinkUp_ && started_) {
        udp_.stop();
        // 失敗時のフォールバック begin(port) はマルチキャスト宛を受けられないため
        // 実質気休めだが、既存 connectSta() と挙動を揃えておく。
        if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
            udp_.begin(cfg_.udpPort);
        }
    }
    wasLinkUp_ = linkUp;

    if (!started_) return;
    pollReceive(data.orcNet);
}

void OrcNetModule::updateOutput(SystemData& data) {
    if (!started_) return;
    flushSend(data.orcNet);
}

void OrcNetModule::deinit() {
    udp_.stop();
}

void OrcNetModule::pollReceive(OrcNetData& net) {
    // このサイクルで最初に保存した beatNo を追跡し、異なる beatNo が来たら
    // deferredBeat に退避して while を抜ける。同一 beatNo の連送 (redundancy)
    // は lastBeat を上書きし続けてよい (OrcReceiverModule が重複処理する)。
    bool     sawBeat     = false;
    uint16_t firstBeatNo = 0;

    int packetSize;
    while ((packetSize = udp_.parsePacket()) > 0) {
        if (packetSize != (int)orc::PACKET_SIZE) {
            uint8_t scratch[64];
            int rem = packetSize;
            while (rem > 0) {
                int rd = udp_.read(scratch, sizeof(scratch));
                if (rd <= 0) break;
                rem -= rd;
            }
            continue;
        }
        uint8_t buf[orc::PACKET_SIZE];
        int n = udp_.read(buf, orc::PACKET_SIZE);
        if (n != (int)orc::PACKET_SIZE) continue;
        orc::PacketHeader hdr;
        if (!orc::parseHeader(buf, orc::PACKET_SIZE, hdr)) continue;

        if (hdr.type == orc::PKT_CTRL) {
            memcpy(&net.lastCtrl, buf, sizeof(net.lastCtrl));
            net.hasNewCtrl = true;
        } else if (hdr.type == orc::PKT_BEAT) {
            orc::BeatPacket incoming;
            memcpy(&incoming, buf, sizeof(incoming));
            const uint16_t bn = incoming.payload.beatNo;

            if (!sawBeat) {
                // このサイクル最初のビート → lastBeat に保存
                net.lastBeat   = incoming;
                net.hasNewBeat = true;
                firstBeatNo    = bn;
                sawBeat        = true;
            } else if (bn == firstBeatNo) {
                // 同一 beatNo の連送 (redundancy) → 最新で上書き
                net.lastBeat = incoming;
            } else {
                // 異なる beatNo → deferredBeat に退避して次サイクルで昇格
                net.deferredBeat    = incoming;
                net.hasDeferredBeat = true;
                break;  // 残りは次の pollReceive で読む
            }
        }
    }
}

void OrcNetModule::flushSend(OrcNetData& net) {
    // BEAT を先に送る。playAtMasterMs のマージンが薄いため、CTRL より優先する。
    if (net.hasPendingBeat) {
        uint8_t reps = net.pendingBeatRedundancy ? net.pendingBeatRedundancy : 1;
        for (uint8_t i = 0; i < reps; ++i) {
            udp_.beginPacket(cfg_.multicastIp, cfg_.udpPort);
            udp_.write(reinterpret_cast<const uint8_t*>(&net.pendingBeat),
                       sizeof(net.pendingBeat));
            udp_.endPacket();
            // 連送はタイトループだと同じ radio 状態で全滅しやすいので、
            // 各回の間に短い delay を挟んで radio 状態が変化する余地を作る。
            // beatGapMs=0 なら旧来のタイトループ連送。
            if (cfg_.beatGapMs > 0 && (i + 1) < reps) {
                delay(cfg_.beatGapMs);
            }
        }
        net.hasPendingBeat = false;
    }
    if (net.hasPendingCtrl) {
        udp_.beginPacket(cfg_.multicastIp, cfg_.udpPort);
        udp_.write(reinterpret_cast<const uint8_t*>(&net.pendingCtrl),
                   sizeof(net.pendingCtrl));
        udp_.endPacket();
        net.hasPendingCtrl = false;
    }
}
