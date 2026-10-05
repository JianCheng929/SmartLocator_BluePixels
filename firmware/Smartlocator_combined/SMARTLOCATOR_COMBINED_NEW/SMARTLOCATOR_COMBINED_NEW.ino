/*
 * SmartLocator BluPixels — Combined Firmware v1.3
 * CT125 FYP — Android Only
 *
 * FIXES IN v1.3:
 *  - BLE reconnect fix: scan stopped before re-advertising to prevent
 *    GATT status 147 conflict between scan and advertise on ESP32
 *  - Reconnect delay added for BLE stack stability
 *
 * COMMAND REFERENCE:
 *   POWER:ON / POWER:OFF
 *   RESET
 *   ITEM:name         e.g. ITEM:MyBag
 *   FLOOR:0 to FLOOR:4   (Ground=0)
 *   CONFIRM
 *   BUZZER:ON / BUZZER:OFF
 *   VOL:0-100         (VOL:-1 = auto)
 *   BEEP:1-3          (BEEP:-1 = auto)
 *   PHONE:DeviceName
 *   TIME:HH:MM:SS     ← Flutter sends this on every connect
 *   DATE:YYYY-MM-DD   ← Flutter sends this on every connect
 *
 * BUZZER ZONES (auto mode):
 *   CLOSED BY  (RSSI >= -55) → 1 beep, vol 25
 *   NEARBY     (RSSI >= -70) → 1 beep, vol 25
 *   FAR        (RSSI >= -80) → 2 beeps, vol 50
 *   TOO FAR    (RSSI >= -95) → 3 beeps, vol 75
 *   SIGNAL LOST(RSSI < -95)  → 3 beeps, vol 100
 *
 * WIRING:
 *   BME280    SDA=GPIO21, SCL=GPIO22, Addr=0x76
 *   Buzzer    GPIO25 (passive PWM)
 *   Green LED GPIO17
 *   Red LED   GPIO16
 *   Switch    GPIO26 → GND
 */

#include <Wire.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEScan.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <BLEAdvertisedDevice.h>
#include <Preferences.h>

#define FULL_LIFE_SEC   14400UL // 4 hours — 3.28hr safety buffer
#define SAVE_INTERVAL_MS 10000UL

Preferences prefs;
unsigned long totalUsageSeconds = 0;
unsigned long lastSaveTime      = 0;

// ── USER SETTINGS ──────────────────────────────────────────
#define OWNER_PHONE_NAME  "YOUR_PHONE_BLE_NAME"
#define BATT_LOW_THRESH   20

// ── PINS ───────────────────────────────────────────────────
#define BUZZER_PIN    25
#define GREEN_LED_PIN 17
#define RED_LED_PIN   16

// ── BLE UUIDs ──────────────────────────────────────────────
#define SERVICE_UUID  "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID       "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_UUID    "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// ── BUZZER ─────────────────────────────────────────────────
#define BUZZER_FREQ  2000
#define BUZZER_RES   8

// ── BME280 ─────────────────────────────────────────────────
Adafruit_BME280 bme;
#define BME_ADDR 0x76

// ── FLOOR DETECTION ────────────────────────────────────────
const int   FLOOR_COUNT             = 5;
const float FLOOR_MIN               = 0.20f;
const float FLOOR_MAX               = 0.50f;
const int   STABLE_SAMPLES_REQUIRED = 80;
const float MAX_STD_DEV             = 0.03f;
String floorNames[5] = {"Ground","Floor 1","Floor 2","Floor 3","Floor 4"};

// ── PRESSURE FILTER BUFFERS ────────────────────────────────
const int   MEDIAN_SIZE    = 7;
const int   AVG_SIZE       = 15;
const int   ROLLING_WINDOW = 60;
const float EMA_ALPHA      = 0.25f;
float medianBuffer[7], avgBuffer[15], recentPressures[60];
int   medianIndex = 0, avgIndex = 0, recentIndex = 0;
bool  buffersFull = false, recentFull = false;
float emaPressure = 0;

// ── RSSI ───────────────────────────────────────────────────
#define SCAN_DURATION_SEC  0
#define LOST_TIMEOUT_MS    5000
int  rssiSmooth[5];
int  rssiSmIdx = 0;
bool rssiFull  = false;

