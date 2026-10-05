#include <Wire.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

Adafruit_BME280 bme;

// ============== BLE NORDIC UART SERVICE (NUS) ==============
// These UUIDs are required by Serial Bluetooth Terminal app
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer*         pServer         = NULL;
BLECharacteristic* pTxCharacteristic = NULL;
bool deviceConnected    = false;
bool oldDeviceConnected = false;

// Incoming BLE data buffer
String bleInput = "";
bool   bleInputReady = false;

// ============== CONFIGURATION ==============
const int   FLOOR_COUNT = 5;
const float FLOOR_MIN   = 0.20;
const float FLOOR_MAX   = 0.50;
const int   STABLE_SAMPLES_REQUIRED = 50;
const float MAX_STD_DEV = 0.05;

// ============== TIMING ==============
const int READ_INTERVAL_MS    = 500;
const int DISPLAY_INTERVAL_MS = 1000;

// ============== FILTERING ==============
const int MEDIAN_SIZE = 7;
const int AVG_SIZE    = 15;
float medianBuffer[MEDIAN_SIZE];
float avgBuffer[AVG_SIZE];
int   medianIndex   = 0;
int   avgIndex      = 0;
bool  buffersFull   = false;
float emaPressure   = 0;
const float EMA_ALPHA = 0.15;

// ============== ROLLING STATISTICS ==============
const int ROLLING_WINDOW = 60;
float recentPressures[ROLLING_WINDOW];
int   recentIndex = 0;
bool  recentFull  = false;

// ============== GLOBAL VARIABLES ==============
float currentPressure  = 0;
float baselinePressure = 0;
float pressureDiff     = 0;
int   homeFloor        = -1;
int   sampleCount      = 0;
bool  stabilityReady   = false;
String itemName        = "";

// ============== DATE & TIME ==============
int currentYear  = 2026;
int currentMonth = 3;
int currentDay   = 19;
int currentHour  = 0;
int currentMin   = 0;
int currentSec   = 0;
unsigned long startMillis = 0;

// ============== TIMING CONTROL ==============
unsigned long lastReadTime    = 0;
unsigned long lastDisplayTime = 0;

// ============== APP MODE ==============
enum Mode {
  MODE_ITEM,
  MODE_FLOOR,
  MODE_BASELINE,
  MODE_TRACKING
};
Mode currentMode = MODE_ITEM;

// ============== FLOOR NAMES ==============
String floorNames[FLOOR_COUNT] = {
  "Ground", "Floor 1", "Floor 2", "Floor 3", "Floor 4"
};

// ============== BLE SEND ==============
// Replaces Serial.print — sends text to BLE app
void bleSend(String msg) {
  if (deviceConnected) {
    // BLE max packet = 20 bytes, split if needed
    int len = msg.length();
    int pos = 0;
    while (pos < len) {
      int chunkSize = min(20, len - pos);
      String chunk  = msg.substring(pos, pos + chunkSize);
      pTxCharacteristic->setValue(chunk.c_str());
      pTxCharacteristic->notify();
      pos += chunkSize;
      delay(10); // small delay between chunks
    }
  }
}

void bleSendln(String msg) {
  bleSend(msg + "\n");
}

// ============== BLE SERVER CALLBACKS ==============
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE Client connected!");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("BLE Client disconnected!");
  }
};

// ============== BLE RX CALLBACKS ==============
// Called when app sends data to ESP32
class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String rxValue = pCharacteristic->getValue().c_str();
    if (rxValue.length() > 0) {
      rxValue.trim();
      bleInput      = rxValue;
      bleInputReady = true;
      Serial.println("BLE received: " + rxValue);
    }
  }
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  startMillis = millis();

  Serial.println("SmartLocator BLE Starting...");

  // ============== BLE INIT ==============
  BLEDevice::init("SmartLocator");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  // TX Characteristic (ESP32 → App)
  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  // RX Characteristic (App → ESP32)
  BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE
  );
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  // Start advertising so app can find ESP32
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started. Waiting for connection...");
  Serial.println("Device name: SmartLocator");

  // ============== BME280 INIT ==============
  Wire.begin();
  Wire.setClock(400000);

  if (!bme.begin(0x76)) {
    Serial.println("ERROR: BME280 not found!");
    while (1) delay(10);
  }

  bme.setSampling(
    Adafruit_BME280::MODE_NORMAL,
    Adafruit_BME280::SAMPLING_X16,
    Adafruit_BME280::SAMPLING_X16,
    Adafruit_BME280::SAMPLING_X1,
    Adafruit_BME280::FILTER_X16,
    Adafruit_BME280::STANDBY_MS_500
  );

  // PRE-FILL BUFFERS
  float firstReading = 0;
  while (firstReading < 950 || firstReading > 1050) {
    firstReading = bme.readPressure() / 100.0F;
    delay(100);
  }
  for (int i = 0; i < MEDIAN_SIZE; i++)    medianBuffer[i]    = firstReading;
  for (int i = 0; i < AVG_SIZE; i++)       avgBuffer[i]       = firstReading;
  for (int i = 0; i < ROLLING_WINDOW; i++) recentPressures[i] = firstReading;
  emaPressure     = firstReading;
  buffersFull     = true;
  currentPressure = firstReading;

  Serial.println("Sensor ready! Pressure: " + String(firstReading, 2) + " hPa");
}

