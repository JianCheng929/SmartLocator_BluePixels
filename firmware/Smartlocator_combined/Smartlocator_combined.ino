/*
 * SmartLocator BluPixels — Combined Firmware v1.0
 * CT125 FYP — Android Only
 *
 * WIRING:
 * BME280     SDA=GPIO21, SCL=GPIO22, Addr=0x76
 * Buzzer     GPIO25 (passive PWM)
 * Green LED  GPIO17 — LED+ via 220ohm to GPIO17, LED- to GND
 * Red LED    GPIO16 — LED+ via 220ohm to GPIO16, LED- to GND
 * Switch     GPIO26 — one leg to GPIO26, other to GND
 * Boost 5V   → VIN of ESP32 (unchanged)
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

#define FULL_LIFE_SEC    25200UL  // 7 hours — update after real test
#define SAVE_INTERVAL_MS 60000UL  // save every 1 minute

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
#define SWITCH_PIN    26

// ── BLE UUIDs (must match Flutter app) ────────────────────
#define SERVICE_UUID  "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID       "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_UUID       "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

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
const int   STABLE_SAMPLES_REQUIRED = 50;
const float MAX_STD_DEV             = 0.05f;
String floorNames[5] = {"Ground","Floor 1","Floor 2","Floor 3","Floor 4"};

// ── PRESSURE FILTER BUFFERS ────────────────────────────────
const int   MEDIAN_SIZE    = 7;
const int   AVG_SIZE       = 15;
const int   ROLLING_WINDOW = 60;
const float EMA_ALPHA      = 0.15f;
float medianBuffer[7], avgBuffer[15], recentPressures[60];
int   medianIndex = 0, avgIndex = 0, recentIndex = 0;
bool  buffersFull = false, recentFull = false;
float emaPressure = 0;

// ── RSSI ───────────────────────────────────────────────────
#define SCAN_DURATION_SEC  1
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
bool softPowerOff = false;  // ← add this line
bool buzzerEnabled = true;
int  userVolume = -1, userBeep = -1;
int  batteryPercent = 100;
int  currentYear = 2026, currentMonth = 3, currentDay = 19;
int  currentHour = 0, currentMin = 0, currentSec = 0;
unsigned long startMillis = 0;
const unsigned long READ_INTERVAL_MS    = 500;
const unsigned long DISPLAY_INTERVAL_MS = 1000;
const unsigned long BATT_INTERVAL_MS    = 5000;
unsigned long lastReadTime = 0, lastDisplayTime = 0, lastBattTime = 0;
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
void  loadUsageTime();   // ← ADD
void  saveUsageTime();   // ← ADD
void  resetUsageTime();  // ← ADD

// ── BLE SEND (20-byte chunks) ──────────────────────────────
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
  void onConnect(BLEServer*)    {
    bleConnected = true;
    Serial.println("[BLE] App connected");
  }
  void onDisconnect(BLEServer*) {
    bleConnected = false;
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Disconnected, re-advertising");
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

  // ── GPIO FIRST — before anything else ──────────────────
  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN,   OUTPUT);
  pinMode(SWITCH_PIN,    INPUT_PULLUP);
  digitalWrite(GREEN_LED_PIN, LOW);  // off until switch checked
  digitalWrite(RED_LED_PIN,   LOW);  // off by default

  // ── START MILLIS ────────────────────────────────────────
  startMillis = millis();

  // ── BATTERY TIMER LOAD ──────────────────────────────────
  loadUsageTime();
  batteryPercent = readBatteryPercent();
  if (batteryPercent <= 5) {
    resetUsageTime();
    batteryPercent = 100;
    digitalWrite(RED_LED_PIN, LOW);
    Serial.println("[BATT] Fresh boot — assumed charged, reset!");
  } else {
    Serial.printf("[BATT] Loaded: %d%% remaining\n", batteryPercent);
  }

  Serial.println("\n=== SmartLocator BluPixels v1.0 ===");

  // ── SWITCH CHECK ────────────────────────────────────────
  systemOn = (digitalRead(SWITCH_PIN) == LOW);
  digitalWrite(GREEN_LED_PIN, systemOn ? HIGH : LOW);

  // ── BUZZER ──────────────────────────────────────────────
  ledcAttach(BUZZER_PIN, BUZZER_FREQ, BUZZER_RES);
  ledcWriteTone(BUZZER_PIN, 0);

  // ── ADC ─────────────────────────────────────────────────
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
  Wire.setClock(400000);
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
    for (int t = 0; t < 20 && (first < 950 || first > 1050); t++) {
      first = bme.readPressure() / 100.0f;
      delay(100);
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

  Serial.printf("[BATT] %d%%\n", batteryPercent);
  Serial.println("[OK] Waiting for BLE connection...");
  if (systemOn) doBeeps(2, 40);  // beep only if switch ON
}

// ── LOOP ───────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  bool swOn = (digitalRead(SWITCH_PIN) == LOW);

// Hardware switch OFF always wins
if (!swOn && systemOn) {
  systemOn = false;
  digitalWrite(GREEN_LED_PIN, LOW);
  ledcWriteTone(BUZZER_PIN, 0);
  Serial.println("[SW] Hardware OFF");
}
// Hardware switch ON only turns on if not software-powered-off
if (swOn && !systemOn && !softPowerOff) {
  systemOn = true;
  digitalWrite(GREEN_LED_PIN, HIGH);
  Serial.println("[SW] Hardware ON");
}
// If switch OFF, clear software power flag
if (!swOn) softPowerOff = false;

// ── Process BLE commands EVEN when system off ──────────
// Needed so POWER:ON can wake system via app
if (bleCmdReady) {
  bleCmdReady = false;
  processCommand(bleCmd);
}

if (!systemOn) { delay(200); return; }

  if (bleConnected && !oldBleConnected) {
    oldBleConnected = true;
    delay(300);
    bleSendLn("{\"type\":\"welcome\",\"msg\":\"SmartLocator Ready\","
              "\"phone\":\"" + ownerPhone + "\"}");
  }
  if (!bleConnected && oldBleConnected) {
    oldBleConnected = false;
    ledcWriteTone(BUZZER_PIN, 0);
  }

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
        calibProgress = 100;
        // AUTO-SAVE baseline when stable — no CONFIRM needed
        baselinePressure = currentPressure;
        calibDone        = true;
        currentMode      = MODE_TRACKING;
        bleSendLn("{\"type\":\"ack\",\"cmd\":\"AUTO_CONFIRM\","
                  "\"baseline\":" + String(baselinePressure, 3) +
                  ",\"floor\":"   + String(homeFloor) + "}");
        Serial.println("[CALIB] Auto-saved! Baseline: "
                       + String(baselinePressure, 3) + " hPa");
      } else {
        // Progress: 0-70% based on sample count
        // then 70-99% based on stability (stdDev shrinking)
        int p1 = map(constrain(sampleCount, 0, STABLE_SAMPLES_REQUIRED),
                     0, STABLE_SAMPLES_REQUIRED, 0, 70);
        calibProgress = min(p1, 99); // never shows 100 until truly stable
      }
    }
  }
  
  phoneFound = false;
  ledcWriteTone(BUZZER_PIN, 0);
  pBLEScan->start(SCAN_DURATION_SEC, false);
  if (!phoneFound && (millis() - lastPhoneSeen > LOST_TIMEOUT_MS))
    lastRSSI = -100;

  if (bleConnected && currentMode == MODE_TRACKING && buzzerEnabled && calibDone)
    controlBuzzer();

  // Battery update every 5 seconds
  if (now - lastBattTime >= BATT_INTERVAL_MS) {
    lastBattTime   = now;
    batteryPercent = readBatteryPercent();
    // Red LED ON below 20% → LOW
    // Red LED OFF above 20% → GOOD
    digitalWrite(RED_LED_PIN,
      (batteryPercent <= 20) ? HIGH : LOW);
    Serial.printf("[BATT] %d%%\n", batteryPercent);
  }

  // Save usage time to flash every 1 minute
  if (now - lastSaveTime >= SAVE_INTERVAL_MS) {
    lastSaveTime = now;
    saveUsageTime();
  }

  if (bleConnected && (now - lastDisplayTime >= DISPLAY_INTERVAL_MS)) {
    lastDisplayTime = now;
    (currentMode == MODE_CALIBRATING) ? sendCalibJson() : sendStatusJson();
  }
}

// ── COMMAND PROCESSOR ──────────────────────────────────────
void processCommand(const String& cmd) {
  if (cmd == "POWER:OFF") {
  systemOn = false;
  softPowerOff = true;        // ← add this line
  digitalWrite(GREEN_LED_PIN, LOW);
  ledcWriteTone(BUZZER_PIN, 0);
  bleSendLn("{\"type\":\"ack\",\"cmd\":\"POWER:OFF\"}");
  return;
  }
  if (cmd == "POWER:ON") {
    systemOn = true;
    softPowerOff = false;       // ← add this line
    digitalWrite(GREEN_LED_PIN, HIGH);
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"POWER:ON\"}");
    return;
  }
  if (cmd == "RESET") {
    resetUsageTime(); 
    itemName = ""; homeFloor = -1; baselinePressure = 0;
    pressureDiff = 0; sampleCount = 0; recentIndex = 0;
    recentFull = false; stabilityReady = false;
    calibDone = false; calibProgress = 0;
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
      currentMode = MODE_CALIBRATING;
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"FLOOR\","
                "\"floor\":" + String(f) +
                ",\"floorName\":\"" + floorNames[f] + "\"}");
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
    bleSendLn("{\"type\":\"ack\",\"cmd\":\"VOL\","
              "\"value\":" + String(userVolume) + "}");
    return;
  }
  if (cmd.startsWith("BEEP:")) {
    int b = cmd.substring(5).toInt();
    userBeep = (b == -1) ? -1 : constrain(b, 1, 3);
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
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"TIME\"}");
    }
    return;
  }
  // ── NEW: DATE command ─────────────────────────────────────
  if (cmd.startsWith("DATE:")) {
    String d = cmd.substring(5);
    if (d.length() >= 10) {
      currentYear  = d.substring(0,4).toInt();
      currentMonth = d.substring(5,7).toInt();
      currentDay   = d.substring(8,10).toInt();
      bleSendLn("{\"type\":\"ack\",\"cmd\":\"DATE\"}");
    }
    return;
  }
  bleSendLn("{\"type\":\"err\",\"msg\":\"Unknown: " + cmd + "\"}");
}

// ── JSON OUTPUT ────────────────────────────────────────────
void sendStatusJson() {
  int f = calibDone ? detectFloor() : max(0, homeFloor);
  if (f < 0 || f >= FLOOR_COUNT) f = 0;
  String j = "{\"type\":\"status\"";
  j += ",\"item\":\""       + itemName              + "\"";
  j += ",\"floor\":"        + String(f);
  j += ",\"floorName\":\""  + floorNames[f]         + "\"";
  j += ",\"proximity\":\""  + getProximityLabel(lastRSSI) + "\"";
  j += ",\"rssi\":"         + String(lastRSSI);
  j += ",\"battery\":"      + String(batteryPercent);
  j += ",\"buzzerOn\":"     + String(buzzerEnabled ? "true" : "false");
  j += ",\"volume\":"       + String(userVolume);
  j += ",\"beep\":"         + String(userBeep);
  j += ",\"calDone\":"      + String(calibDone ? "true" : "false");
  j += ",\"time\":\""       + getCurrentTime()      + "\"";
  j += ",\"date\":\""       + getCurrentDate()      + "\"";
  j += ",\"power\":"        + String(systemOn ? "true" : "false");
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
    ",\"samples\":"   + String(sampleCount) + "}\n";
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

// ── STABILITY ──────────────────────────────────────────────
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
  float d = baselinePressure - currentPressure, ad = fabs(d);
  int off = ad < FLOOR_MIN ? 0
          : ad <= FLOOR_MAX   ? 1
          : ad <= FLOOR_MAX*2 ? 2
          : ad <= FLOOR_MAX*3 ? 3 : 4;
  return constrain(d > 0 ? homeFloor+off : homeFloor-off,
                   0, FLOOR_COUNT-1);
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
  return map(constrain(v, 0, 100), 0, 100, 0, 128);
}
void doBeeps(int count, int vol) {
  for (int i = 0; i < count; i++) {
    ledcWriteTone(BUZZER_PIN, BUZZER_FREQ);
    ledcWrite(BUZZER_PIN, volToDuty(vol));
    delay(200);
    ledcWriteTone(BUZZER_PIN, 0);
    ledcWrite(BUZZER_PIN, 0);
    if (i < count-1) delay(150);
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
  int zB, zV;
  if      (lastRSSI >= -55) { zB=1; zV=30;  }
  else if (lastRSSI >= -70) { zB=1; zV=30;  }
  else if (lastRSSI >= -80) { zB=2; zV=60;  }
  else if (lastRSSI >= -95) { zB=3; zV=100; }
  else {
    // SIGNAL LOST — respect userBeep and userVolume
    int vol = userVolume >= 0 ? userVolume : 100;
    int cnt = userBeep   >= 1 ? userBeep   : 3;
    doBeeps(cnt, vol);
    return;
  }
  doBeeps(userBeep   >= 1 ? userBeep   : zB,
          userVolume >= 0 ? userVolume : zV);
}

// ── BATTERY (Timer + Auto Reset on Power Cycle) ────────
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
  Serial.printf("[BATT] Loaded usage: %lu sec\n",
                totalUsageSeconds);
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

// ── CLOCK ──────────────────────────────────────────────────
String getCurrentTime() {
  unsigned long el = (millis()-startMillis)/1000;
  int h = (currentHour+(int)(el/3600))%24;
  int m = (currentMin +(int)((el%3600)/60))%60;
  int s = (currentSec +(int)(el%60))%60;
  char buf[9]; sprintf(buf,"%02d:%02d:%02d",h,m,s);
  return String(buf);
}
String getCurrentDate() {
  const char* mo[]={"Jan","Feb","Mar","Apr","May","Jun",
                    "Jul","Aug","Sep","Oct","Nov","Dec"};
  const char* dw[]={"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
  unsigned long el = (millis()-startMillis)/1000;
  int td  = currentDay+(int)(el/86400);
  int dow = (4+td-currentDay)%7;
  char buf[32];
  sprintf(buf,"%s, %d %s %d",dw[dow],td,mo[currentMonth-1],currentYear);
  return String(buf);
}