// ── STATE ──────────────────────────────────────────────────
bool systemOn = true;
bool bleConnected = false, oldBleConnected = false;
String itemName = "";
int    homeFloor = -1;
float  baselinePressure = 0, currentPressure = 0, pressureDiff = 0;
int    sampleCount = 0;
bool   stabilityReady = false, calibDone = false;
int    calibProgress = 0;
String ownerPhone = OWNER_PHONE_NAME;
int    lastRSSI = -100;
bool   phoneFound = false;
unsigned long lastPhoneSeen = 0;
bool softPowerOff = false;
bool buzzerEnabled = true;
bool pendingBuzzerUpdate = false; // true when new BEEP/VOL received
int  userVolume = -1, userBeep = -1;
int  batteryPercent = 100;
int  currentYear = 2026, currentMonth = 1, currentDay = 1;
int  currentHour = 0, currentMin = 0, currentSec = 0;
unsigned long startMillis = 0;
bool firstScanDone = false;
// ── FIX: BLE reconnect state ───────────────────────────────
bool needsReconnectSetup = false;  // flag to handle reconnect in loop safely
bool calibRestored = false;
bool battLedReady  = false; 

const unsigned long READ_INTERVAL_MS    = 500;
const unsigned long DISPLAY_INTERVAL_MS = 1000;
const unsigned long BATT_INTERVAL_MS    = 2000;
unsigned long lastReadTime = 0, lastDisplayTime = 0;
unsigned long lastBattTime = 0;  // will be set in setup()

enum Mode { MODE_IDLE, MODE_CALIBRATING, MODE_TRACKING };
Mode currentMode = MODE_IDLE;
BLEServer*         pServer           = NULL;
BLECharacteristic* pTxCharacteristic = NULL;
BLEScan*           pBLEScan          = NULL;
String  bleCmd = "";
bool    bleCmdReady = false;

// ── FORWARD DECLARATIONS ───────────────────────────────────
void  processCommand(const String&);
float getStablePressure();
bool  checkStability();
int   detectFloor();
void  sendStatusJson();
void  sendCalibJson();
String getProximityLabel(int);
void  controlBuzzer();
int   readBatteryPercent();
String getCurrentTime();
String getCurrentDate();
int   volToDuty(int);
void  doBeeps(int, int);
void  doRapidBeeps(int);
void  loadUsageTime();
void  saveUsageTime();
void  resetUsageTime();

// ── BLE SEND ───────────────────────────────────────────────
void bleSend(const String& msg) {
  if (!bleConnected || !pTxCharacteristic) return;
  int len = msg.length(), pos = 0;
  while (pos < len) {
    int chunk = min(20, len - pos);
    pTxCharacteristic->setValue(msg.substring(pos, pos + chunk).c_str());
    pTxCharacteristic->notify();
    pos += chunk;
    delay(10);
  }
}
void bleSendLn(const String& msg) { bleSend(msg + "\n"); }

// ── BLE CALLBACKS ──────────────────────────────────────────
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) {
    bleConnected = true;
    Serial.println("[BLE] App connected");
  }
  void onDisconnect(BLEServer*) {
    bleConnected = false;
    // FIX: do NOT call startAdvertising() here directly —
    // scan may be running and will conflict (GATT 147).
    // Set flag so loop() handles it safely after stopping scan.
    needsReconnectSetup = true;
    Serial.println("[BLE] Disconnected — will restart advertising safely");
  }
};

class RxCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* p) {
    String v = p->getValue().c_str();
    v.trim();
    if (v.length() > 0) {
      bleCmd = v;
      bleCmdReady = true;
      Serial.println("[RX] " + v);
    }
  }
};

class ScanCB : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice dev) {
    if (String(dev.getName().c_str()) == ownerPhone) {
      int r = dev.getRSSI();
      rssiSmooth[rssiSmIdx] = r;
      rssiSmIdx = (rssiSmIdx + 1) % 5;
      if (!rssiFull && rssiSmIdx == 0) rssiFull = true;
      int cnt = rssiFull ? 5 : rssiSmIdx;
      long s = 0;
      for (int i = 0; i < cnt; i++) s += rssiSmooth[i];
      lastRSSI = cnt > 0 ? (int)(s / cnt) : r;
      phoneFound = true;
      lastPhoneSeen = millis();
    }
  }
};

