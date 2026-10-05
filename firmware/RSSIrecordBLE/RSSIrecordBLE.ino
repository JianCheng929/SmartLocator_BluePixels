#include <BLEDevice.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============== NORDIC UART SERVICE UUIDs ==============
#define NUS_SERVICE_UUID "6E400001-B5B3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID      "6E400002-B5B3-F393-E0A9-E50E24DCCA9E"
#define NUS_TX_UUID      "6E400003-B5B3-F393-E0A9-E50E24DCCA9E"

// ============== CONFIGURATION ==============
#define SCAN_DURATION_SEC 1
#define LOST_TIMEOUT_MS   5000

// ============== BUZZER PWM ==============
#define BUZZER_PIN  25
#define BUZZER_RES  8
#define BUZZER_FREQ 2000

// ============== RSSI THRESHOLDS ==============
const int RSSI_ALERT_THRESHOLD = -85;
const int RSSI_SAFE_THRESHOLD  = -78;

// ============== TARGET ==============
String ownerPhoneName = "YOUR_PHONE_BLE_NAME";  // <-- change to your phone's BLE name

// ============== STATE ==============
int  lastRSSI     = -100;
bool ownerFound   = false;
unsigned long lastSeenTime = 0;

// ============== USER OVERRIDES ==============
int userVolume = -1;
int userBeeps  = -1;

// ============== SMOOTHING ==============
const int SMOOTHING_WINDOW = 5;
int rssiBuffer[SMOOTHING_WINDOW];
int bufferIndex = 0;
bool bufferFull = false;

// ============== BLE ==============
BLECharacteristic* pTxCharacteristic;
bool deviceConnected = false;
BLEScan* pBLEScan;

// ======================================================
//  DUAL PRINT — USB Serial + BLE UART both
// ======================================================
void bleUartSend(const char* msg) {
  Serial.print(msg);
  if (deviceConnected) {
    pTxCharacteristic->setValue((uint8_t*)msg, strlen(msg));
    pTxCharacteristic->notify();
    delay(10);
  }
}

void bleUartSendLn(const char* msg) {
  bleUartSend(msg);
  bleUartSend("\n");
}

void bleUartSendInt(int val) {
  char buf[12];
  itoa(val, buf, 10);
  bleUartSend(buf);
}

// ======================================================
//  BLE SERVER CALLBACKS
// ======================================================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println(">> App connected");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println(">> App disconnected — re-advertising");
    BLEDevice::getAdvertising()->start();
  }
};

// ======================================================
//  COMMAND PROCESSOR
// ======================================================
void processCommand(String input);  // forward declaration

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String input = pCharacteristic->getValue().c_str();
    input.trim();
    input.toUpperCase();
    processCommand(input);
  }
};

// ======================================================
//  BUZZER HELPERS
// ======================================================
int volToDuty(int v) {
  return map(constrain(v, 0, 100), 0, 100, 0, 128);
}

void buzzerOn(int vol) {
  ledcWriteTone(BUZZER_PIN, BUZZER_FREQ);
  ledcWrite(BUZZER_PIN, volToDuty(vol));
}

void buzzerOff() {
  ledcWriteTone(BUZZER_PIN, 0);
  ledcWrite(BUZZER_PIN, 0);
}

void doBeeps(int count, int vol) {
  for (int i = 0; i < count; i++) {
    buzzerOn(vol); delay(200);
    buzzerOff();
    if (i < count - 1) delay(150);
  }
}

void doRapidBeeps(int vol) {
  for (int i = 0; i < 4; i++) {
    buzzerOn(vol); delay(100);
    buzzerOff();   delay(80);
  }
}

void getEffectiveParams(int zB, int zV, int &oB, int &oV) {
  oB = (userBeeps  >= 1) ? userBeeps  : zB;
  oV = (userVolume >= 0) ? userVolume : zV;
}

// ======================================================
//  BLE SCAN CALLBACKS
// ======================================================
class ScanCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) {
    String name = advertisedDevice.getName();
    if (name == ownerPhoneName) {
      int rssi = advertisedDevice.getRSSI();
      rssiBuffer[bufferIndex] = rssi;
      bufferIndex = (bufferIndex + 1) % SMOOTHING_WINDOW;
      if (!bufferFull && bufferIndex == 0) bufferFull = true;
      lastRSSI     = getSmoothedRSSI();
      ownerFound   = true;
      lastSeenTime = millis();
    }
  }

  int getSmoothedRSSI() {
    int count = bufferFull ? SMOOTHING_WINDOW : bufferIndex;
    if (count == 0) return lastRSSI;
    long sum = 0;
    for (int i = 0; i < count; i++) sum += rssiBuffer[i];
    return sum / count;
  }
};

// ======================================================
//  SETUP
// ======================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  // Buzzer
  ledcAttach(BUZZER_PIN, BUZZER_FREQ, BUZZER_RES);
  buzzerOff();

  // BLE init
  BLEDevice::init("SmartLocator");

  // ── BLE Server (UART monitor) ──
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(NUS_SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
    NUS_TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(
    NUS_RX_UUID,
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR);
  pRxCharacteristic->setCallbacks(new RxCallbacks());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(NUS_SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  pAdvertising->start();

  // ── BLE Scanner ──
  pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new ScanCallbacks());
  pBLEScan->setActiveScan(false);
  pBLEScan->setInterval(1000);
  pBLEScan->setWindow(512);

  Serial.println("SmartLocator ready");
  Serial.println("Connect via Serial Bluetooth Terminal (BLE LE tab)");
  Serial.print("Scanning for: ");
  Serial.println(ownerPhoneName);
}

