#include "WiFiS3.h"

char ssid[] = "whyfour";
char pass[] = "12345678";

WiFiServer server(5200);
WiFiClient currentClient;

// Motor pins
const int enL = 6, inL1 = 5, inL2 = 4;
const int enR = 9, inR1 = 7, inR2 = 8;

//ultrasonic pins
const int trigPin = A4;
const int echoPin = A5;
const float threshold = 30.0;

// CD4021 pins
const int data4021Pin = 10;
const int load4021Pin = 11;
const int clk4021Pin  = 12;

// right Encoder
const int encoder2Pin = 3;
volatile unsigned long rightPulseCount = 0;

//left encoder
volatile unsigned long leftPulseCount = 0;
byte lastEncoder1 = 0;

// Wheel constants
const float WHEEL_DIAMETER = 6.25;
const float DIST_PER_PULSE = (WHEEL_DIAMETER * PI) / 8.0;
const float WHEELBASE = 14.5;

// =============================
// CALIBRATION
// =============================

float LEFT_TRIM  = 1.0;
float RIGHT_TRIM = 1.1;

float TURN_SCALE = 0.5;

int BASE_SPEED_L = 120;
int BASE_SPEED_R = 120;

int TURN_SPEED_L = 100;
int TURN_SPEED_R = 100;

// =============================

#define MAX_COMMANDS 20
struct Command { char type; float value; };

Command queue[MAX_COMMANDS];
int numCommands = 0;
int currentCmd = 0;
bool executing = false;

// =============================

void setup() {
  Serial.begin(115200);

  pinMode(enL, OUTPUT);
  pinMode(inL1, OUTPUT);
  pinMode(inL2, OUTPUT);

  pinMode(enR, OUTPUT);
  pinMode(inR1, OUTPUT);
  pinMode(inR2, OUTPUT);

  pinMode(trigPin, OUTPUT);
  pinMode(echoPin, INPUT);

  pinMode(data4021Pin, INPUT);
  pinMode(load4021Pin, OUTPUT);
  pinMode(clk4021Pin,  OUTPUT);

  digitalWrite(load4021Pin, LOW);
  digitalWrite(clk4021Pin, LOW);

  pinMode(encoder2Pin, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(encoder2Pin), rightISR, RISING);

  stopMotors();

  WiFi.beginAP(ssid, pass);
  delay(1000);

  Serial.println(WiFi.localIP());
  server.begin();
}

// =============================

void loop() {
  WiFiClient client = server.available();

  if (client) {
    currentClient = client;
    Serial.println("Client connected");

    while (client.connected()) {

      if (client.available()) {
        String msg = client.readStringUntil('\n');
        msg.trim();
        Serial.println("RX: " + msg);
        handleMessage(msg);
      }

      if (executing && currentCmd < numCommands) {
        executeCommand();
      }
    }

    stopMotors();
    executing = false;
  }
}

// =============================

void handleMessage(String msg) {

  if (msg == "GO") {
    executing = true;
    currentCmd = 0;
  }

  else if (msg == "RESET") {
    numCommands = 0;
    executing = false;
  }

  else if (msg.startsWith("CMD:")) {
    parseCommand(msg.substring(4));
  }
}

// =============================

void parseCommand(String s) {
  int i = s.indexOf(',');
  if (i < 0) return;

  char type = s.charAt(0);
  float val = s.substring(i+1).toFloat();

  if (numCommands < MAX_COMMANDS) {
    queue[numCommands++] = {type, val};
  }
}

// =============================

void executeCommand() {
  Command c = queue[currentCmd];

  if (c.type == 'F') drive(c.value);
  if (c.type == 'L') rotate(false);
  if (c.type == 'R') rotate(true);

  currentCmd++;

  if (currentCmd >= numCommands) {
    executing = false;
  }
}

// =============================
// DRIVE STRAIGHT
// =============================

void drive(float cm) {

  resetEnc();
  int target = cm / DIST_PER_PULSE;

  setMotor(true, true);//chnage the location of this if it keep lagging

while(rightPulseCount < target){
  updateLeftEncoder();

  float dist = measureDistance();
  while(dist > 0 && dist < threshold){
    stopMotors();
    delay(100);
    dist = measureDistance();
  }

  long diff = (long)leftPulseCount - (long)rightPulseCount;
  int correction = diff * 1; //change 1 for calibration

  int leftSpeed  = constrain((BASE_SPEED_L * LEFT_TRIM)  - correction, 0, 255);
  int rightSpeed = constrain((BASE_SPEED_R * RIGHT_TRIM) + correction, 0, 255);

  analogWrite(enL, leftSpeed);
  analogWrite(enR, rightSpeed);

  delay(5);
  }

  stopMotors();
}

// =============================
// TURN 90°
// =============================

void rotate(bool clockwise) {

  float arc = (90.0 / 360.0) * PI * WHEELBASE;
  arc *= TURN_SCALE;

  int target = arc / DIST_PER_PULSE;

  resetEnc();

  if (clockwise) setMotor(true, false);
  else           setMotor(false, true);

  analogWrite(enL, TURN_SPEED_L);
  analogWrite(enR, TURN_SPEED_R);

  while (rightPulseCount < target) {
    delay(5);
  }

  stopMotors();
}

// =============================

void rightISR() {
  rightPulseCount++;
}

void resetEnc() {
  noInterrupts();
  rightPulseCount = 0;
  leftPulseCount  = 0;
  interrupts();
  lastEncoder1 = 0;
}

// =============================

void setMotor(bool lf, bool rf) {
  digitalWrite(inL1, lf);
  digitalWrite(inL2, !lf);
  digitalWrite(inR1, rf);
  digitalWrite(inR2, !rf);
}

void stopMotors() {
  analogWrite(enL, 0);
  analogWrite(enR, 0);
}

float measureDistance(){

  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin,HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);
  delayMicroseconds(200);

  unsigned long duration = pulseIn(echoPin,HIGH, 20000);

  if(duration == 0) return 0;

  return (duration*0.034)/2;
}

//===========================//

byte read4021() {
  byte value = 0;

  // latch parallel inputs
  digitalWrite(load4021Pin, HIGH);
  delayMicroseconds(5);
  digitalWrite(load4021Pin, LOW);
  delayMicroseconds(5);

  for (int i = 0; i < 8; i++) {
    value <<= 1;
    if (digitalRead(data4021Pin)) {
      value |= 1;
    }

    digitalWrite(clk4021Pin, HIGH);
    delayMicroseconds(5);
    digitalWrite(clk4021Pin, LOW);
    delayMicroseconds(5);
  }

  return value;
}

void updateLeftEncoder(){
  byte encoder1Raw = read4021();
  
  byte bit1 = (encoder1Raw >> 1)& 0x01;
  byte lastBit1 = (lastEncoder1 >> 1) & 0x01;
  if (bit1 && !lastBit1) leftPulseCount++;
  lastEncoder1 = encoder1Raw;
}