// ── SETUP ──────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN,   OUTPUT);
  digitalWrite(GREEN_LED_PIN, HIGH);
  digitalWrite(RED_LED_PIN,   LOW);

  startMillis = millis();

  loadUsageTime();
  loadCalibData(); 
    // ✅ 检查Flutter是否标记需要reset
    prefs.begin("smartloc", false);
    bool needsReset = prefs.getBool("needsReset", false);
    if (needsReset) {
      prefs.putBool("needsReset", false);
      prefs.end();
      resetUsageTime();
      totalUsageSeconds = 0;
      batteryPercent = 100;
      startMillis       = millis(); 
      digitalWrite(RED_LED_PIN, LOW);
      Serial.println("[BATT] Auto-reset on boot — fully recharged!");
    } else {
      prefs.end();
      batteryPercent = readBatteryPercent();
    }
  if (batteryPercent <= 5) {
    resetUsageTime();
    batteryPercent = 100;
    digitalWrite(RED_LED_PIN, LOW);
    Serial.println("[BATT] Fresh boot — assumed charged, reset!");
  } else {
    Serial.printf("[BATT] Loaded: %d%% remaining\n", batteryPercent);
    digitalWrite(RED_LED_PIN, (batteryPercent <= 20) ? HIGH : LOW);
  }

  Serial.println("\n=== SmartLocator BluPixels v1.3 ===");
  Serial.println("--- COMMAND REFERENCE ---");
  Serial.println("ITEM:name  FLOOR:0-4  CONFIRM  RESET");
  Serial.println("POWER:ON   POWER:OFF");
  Serial.println("BUZZER:ON  BUZZER:OFF");
  Serial.println("VOL:0-100  BEEP:1-3");
  Serial.println("PHONE:name TIME:HH:MM:SS  DATE:YYYY-MM-DD");
  Serial.println("NOTE: ALL commands UPPERCASE!");
  Serial.println("-------------------------");

  // ✅ ESP32 一上电就是 ON
  systemOn = true;

  ledcAttach(BUZZER_PIN, BUZZER_FREQ, BUZZER_RES);
  ledcWriteTone(BUZZER_PIN, 0);

  analogReadResolution(12);

  // ── BLE ─────────────────────────────────────────────────
  BLEDevice::init("SmartLocator");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCB());
  BLEService* pSvc = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pSvc->createCharacteristic(
    TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());
  BLECharacteristic* pRx = pSvc->createCharacteristic(
    RX_UUID,
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR);
  pRx->setCallbacks(new RxCB());
  pSvc->start();
  BLEAdvertising* pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  pAdv->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new ScanCB(), true);
  pBLEScan->setActiveScan(false);
  pBLEScan->setInterval(1000);
  pBLEScan->setWindow(512);
  Serial.println("[BLE] Advertising 'SmartLocator'");
  Serial.println("[BLE] Scanning for phone: " + ownerPhone);

  // ── BME280 ──────────────────────────────────────────────
  Wire.begin();
  Wire.setClock(100000);  
  delay(500);
  if (!bme.begin(BME_ADDR)) {
    Serial.println("[ERR] BME280 not found!");
    for (int i = 0; i < 5; i++) {
      digitalWrite(RED_LED_PIN, HIGH); delay(200);
      digitalWrite(RED_LED_PIN, LOW);  delay(200);
    }
  } else {
    bme.setSampling(
      Adafruit_BME280::MODE_NORMAL,
      Adafruit_BME280::SAMPLING_X16,
      Adafruit_BME280::SAMPLING_X16,
      Adafruit_BME280::SAMPLING_X1,
      Adafruit_BME280::FILTER_X16,
      Adafruit_BME280::STANDBY_MS_500);
    float first = 0;
    delay(500);  
    for (int t = 0; t < 30 && (first < 950 || first > 1050); t++) {
      first = bme.readPressure() / 100.0f;
      Serial.printf("[BME] init read %d: %.3f\n", t, first);
      delay(200); 
    }
    if (first >= 950 && first <= 1050) {
      for (int i = 0; i < 7;  i++) medianBuffer[i]    = first;
      for (int i = 0; i < 15; i++) avgBuffer[i]       = first;
      for (int i = 0; i < 60; i++) recentPressures[i] = first;
      emaPressure     = first;
      buffersFull     = true;
      currentPressure = first;
      Serial.printf("[BME] Ready: %.2f hPa\n", first);
    }
  }
  lastBattTime = millis() + 10000UL;
  Serial.printf("[BATT] %d%%\n", batteryPercent);
  Serial.println("[OK] Waiting for BLE connection...");
  if (systemOn) doBeeps(2, 40);
}