// ======================================================
//  LOOP
// ======================================================
void loop() {
  // USB serial commands
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    input.toUpperCase();
    processCommand(input);
  }

  ownerFound = false;
  buzzerOff();
  pBLEScan->start(SCAN_DURATION_SEC, false);

  if (!ownerFound && (millis() - lastSeenTime > LOST_TIMEOUT_MS)) {
    lastRSSI = -100;
  }

  displayStatus();
  controlBuzzerByZone();
  delay(300);
}

// ======================================================
//  DISPLAY STATUS
// ======================================================
void displayStatus() {
  bleUartSendLn("\n======== STATUS ========");

  bleUartSend("Signal: ");
  int bars = mapRssiToBars(lastRSSI);
  for (int i = 0; i < 5; i++) bleUartSend(i < bars ? "#" : ".");
  bleUartSend(" (");
  bleUartSendInt(lastRSSI);
  bleUartSendLn(" dBm)");

  bleUartSend("Status: ");
  if      (lastRSSI >= -55) bleUartSendLn("VERY CLOSE  [1 beep soft]");
  else if (lastRSSI >= -70) bleUartSendLn("NEARBY      [1 beep soft]");
  else if (lastRSSI >= -80) bleUartSendLn("FAR         [2 beeps moderate]");
  else if (lastRSSI >= -95) bleUartSendLn("TOO FAR     [3 beeps loud]");
  else                      bleUartSendLn("OUT OF RANGE [rapid loud]");

  bleUartSend("Volume: ");
  if (userVolume >= 0) {
    bleUartSendInt(userVolume);
    bleUartSendLn("% OVERRIDE");
  } else bleUartSendLn("Zone default");

  bleUartSend("Beeps:  ");
  if (userBeeps >= 1) {
    bleUartSendInt(userBeeps);
    bleUartSendLn(" OVERRIDE");
  } else bleUartSendLn("Zone default");

  bleUartSend("Last:   ");
  if (ownerFound) bleUartSendLn("Just now");
  else {
    bleUartSendInt((millis() - lastSeenTime) / 1000);
    bleUartSendLn("s ago");
  }
  bleUartSendLn("========================");
  bleUartSendLn("Cmds: V50/V-1/B2/B-1/T/C");
}

// ======================================================
//  BUZZER CONTROL BY ZONE
// ======================================================
void controlBuzzerByZone() {
  int b, v;
  if      (lastRSSI >= -55) { getEffectiveParams(1, 30,  b, v); doBeeps(b, v); }
  else if (lastRSSI >= -70) { getEffectiveParams(1, 30,  b, v); doBeeps(b, v); }
  else if (lastRSSI >= -80) { getEffectiveParams(2, 60,  b, v); doBeeps(b, v); }
  else if (lastRSSI >= -95) { getEffectiveParams(3, 100, b, v); doBeeps(b, v); }
  else { doRapidBeeps((userVolume >= 0) ? userVolume : 100); }
}

// ======================================================
//  RSSI BARS
// ======================================================
int mapRssiToBars(int rssi) {
  if (rssi >= -55) return 5;
  if (rssi >= -65) return 4;
  if (rssi >= -75) return 3;
  if (rssi >= -85) return 2;
  if (rssi >= -95) return 1;
  return 0;
}

// ======================================================
//  COMMAND PROCESSOR
// ======================================================
void processCommand(String input) {
  if (input.startsWith("V")) {
    int val = input.substring(1).toInt();
    if (val == -1) {
      userVolume = -1;
      bleUartSendLn(">> Volume: zone default");
    } else {
      userVolume = constrain(val, 0, 100);
      bleUartSend(">> Volume: ");
      bleUartSendInt(userVolume);
      bleUartSendLn("%");
    }

  } else if (input.startsWith("B")) {
    int val = input.substring(1).toInt();
    if (val == -1) {
      userBeeps = -1;
      bleUartSendLn(">> Beeps: zone default");
    } else {
      userBeeps = constrain(val, 1, 3);
      bleUartSend(">> Beeps: ");
      bleUartSendInt(userBeeps);
      bleUartSend("\n");
    }

  } else if (input == "T") {
    bleUartSendLn(">> Testing buzzer...");
    bleUartSendLn("   Soft 30%");     doBeeps(1, 30);    delay(400);
    bleUartSendLn("   Moderate 60%"); doBeeps(2, 60);    delay(400);
    bleUartSendLn("   Loud 100%");    doBeeps(3, 100);   delay(400);
    bleUartSendLn("   Rapid");        doRapidBeeps(100);

  } else if (input == "C") {
    bleUartSendLn(">> Enter new phone name:");

  } else if (input.length() > 0) {
    // Treat unknown input as new phone name after C command
    ownerPhoneName = input;
    bleUartSend(">> Scanning for: ");
    bleUartSendLn(ownerPhoneName.c_str());
  }
}