void loop() {
  // Handle BLE connection state changes
  handleBLEConnection();

  // Handle incoming BLE input
  if (bleInputReady) {
    bleInputReady = false;
    handleInput(bleInput);
  }

  unsigned long now = millis();

  // Always read sensor
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
  }

  // Display based on mode
  if (now - lastDisplayTime >= DISPLAY_INTERVAL_MS) {
    lastDisplayTime = now;

    if (!deviceConnected) return; // dont display if not connected

    if (currentMode == MODE_BASELINE)
      displayBaseline();
    else if (currentMode == MODE_TRACKING)
      displayTracking();
  }
}

// ============== BLE CONNECTION HANDLER ==============
void handleBLEConnection() {
  // Just reconnected
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
    delay(500);
    // Show welcome and prompt when app connects
    bleSendln("");
    bleSendln("  ========================================");
    bleSendln("         Welcome to SmartLocator!        ");
    bleSendln("      IoT Personal Item Floor Tracker    ");
    bleSendln("  ========================================");
    bleSendln("");
    bleSendln("  Sensor ready! Pressure: " + String(currentPressure, 2) + " hPa");
    bleSendln("");
    printItemPrompt();
  }

  // Just disconnected — restart advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("BLE advertising restarted...");
    oldDeviceConnected = deviceConnected;
  }
}

// ============== PROMPTS ==============
void printItemPrompt() {
  bleSendln("  ========================================");
  bleSendln("   Step 1: Enter your item name          ");
  bleSendln("  ========================================");
  bleSendln("  Example: Bag, Laptop, Keys, Wallet     ");
  bleSendln("  Type item name and send...             ");
  bleSendln("  ========================================");
  bleSendln("");
}

void printFloorPrompt() {
  bleSendln("");
  bleSendln("  ========================================");
  bleSendln("   Step 2: Which floor are you on NOW?   ");
  bleSendln("  ========================================");
  bleSendln("    0 - Ground Floor");
  bleSendln("    1 - Floor 1");
  bleSendln("    2 - Floor 2");
  bleSendln("    3 - Floor 3");
  bleSendln("    4 - Floor 4");
  bleSendln("  Type number and send...                ");
  bleSendln("  ========================================");
}

// ============== INPUT HANDLER ==============
void handleInput(String input) {
  input.trim();
  if (input.length() == 0) return;

  // Global reset anytime
  if (input == "R" || input == "r") {
    fullReset();
    return;
  }

  // Step 1: Item name
  if (currentMode == MODE_ITEM) {
    itemName = input;
    bleSendln("");
    bleSendln("  Item set to: " + itemName);
    currentMode = MODE_FLOOR;
    printFloorPrompt();
    return;
  }

  // Step 2: Floor selection
  if (currentMode == MODE_FLOOR) {
    int floor = input.toInt();
    if ((input == "0" || floor > 0) &&
         floor >= 0 && floor < FLOOR_COUNT) {
      homeFloor   = floor;
      sampleCount = 0;
      recentIndex = 0;
      recentFull  = false;
      currentMode = MODE_BASELINE;
      bleSendln("");
      bleSendln("  ========================================");
      bleSendln("  Item    : " + itemName);
      bleSendln("  Floor   : " + floorNames[homeFloor]);
      bleSendln("  ----------------------------------------");
      bleSendln("  Keep device VERY STILL!                ");
      bleSendln("  Wait for STABLE then send ENTER        ");
      bleSendln("  ========================================");
      bleSendln("");
    } else {
      bleSendln("  Invalid! Enter 0 to 4.");
      printFloorPrompt();
    }
    return;
  }

  // Step 3: Save baseline
  if (currentMode == MODE_BASELINE) {
    if (stabilityReady) {
      baselinePressure = currentPressure;
      currentMode      = MODE_TRACKING;
      bleSendln("");
      bleSendln("  ========================================");
      bleSendln("  BASELINE SAVED! Live tracking started  ");
      bleSendln("  ========================================");
      bleSendln("  Baseline Floor    : " + floorNames[homeFloor]);
      bleSendln("  Baseline Pressure : " + String(baselinePressure, 3) + " hPa");
      bleSendln("  ========================================");
      bleSendln("  Send R to reset anytime                ");
      bleSendln("  ========================================");
      bleSendln("");
    } else {
      bleSendln("  Not stable yet! Keep still and wait.");
    }
    return;
  }
}