// ── LOOP ───────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  if (!battLedReady && millis() > 3000UL) {
    battLedReady = true;
  }

  if (needsReconnectSetup) {
    needsReconnectSetup = false;
    pBLEScan->stop();
    delay(200);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Re-advertising after safe scan stop");
  }

  // Process BLE commands
  if (bleCmdReady) {
    bleCmdReady = false;
    processCommand(bleCmd);
  }

  if (!systemOn) { delay(200); return; }

  // Welcome on connect — send TIME/DATE sync reminder
  if (bleConnected && !oldBleConnected) {
    oldBleConnected = true;
    delay(300);
    bleSendLn("{\"type\":\"welcome\",\"msg\":\"SmartLocator v1.3 Ready\","
              "\"phone\":\"" + ownerPhone + "\","
              "\"note\":\"Flutter must send TIME:HH:MM:SS and DATE:YYYY-MM-DD\"}");
  }
  if (!bleConnected && oldBleConnected) {
    oldBleConnected = false;
    ledcWriteTone(BUZZER_PIN, 0);
  }

  // Pressure reading
  if (now - lastReadTime >= READ_INTERVAL_MS) {
    lastReadTime    = now;
    currentPressure = getStablePressure();
    sampleCount++;
    recentPressures[recentIndex] = currentPressure;
    recentIndex = (recentIndex + 1) % ROLLING_WINDOW;
    if (!recentFull && recentIndex == 0) recentFull = true;
    if (baselinePressure > 0)
      pressureDiff = baselinePressure - currentPressure;
    stabilityReady = checkStability();

    if (currentMode == MODE_CALIBRATING) {
      if (stabilityReady) {
        calibProgress    = 100;
        baselinePressure = currentPressure;
        calibDone        = true;
        currentMode      = MODE_TRACKING;
        // Reset rolling buffer so floor detection starts fresh
        // from calibration point — not from boot values
        for (int i = 0; i < ROLLING_WINDOW; i++)
          recentPressures[i] = currentPressure;
        recentIndex = 0;
        recentFull  = true;
        bleSendLn("{\"type\":\"ack\",\"cmd\":\"AUTO_CONFIRM\","
                  "\"baseline\":" + String(baselinePressure, 3) +
                  ",\"floor\":"   + String(homeFloor) + "}");
        Serial.println("[CALIB] Auto-saved! Baseline: "
                       + String(baselinePressure, 3) + " hPa");
      } else {
        int p1 = map(constrain(sampleCount, 0, STABLE_SAMPLES_REQUIRED),
                     0, STABLE_SAMPLES_REQUIRED, 0, 70);
        calibProgress = min(p1, 99);
      }
    }
  }

  // BLE scan — only scan when connected (no point scanning when advertising)
  if (bleConnected) {
    phoneFound = false;
    pBLEScan->start(1, false);
    pBLEScan->clearResults();  
    if (!firstScanDone) {
      firstScanDone = true;
      // Set safe defaults so buzzer fires even before Flutter sends zone commands
      if (userBeep < 1)   userBeep   = 1;
      if (userVolume < 0) userVolume = 25;
    }
    if (!phoneFound && (millis() - lastPhoneSeen > LOST_TIMEOUT_MS))
      lastRSSI = -100;
  }

  // Buzzer fires after scan, silence after beeps complete
  // Buzzer fires after scan, silence after beeps complete
  if (bleConnected && currentMode == MODE_TRACKING
      && buzzerEnabled && calibDone && firstScanDone) {
    if (userBeep >= 1 && userVolume >= 0) {
      // If a new BEEP/VOL command just arrived, skip this cycle
      // to let the new values settle before firing
      if (pendingBuzzerUpdate) {
        pendingBuzzerUpdate = false; // consume flag, fire next cycle
      } else {
        int b = userBeep;
        int v = userVolume;
        doBeeps(b, v);
      }
    }
  }

  // Silence buzzer pin after beep cycle completes
  ledcWriteTone(BUZZER_PIN, 0);
  ledcWrite(BUZZER_PIN, 0);

  // Battery update
  if (now - lastBattTime >= BATT_INTERVAL_MS) {
  lastBattTime   = now;
  batteryPercent = readBatteryPercent();
    if (battLedReady) {
      digitalWrite(RED_LED_PIN, (batteryPercent <= 20) ? HIGH : LOW);
    }
    Serial.printf("[BATT] %d%%\n", batteryPercent);
  }

  // Save usage time
  if (now - lastSaveTime >= SAVE_INTERVAL_MS) {
    lastSaveTime = now;
    saveUsageTime();
    saveCalibData();
  }

  // Send JSON every second
  if (bleConnected && (now - lastDisplayTime >= DISPLAY_INTERVAL_MS)) {
    lastDisplayTime = now;
    (currentMode == MODE_CALIBRATING) ? sendCalibJson() : sendStatusJson();
  }
}

