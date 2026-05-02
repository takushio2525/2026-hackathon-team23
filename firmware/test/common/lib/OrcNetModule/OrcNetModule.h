// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/test/node_01     # 指揮者ノード (SoftAp)
//   pio run -d firmware/test/node_02     # 楽器 1 (Sta)
//
// WiFi 接続維持 + UDP マルチキャスト送受信を集約する IModule 実装
// 指揮者ノード(SoftAp)と楽器ノード(Sta)で共有する
#pragma once
#include <Arduino.h>
#include <IPAddress.h>

#include "IModule.h"
#include "OrcProtocol.h"

#if defined(ARDUINO_ARCH_ESP32)
    #include <WiFi.h>
    #include <WiFiUdp.h>
#elif defined(ARDUINO_UNOR4_WIFI) || defined(ARDUINO_ARCH_RENESAS) || defined(ARDUINO_ARCH_RENESAS_UNO)
    #include <WiFiS3.h>
    #include <WiFiUdp.h>
#else
    #include <WiFi.h>
    #include <WiFiUdp.h>
#endif

enum class WifiMode : uint8_t {
    SoftAp,  // 自身が AP を起動する側 (node_01)
    Sta,     // 既存 SoftAP に接続する側 (node_02-05)
};

struct OrcNetConfig {
    WifiMode    mode;
    const char* ssid;
    const char* pass;
    IPAddress   multicastIp;
    uint16_t    udpPort;
    uint8_t     channel;              // SoftAp 時のみ参照
    uint32_t    reconnectIntervalMs;  // 切断検出後の再接続間隔
};

struct OrcNetData {
    // 受信側 (他モジュールが読む)
    bool wifiConnected = false;
    bool hasNewCtrl = false;
    bool hasNewBeat = false;
    orc::CtrlPacket lastCtrl{};
    orc::BeatPacket lastBeat{};

    // 送信側 (送信したいモジュールが書く)
    bool hasPendingCtrl = false;
    orc::CtrlPacket pendingCtrl{};
    bool hasPendingBeat = false;
    orc::BeatPacket pendingBeat{};
    uint8_t pendingBeatRedundancy = 1;
};

class OrcNetModule : public IModule {
public:
    explicit OrcNetModule(const OrcNetConfig& cfg) : cfg_(cfg) {}
    bool init() override;
    void updateInput(SystemData& data) override;
    void updateOutput(SystemData& data) override;
    void deinit() override;

private:
    bool startSoftAp();
    bool connectSta();
    void pollReceive(OrcNetData& net);
    void flushSend(OrcNetData& net);
    bool isLinkUp() const;

    OrcNetConfig cfg_;
    WiFiUDP      udp_;
    bool         started_ = false;
    uint32_t     lastReconnectMs_ = 0;
};