// ============== STABILITY CHECK ==============
bool checkStability() {
  int count = recentFull ? ROLLING_WINDOW : recentIndex;
  if (count == 0) return false;

  float sum    = 0;
  float minVal = recentPressures[0];
  float maxVal = recentPressures[0];

  for (int i = 0; i < count; i++) {
    sum += recentPressures[i];
    if (recentPressures[i] < minVal) minVal = recentPressures[i];
    if (recentPressures[i] > maxVal) maxVal = recentPressures[i];
  }

  float avg   = sum / count;
  float range = maxVal - minVal;

  float sumSq = 0;
  for (int i = 0; i < count; i++)
    sumSq += pow(recentPressures[i] - avg, 2);
  float stdDev = sqrt(sumSq / count);

  return (sampleCount >= STABLE_SAMPLES_REQUIRED &&
          range < 0.1 &&
          stdDev < MAX_STD_DEV);
}

// ============== BASELINE DISPLAY ==============
void displayBaseline() {
  int count = recentFull ? ROLLING_WINDOW : recentIndex;
  if (count == 0) count = 1;

  float sum    = 0;
  float minVal = recentPressures[0];
  float maxVal = recentPressures[0];
  for (int i = 0; i < count; i++) {
    sum += recentPressures[i];
    if (recentPressures[i] < minVal) minVal = recentPressures[i];
    if (recentPressures[i] > maxVal) maxVal = recentPressures[i];
  }
  float avg    = sum / count;
  float range  = maxVal - minVal;
  float sumSq  = 0;
  for (int i = 0; i < count; i++)
    sumSq += pow(recentPressures[i] - avg, 2);
  float stdDev = sqrt(sumSq / count);

  String statusMsg = "";
  if (stabilityReady)
    statusMsg = ">>> STABLE - Send anything to save <<<";
  else if (sampleCount < STABLE_SAMPLES_REQUIRED)
    statusMsg = "Warming up (" + String(STABLE_SAMPLES_REQUIRED - sampleCount) + " more)";
  else if (range >= 0.1)
    statusMsg = "SETTLING - Hold still...";
  else
    statusMsg = "OK - Almost stable...";

  bleSendln("");
  bleSendln("===== CALIBRATING =====");
  bleSendln("Time:    " + String(sampleCount / 2) + "s");
  bleSendln("Current: " + String(currentPressure, 3) + " hPa");
  bleSendln("Avg:     " + String(avg, 3) + " hPa");
  bleSendln("Range:   " + String(range, 3) + " hPa (<0.1)");
  bleSendln("StdDev:  " + String(stdDev, 4) + " hPa");
  bleSendln("Status:  " + statusMsg);
  bleSendln("=======================");
}

// ============== FLOOR DETECTION ==============
int detectFloorStepwise() {
  float diff    = baselinePressure - currentPressure;
  float absDiff = fabs(diff);
  int   floorOffset = 0;

  if      (absDiff < FLOOR_MIN)                              floorOffset = 0;
  else if (absDiff >= FLOOR_MIN && absDiff <= FLOOR_MAX)     floorOffset = 1;
  else if (absDiff > FLOOR_MAX  && absDiff <= FLOOR_MAX * 2) floorOffset = 2;
  else if (absDiff > FLOOR_MAX * 2 && absDiff <= FLOOR_MAX * 3) floorOffset = 3;
  else                                                        floorOffset = 4;

  int detected = (diff > 0)
                 ? homeFloor + floorOffset
                 : homeFloor - floorOffset;

  if (detected < 0)            detected = 0;
  if (detected >= FLOOR_COUNT) detected = FLOOR_COUNT - 1;

  return detected;
}