// ── COMMAND PROCESSOR ──────────────────────────────────────
void processCommand(const String& cmd) {
  if (cmd == "POWER:OFF") {
  systemOn = false;
  softPowerOff = true;
  digitalWrite(GREEN_LED_PIN, LOW);
  ledcWriteTone(BUZZER_PIN, 0);

  // ── FIX: 先更新RAM里的totalUsageSeconds再存 ──
  unsigned long sessionSec = (millis() - startMillis) / 1000;
  totalUsageSeconds += sessionSec;  // ← 关键！更新RAM
  prefs.begin("smartloc", false);
  prefs.putULong("usage", totalUsageSeconds);
  prefs.end();
  startMillis = millis();  // 重置session起点
  // ─────────────────────────────────────────────
  
  bleSendLn("{\"type\":\"ack\",\"cmd\":\"POWER:OFF\"}");
  return;
}
  if (cmd == "POWER:ON") {
    systemOn = true;
    softPowerOff = false;
    digitalWrite(GREEN_LED_PIN, HIGH);

    // ── ADD: 重新开始计算 ──
    startMillis = millis();    // 重置session起点
    // ──────────────────────

    bleSendLn("{\"type\":\"ack\",\"cmd\":\"POWER:ON\"}");
    return;
  }

  if (cmd == "BATT:RESET") {
    resetUsageTime();
    batteryPercent = 100;
    startMillis = millis();
    digitalWrite(RED_LED_PIN, LOW);
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"BATT:RESET\"}");
    return;
  }
  
  if (cmd == "MARK:RESET") {
      prefs.begin("smartloc", false);
      prefs.putBool("needsReset", true);
      prefs.end();
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"MARK:RESET\"}");
      Serial.println("[BATT] needsReset flag saved to NVS!");
      return;
  }

  if (cmd == "RESET") {
    resetUsageTime();
    clearCalibData();
    batteryPercent = 100;             // ← 加这行！RAM立刻更新
    startMillis = millis();           // ← 加这行！重置计时起点
    digitalWrite(RED_LED_PIN, LOW);   // ← 加这行！红灯熄灭
    itemName = ""; homeFloor = -1; baselinePressure = 0;
    pressureDiff = 0; sampleCount = 0; recentIndex = 0;
    recentFull = false; stabilityReady = false;
    calibDone = false; calibProgress = 0;
    firstScanDone = false;
    currentMode = MODE_IDLE;
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"RESET\"}");
    return;
  }
  if (cmd.startsWith("ITEM:")) {
    itemName = cmd.substring(5); itemName.trim();
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"ITEM\","
              "\"value\":\"" + itemName + "\"}");
    return;
  }
  if (cmd.startsWith("FLOOR:")) {
    int f = cmd.substring(6).toInt();
    if (f >= 0 && f < FLOOR_COUNT) {
      homeFloor = f; sampleCount = 0; recentIndex = 0;
      recentFull = false; calibDone = false;
      calibProgress = 0; baselinePressure = 0;
      clearCalibData();
      currentMode = MODE_CALIBRATING;
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"FLOOR\","
                "\"floor\":" + String(f) +
                ",\"floorName\":\"" + floorNames[f] + "\","
                "\"info\":\"Calibrating... keep device still 60-90s\"}");
    } else {
      bleSendLn("{\"type\":\"err\",\"msg\":\"Floor must be 0-4\"}");
    }
    return;
  }
  if (cmd == "CONFIRM") {
    if (currentMode == MODE_CALIBRATING && stabilityReady) {
      baselinePressure = currentPressure;
      calibDone = true; calibProgress = 100;
      currentMode = MODE_TRACKING;
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"CONFIRM\","
                "\"baseline\":" + String(baselinePressure, 3) +
                ",\"floor\":" + String(homeFloor) + "}");
    } else if (currentMode != MODE_CALIBRATING) {
      bleSendLn("{\"type\":\"err\",\"msg\":\"Not in calibration mode\"}");
    } else {
      bleSendLn("{\"type\":\"err\","
                "\"msg\":\"Not stable yet — keep device still\"}");
    }
    return;
  }
  if (cmd == "BUZZER:ON") {
    buzzerEnabled = true;
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"BUZZER:ON\"}");
    return;
  }
  if (cmd == "BUZZER:OFF") {
    buzzerEnabled = false;
    ledcWriteTone(BUZZER_PIN, 0);
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"BUZZER:OFF\"}");
    return;
  }
  if (cmd.startsWith("VOL:")) {
    int v = cmd.substring(4).toInt();
    userVolume = (v == -1) ? -1 : constrain(v, 0, 100);
    pendingBuzzerUpdate = true;
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"VOL\","
              "\"value\":" + String(userVolume) + "}");
    return;
  }
  if (cmd.startsWith("BEEP:")) {
    int b = cmd.substring(5).toInt();
    userBeep = (b == -1) ? -1 : constrain(b, 1, 3);
    pendingBuzzerUpdate = true;
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"BEEP\","
              "\"value\":" + String(userBeep) + "}");
    return;
  }
  if (cmd.startsWith("PHONE:")) {
    ownerPhone = cmd.substring(6); ownerPhone.trim();
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"PHONE\","
              "\"name\":\"" + ownerPhone + "\"}");
    return;
  }
  if (cmd.startsWith("TIME:")) {
    String t = cmd.substring(5);
    if (t.length() >= 8) {
      currentHour = t.substring(0,2).toInt();
      currentMin  = t.substring(3,5).toInt();
      currentSec  = t.substring(6,8).toInt();
      startMillis = millis();
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"TIME\","
                "\"synced\":\"" + t + "\"}");
    }
    return;
  }
  if (cmd.startsWith("DATE:")) {
    String d = cmd.substring(5);
    if (d.length() >= 10) {
      currentYear  = d.substring(0,4).toInt();
      currentMonth = d.substring(5,7).toInt();
      currentDay   = d.substring(8,10).toInt();
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"DATE\","
                "\"synced\":\"" + d + "\"}");
    }
    return;
  }

  // Hardware test — send TEST:BUZZ from nRF Connect or Flutter
  if (cmd == "TEST:BUZZ") {
    for (int i = 0; i < 3; i++) {
      ledcWriteTone(BUZZER_PIN, BUZZER_FREQ);
      ledcWrite(BUZZER_PIN, 255);   // max duty — confirms hardware works
      delay(400);
      ledcWriteTone(BUZZER_PIN, 0);
      ledcWrite(BUZZER_PIN, 0);
      delay(200);
    }
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"TEST:BUZZ\",\"note\":\"3 beeps at max vol\"}");
    return;
  }

  bleSendLn("{\"type\":\"err\",\"msg\":\"Unknown: " + cmd +
            "\",\"hint\":\"Commands UPPERCASE e.g. ITEM:name FLOOR:0\"}");
}

// ── JSON OUTPUT ────────────────────────────────────────────
void sendStatusJson() {
  int f = calibDone ? detectFloor() : max(0, homeFloor);
  if (f < 0 || f >= FLOOR_COUNT) f = 0;
  String j = "{\"type\":\"status\"";
  j += ",\"item\":\""      + itemName                    + "\"";
  j += ",\"floor\":"       + String(f);
  j += ",\"floorName\":\"" + floorNames[f]               + "\"";
  j += ",\"proximity\":\"" + getProximityLabel(lastRSSI)  + "\"";
  j += ",\"rssi\":"        + String(lastRSSI);
  j += ",\"battery\":"     + String(batteryPercent);
  j += ",\"buzzerOn\":"    + String(buzzerEnabled ? "true" : "false");
  j += ",\"volume\":"      + String(userVolume);
  j += ",\"beep\":"        + String(userBeep);
  j += ",\"calDone\":"     + String(calibDone ? "true" : "false");
  j += ",\"time\":\""      + getCurrentTime()            + "\"";
  j += ",\"date\":\""      + getCurrentDate()            + "\"";
  j += ",\"power\":"       + String(systemOn ? "true" : "false");
  j += "}\n";
  bleSend(j);
  Serial.print(j);
}

void sendCalibJson() {
  int cnt = recentFull ? ROLLING_WINDOW : (recentIndex ? recentIndex : 1);
  float sum = 0, mn = recentPressures[0], mx = recentPressures[0];
  for (int i = 0; i < cnt; i++) {
    sum += recentPressures[i];
    if (recentPressures[i] < mn) mn = recentPressures[i];
    if (recentPressures[i] > mx) mx = recentPressures[i];
  }
  float avg = sum / cnt, sq = 0;
  for (int i = 0; i < cnt; i++)
    sq += pow(recentPressures[i] - avg, 2);
  float sd = sqrt(sq / cnt);
  String j = "{\"type\":\"calib\""
    ",\"progress\":"  + String(calibProgress) +
    ",\"stable\":"    + String(stabilityReady ? "true" : "false") +
    ",\"pressure\":"  + String(currentPressure, 3) +
    ",\"stdDev\":"    + String(sd, 4) +
    ",\"samples\":"   + String(sampleCount) +
    ",\"hint\":\"Keep still on " + floorNames[max(0,homeFloor)] + "\"}\n";
  bleSend(j);
  Serial.print(j);
}