// ============== TRACKING DISPLAY ==============
void displayTracking() {
  int detectedFloor = detectFloorStepwise();

  float absDiff = fabs(pressureDiff);
  String rangeStatus = "";
  if      (absDiff < FLOOR_MIN)                              rangeStatus = "Same floor";
  else if (absDiff >= FLOOR_MIN && absDiff <= FLOOR_MAX)     rangeStatus = "1 floor (" + String(FLOOR_MIN,2) + "-" + String(FLOOR_MAX,2) + " hPa)";
  else if (absDiff > FLOOR_MAX  && absDiff <= FLOOR_MAX * 2) rangeStatus = "2 floors (" + String(FLOOR_MAX,2) + "-" + String(FLOOR_MAX*2,2) + " hPa)";
  else if (absDiff > FLOOR_MAX * 2 && absDiff <= FLOOR_MAX * 3) rangeStatus = "3 floors (" + String(FLOOR_MAX*2,2) + "-" + String(FLOOR_MAX*3,2) + " hPa)";
  else                                                        rangeStatus = "4 floors (>" + String(FLOOR_MAX*3,2) + " hPa)";

  String timeStr = getCurrentTime();
  String dateStr = getCurrentDate();

  bleSendln("");
  bleSendln("  ======================================");
  bleSendln("          SmartLocator Status          ");
  bleSendln("  ======================================");
  bleSendln("  Item Name : " + itemName);
  bleSendln("  Time      : " + timeStr);
  bleSendln("  Date      : " + dateStr);
  bleSendln("  Floor     : " + floorNames[detectedFloor]);
  bleSendln("  ======================================");
  bleSendln("  ---- Pressure Observation ----");
  bleSendln("  Baseline  : " + String(baselinePressure, 3) + " hPa");
  bleSendln("  Realtime  : " + String(currentPressure, 3) + " hPa");
  bleSendln("  Diff      : " + String(pressureDiff, 3) + " hPa <-- " + rangeStatus);
  bleSendln("  ======================================");
}

// ============== FILTERING ==============
float getStablePressure() {
  float raw = bme.readPressure() / 100.0F;

  if (isnan(raw) || raw < 950 || raw > 1050)
    return emaPressure > 0 ? emaPressure : 1013.25;

  if (emaPressure > 0 && fabs(raw - emaPressure) > 0.10) {
    for (int i = 0; i < MEDIAN_SIZE; i++) medianBuffer[i] = raw;
    for (int i = 0; i < AVG_SIZE; i++)    avgBuffer[i]    = raw;
    emaPressure = raw;
    medianIndex = 0;
    avgIndex    = 0;
    buffersFull = true;
    return emaPressure;
  }

  medianBuffer[medianIndex] = raw;
  medianIndex = (medianIndex + 1) % MEDIAN_SIZE;

  float sorted[MEDIAN_SIZE];
  memcpy(sorted, medianBuffer, sizeof(medianBuffer));
  for (int i = 0; i < MEDIAN_SIZE - 1; i++)
    for (int j = 0; j < MEDIAN_SIZE - i - 1; j++)
      if (sorted[j] > sorted[j + 1]) {
        float tmp   = sorted[j];
        sorted[j]   = sorted[j + 1];
        sorted[j+1] = tmp;
      }
  float median = sorted[MEDIAN_SIZE / 2];

  avgBuffer[avgIndex] = median;
  avgIndex = (avgIndex + 1) % AVG_SIZE;
  if (!buffersFull && avgIndex == 0) buffersFull = true;

  float sum = 0;
  int count = buffersFull ? AVG_SIZE : avgIndex;
  if (count == 0) count = 1;
  for (int i = 0; i < count; i++) sum += avgBuffer[i];
  float averaged = sum / count;

  emaPressure = (EMA_ALPHA * averaged) + ((1.0 - EMA_ALPHA) * emaPressure);
  return emaPressure;
}

// ============== FULL RESET ==============
void fullReset() {
  baselinePressure = 0;
  pressureDiff     = 0;
  homeFloor        = -1;
  sampleCount      = 0;
  recentIndex      = 0;
  recentFull       = false;
  stabilityReady   = false;
  itemName         = "";
  currentMode      = MODE_ITEM;

  bleSendln("");
  bleSendln("  Reset complete! Starting over...");
  bleSendln("");
  printItemPrompt();
}

// ============== TIME & DATE ==============
String getCurrentTime() {
  unsigned long elapsed = (millis() - startMillis) / 1000;
  int s = (currentSec  + elapsed)          % 60;
  int m = (currentMin  + (elapsed / 60))   % 60;
  int h = (currentHour + (elapsed / 3600)) % 24;

  String t = "";
  if (h < 10) t += "0"; t += String(h) + ":";
  if (m < 10) t += "0"; t += String(m) + ":";
  if (s < 10) t += "0"; t += String(s);
  return t;
}

String getCurrentDate() {
  String months[] = {
    "Jan","Feb","Mar","Apr","May","Jun",
    "Jul","Aug","Sep","Oct","Nov","Dec"
  };
  String days[] = {
    "Sun","Mon","Tue","Wed","Thu","Fri","Sat"
  };
  unsigned long elapsed = (millis() - startMillis) / 1000;
  int totalDays = currentDay + (int)(elapsed / 86400);
  int dow = (4 + totalDays - currentDay) % 7; // 19 Mar 2026 = Thursday = 4
  return days[dow] + ", " + String(totalDays) + " "
       + months[currentMonth - 1] + " " + String(currentYear);
}