// ── PRESSURE FILTER ────────────────────────────────────────
float getStablePressure() {
  float raw = bme.readPressure() / 100.0f;
  if (isnan(raw) || raw < 950 || raw > 1050)
    return emaPressure > 0 ? emaPressure : 1013.25f;
  if (emaPressure > 0 && fabs(raw - emaPressure) > 0.10f) {
    for (int i = 0; i < MEDIAN_SIZE; i++) medianBuffer[i] = raw;
    for (int i = 0; i < AVG_SIZE;    i++) avgBuffer[i]    = raw;
    emaPressure = raw; medianIndex = avgIndex = 0;
    buffersFull = true; return emaPressure;
  }
  medianBuffer[medianIndex] = raw;
  medianIndex = (medianIndex + 1) % MEDIAN_SIZE;
  float s[7]; memcpy(s, medianBuffer, sizeof(medianBuffer));
  for (int i = 0; i < 6; i++)
    for (int j = 0; j < 6 - i; j++)
      if (s[j] > s[j+1]) { float t=s[j]; s[j]=s[j+1]; s[j+1]=t; }
  float med = s[3];
  avgBuffer[avgIndex] = med;
  avgIndex = (avgIndex + 1) % AVG_SIZE;
  if (!buffersFull && avgIndex == 0) buffersFull = true;
  float sm = 0; int c = buffersFull ? AVG_SIZE : (avgIndex ? avgIndex : 1);
  for (int i = 0; i < c; i++) sm += avgBuffer[i];
  emaPressure = EMA_ALPHA*(sm/c) + (1.0f-EMA_ALPHA)*emaPressure;
  return emaPressure;
}

// ── STABILITY CHECK ────────────────────────────────────────
bool checkStability() {
  int cnt = recentFull ? ROLLING_WINDOW : recentIndex;
  if (cnt == 0) return false;
  float sum = 0, mn = recentPressures[0], mx = recentPressures[0];
  for (int i = 0; i < cnt; i++) {
    sum += recentPressures[i];
    if (recentPressures[i] < mn) mn = recentPressures[i];
    if (recentPressures[i] > mx) mx = recentPressures[i];
  }
  float avg = sum/cnt, sq = 0;
  for (int i = 0; i < cnt; i++) sq += pow(recentPressures[i]-avg, 2);
  return (sampleCount >= STABLE_SAMPLES_REQUIRED
       && (mx-mn) < 0.1f
       && sqrt(sq/cnt) < MAX_STD_DEV);
}

// ── FLOOR DETECT ───────────────────────────────────────────
int detectFloor() {
  // Use currentPressure (EMA) directly — same as working Code 1
  float d  = baselinePressure - currentPressure;
  float ad = fabs(d);

  Serial.printf("[FLOOR] baseline=%.3f cur=%.3f diff=%.3f\n",
                baselinePressure, currentPressure, d);

  int off = ad < FLOOR_MIN          ? 0
          : ad <= FLOOR_MAX         ? 1
          : ad <= FLOOR_MAX * 2.0f  ? 2
          : ad <= FLOOR_MAX * 3.0f  ? 3 : 4;

  return constrain(
    d > 0 ? homeFloor + off : homeFloor - off,
    0, FLOOR_COUNT - 1
  );
}

// ── PROXIMITY LABEL ────────────────────────────────────────
String getProximityLabel(int rssi) {
  if (rssi >= -55) return "CLOSED BY";
  if (rssi >= -70) return "NEARBY";
  if (rssi >= -80) return "FAR";
  if (rssi >= -95) return "TOO FAR";
  return "SIGNAL LOST";
}

// ── BUZZER ─────────────────────────────────────────────────
int volToDuty(int v) {
  // Passive buzzer needs higher duty — map to 0-255 full range
  return map(constrain(v, 0, 100), 0, 100, 0, 255);
}
void doBeeps(int count, int vol) {
  int duty = volToDuty(vol);
  for (int i = 0; i < count; i++) {
    ledcWriteTone(BUZZER_PIN, BUZZER_FREQ);
    ledcWrite(BUZZER_PIN, duty);
    delay(300);                    // longer on-time for passive buzzer
    ledcWriteTone(BUZZER_PIN, 0);
    ledcWrite(BUZZER_PIN, 0);
    if (i < count - 1) delay(200); // clear gap between beeps
  }
}
void doRapidBeeps(int vol) {
  for (int i = 0; i < 4; i++) {
    ledcWriteTone(BUZZER_PIN, BUZZER_FREQ);
    ledcWrite(BUZZER_PIN, volToDuty(vol));
    delay(100);
    ledcWriteTone(BUZZER_PIN, 0);
    ledcWrite(BUZZER_PIN, 0);
    delay(80);
  }
}
void controlBuzzer() {
  if (userBeep < 1 || userVolume < 0) return;
  // Capture values atomically before doBeeps blocks
  int b = userBeep;
  int v = userVolume;
  doBeeps(b, v);
}

// ── BATTERY ────────────────────────────────────────────────
int readBatteryPercent() {
  unsigned long sessionSec = (millis() - startMillis) / 1000;
  unsigned long totalSec   = totalUsageSeconds + sessionSec;
  if (totalSec >= FULL_LIFE_SEC) return 0;
  int pct = 100 - (int)((totalSec * 100UL) / FULL_LIFE_SEC);
  return constrain(pct, 0, 100);
}
void loadUsageTime() {
  prefs.begin("smartloc", false);
  totalUsageSeconds = prefs.getULong("usage", 0);
  prefs.end();
  Serial.printf("[BATT] Loaded usage: %lu sec\n", totalUsageSeconds);
}
void saveUsageTime() {
  unsigned long sessionSec = (millis() - startMillis) / 1000;
  unsigned long totalSec   = totalUsageSeconds + sessionSec;
  prefs.begin("smartloc", false);
  prefs.putULong("usage", totalSec);
  prefs.end();
}
void resetUsageTime() {
  totalUsageSeconds = 0;
  prefs.begin("smartloc", false);
  prefs.putULong("usage", 0);
  prefs.end();
  Serial.println("[BATT] Timer reset to 0!");
}

void saveCalibData() {
  if (!calibDone || homeFloor < 0) return;
  prefs.begin("smartloc", false);
  prefs.putFloat("baseline", baselinePressure);
  prefs.putInt("homeFloor", homeFloor);
  prefs.putBool("calibDone", true);
  prefs.end();
  Serial.println("[CALIB] Saved to NVS");
}

void loadCalibData() {
  prefs.begin("smartloc", false);
  bool saved = prefs.getBool("calibDone", false);
  if (saved) {
    baselinePressure = prefs.getFloat("baseline", 0);
    homeFloor        = prefs.getInt("homeFloor", -1);
    calibDone        = true;
    currentMode      = MODE_TRACKING;
    calibRestored    = true;
    Serial.printf("[CALIB] Restored: floor=%d baseline=%.3f\n",
                  homeFloor, baselinePressure);
  }
  prefs.end();
}

void clearCalibData() {
  prefs.begin("smartloc", false);
  prefs.putBool("calibDone", false);
  prefs.putFloat("baseline", 0);
  prefs.putInt("homeFloor", -1);
  prefs.end();
}

// ── CLOCK ──────────────────────────────────────────────────
String getCurrentTime() {
  unsigned long el = (millis()-startMillis)/1000;
  int h = (currentHour+(int)(el/3600))%24;
  int m = (currentMin +(int)((el%3600)/60))%60;
  int s = (currentSec +(int)(el%60))%60;
  char buf[9]; sprintf(buf,"%02d:%02d:%02d",h,m,s);
  return String(buf);
}
// Output: "23 Mar 2026" — no day name
String getCurrentDate() {
  const char* mo[]={"Jan","Feb","Mar","Apr","May","Jun",
                    "Jul","Aug","Sep","Oct","Nov","Dec"};
  unsigned long el = (millis()-startMillis)/1000;
  int td = currentDay + (int)(el/86400);
  char buf[20];
  sprintf(buf, "%d %s %d", td, mo[currentMonth-1], currentYear);
  return String(buf);
}