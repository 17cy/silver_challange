import java.net.*;
import java.io.*;

// ─── CONNECTION ───────────────────────────────────────────
Socket socket;
PrintWriter out;
BufferedReader in;

String serverIP   = "192.168.4.1";  // Arduino AP default IP — change if needed
int    serverPort = 5200;

boolean connected = false;

// ─── STATUS & SPEED ───────────────────────────────────────
String statusText = "Not connected";
String speedText  = "— cm/s";
float  lastSpeed  = 0;

// distance input
String distInput = "30";
boolean distFocused = false;

// ─── LAYOUT ───────────────────────────────────────────────
int W = 520, H = 620;

color BG       = #0D0D0D;
color PANEL    = #161616;
color BORDER   = #2A2A2A;
color ACCENT   = #00FF88;
color ACCENT2  = #FF4444;
color TEXTCOL  = #E8E8E8;
color DIMTEXT  = #555555;
color BTNBG    = #1E1E1E;
color BTNHOV   = #252525;

PFont mono;
PFont heading;

// ─── ENCODER TRACKING FOR SPEED ───────────────────────────
int   lastEncR       = 0;
int   lastSpeedTime  = 0;
float  DIST_PER_PULSE = (6.25 * PI) / 8.0;

// ─── BUTTON RECTS ─────────────────────────────────────────
int bW = 130, bH = 52;
int row1Y = 280-25;
int fwdX, leftX, rightX;

int connectBtnX, connectBtnY, connectBtnW = 130, connectBtnH = 36;

// ─── SETUP ────────────────────────────────────────────────
void setup() {
  size(520, 620);
  surface.setTitle("Buggy Control");

  mono    = createFont("Courier New", 13);
  heading = createFont("Courier New Bold", 15);

  fwdX   = W/2 - bW/2;
  leftX  = W/2 - bW - 100;
  rightX = W/2 + 100;

  connectBtnX = W - 160;
  connectBtnY = 24;

  lastSpeedTime = millis();
  
  tryConnect();
}

// ─── DRAW ─────────────────────────────────────────────────
void draw() {
  background(BG);

  // ── top bar
  fill(PANEL);
  noStroke();
  rect(0, 0, W, 64);
  stroke(BORDER);
  strokeWeight(1);
  line(0, 64, W, 64);

  fill(ACCENT);
  textFont(heading);
  textSize(16);
  text("BUGGY CTRL", 24, 40);

  // connection dot
  fill(connected ? ACCENT : ACCENT2);
  noStroke();
  ellipse(connectBtnX - 14, connectBtnY + connectBtnH/2, 8, 8);

  drawButton(connectBtnX, connectBtnY, connectBtnW, connectBtnH,
             connected ? "DISCONNECT" : "CONNECT",
             isHover(connectBtnX, connectBtnY, connectBtnW, connectBtnH));

  // ── distance row
  int rowY = 110;
  textFont(mono);
  textSize(14);
  fill(TEXTCOL);
  text("DISTANCE (cm)", 24, rowY);

  // dist input box
  int dBoxX = 24, dBoxY = rowY + 8, dBoxW = 140, dBoxH = 40;
  stroke(distFocused ? ACCENT : BORDER);
  strokeWeight(1.5);
  fill(BTNBG);
  rect(dBoxX, dBoxY, dBoxW, dBoxH, 4);
  fill(TEXTCOL);
  textFont(mono);
  textSize(18);
  text(distInput + (distFocused && frameCount%60 < 30 ? "|" : ""), dBoxX+12, dBoxY+27);

  // ── controls label
  textSize(14);
  fill(TEXTCOL);
  text("MOVEMENT", 24, 240);

  // ── movement buttons
  boolean fHov   = isHover(fwdX,  row1Y, bW, bH);
  boolean lHov   = isHover(leftX, row1Y, bW, bH);
  boolean rHov   = isHover(rightX,row1Y, bW, bH);

  drawNavButton(fwdX,   row1Y, bW, bH, "▲  FORWARD", fHov, ACCENT);
  drawNavButton(leftX,  row1Y, bW, bH, "<-  LEFT",    lHov, #4488FF);
  drawNavButton(rightX, row1Y, bW, bH, "RIGHT  ->",   rHov, #4488FF);

  // ── status box
  int sBoxY = 380;
  textSize(14);
  textFont(mono);
  fill(TEXTCOL);
  text("STATUS", 24, sBoxY);

  stroke(BORDER);
  strokeWeight(1);
  fill(PANEL);
  rect(24, sBoxY+8, W-48, 80, 4);

  // status colour
  color sCol = TEXTCOL;
  if (statusText.toLowerCase().contains("obstacle")) sCol = ACCENT2;
  else if (statusText.toLowerCase().contains("moving") ||
           statusText.toLowerCase().contains("turning")) sCol = ACCENT;
  else if (statusText.toLowerCase().contains("connect")) sCol = #4488FF;

  fill(sCol);
  textFont(mono);
  textSize(14);
  text(statusText, 36, sBoxY + 52);

  // blinking dot when active
  if ((statusText.contains("Moving") || statusText.contains("Turning")) &&
       frameCount % 40 < 20) {
    fill(ACCENT);
    noStroke();
    ellipse(W - 48, sBoxY + 48, 8, 8);
  }

  // ── speed box
  int spBoxY = 500;
  textFont(mono);
  textSize(14);
  fill(TEXTCOL);
  text("SPEED", 24, spBoxY);

  stroke(BORDER);
  strokeWeight(1);
  fill(PANEL);
  rect(24, spBoxY+8, W-48, 72, 4);

  // speed bar
  float maxSpeed = 60.0;
  float ratio    = constrain(lastSpeed / maxSpeed, 0, 1);
  fill(BORDER);
  noStroke();
  rect(36, spBoxY+50, W-72, 10, 5);
  fill(lerpColor(ACCENT, ACCENT2, ratio));
  rect(36, spBoxY+50, (W-72)*ratio, 10, 5);

  fill(TEXTCOL);
  textFont(mono);
  textSize(20);
  text(speedText, 36, spBoxY + 44);

  // ── footer
  textFont(mono);
  textSize(10);
  fill(TEXTCOL);
  text("IP: " + serverIP + "  PORT: " + serverPort, 24, H - 14);

  // poll incoming
  if (connected) pollIncoming();
}

// ─── BUTTONS ──────────────────────────────────────────────
void drawButton(int x, int y, int w, int h, String label, boolean hov) {
  stroke(BORDER);
  strokeWeight(1);
  fill(hov ? BTNHOV : BTNBG);
  rect(x, y, w, h, 4);
  fill(TEXTCOL);
  textFont(mono);
  textSize(12);
  textAlign(CENTER, CENTER);
  text(label, x + w/2, y + h/2);
  textAlign(LEFT, BASELINE);
}

void drawNavButton(int x, int y, int w, int h, String label, boolean hov, color accent) {
  stroke(hov ? accent : BORDER);
  strokeWeight(hov ? 1.5 : 1);
  fill(hov ? color(red(accent)*0.12, green(accent)*0.12, blue(accent)*0.12) : BTNBG);
  rect(x, y, w, h, 6);
  fill(hov ? accent : TEXTCOL);
  textFont(mono);
  textSize(14);
  textAlign(CENTER, CENTER);
  text(label, x + w/2, y + h/2);
  textAlign(LEFT, BASELINE);
}

boolean isHover(int x, int y, int w, int h) {
  return mouseX >= x && mouseX <= x+w && mouseY >= y && mouseY <= y+h;
}

// ─── MOUSE ────────────────────────────────────────────────
void mousePressed() {
  // connect/disconnect
  if (isHover(connectBtnX, connectBtnY, connectBtnW, connectBtnH)) {
    if (connected) disconnect();
    else           tryConnect();
    return;
  }

  // dist input focus
  int dBoxX = 24, dBoxY = 118, dBoxW = 140, dBoxH = 40;
  distFocused = isHover(dBoxX, dBoxY, dBoxW, dBoxH);

  if (!connected) { statusText = "Not connected"; return; }

  // forward
  if (isHover(fwdX, row1Y, bW, bH)) {
    float dist = float(distInput);
    if (dist <= 0) dist = 30;
    sendCmd("RESET"); 
    sendCmd("CMD:F," + dist);
    sendCmd("GO");
    statusText = "Moving forward " + dist + " cm...";
  }

  // left
  if (isHover(leftX, row1Y, bW, bH)) {
    sendCmd("RESET"); 
    sendCmd("CMD:L,0");
    sendCmd("GO");
    statusText = "Turning left...";
  }

  // right
  if (isHover(rightX, row1Y, bW, bH)) {
    sendCmd("RESET"); 
    sendCmd("CMD:R,0");
    sendCmd("GO");
    statusText = "Turning right...";
  }
}

void keyPressed() {
  if (!distFocused) return;
  if (key == BACKSPACE && distInput.length() > 0)
    distInput = distInput.substring(0, distInput.length()-1);
  else if ((key >= '0' && key <= '9') || key == '.')
    if (distInput.length() < 6) distInput += key;
}

// ─── NETWORK ──────────────────────────────────────────────
void tryConnect() {
  statusText = "Connecting...";
  try {
    socket = new Socket(serverIP, serverPort);
    socket.setSoTimeout(50);  // non-blocking read
    out = new PrintWriter(new OutputStreamWriter(socket.getOutputStream()), true);
    in  = new BufferedReader(new InputStreamReader(socket.getInputStream()));
    connected  = true;
    statusText = "Connected to buggy";
  } catch (Exception e) {
    connected  = false;
    statusText = "Connection failed";
  }
}

void disconnect() {
  try { if (socket != null) socket.close(); } catch (Exception e) {}
  connected  = false;
  statusText = "Disconnected";
  speedText  = "— cm/s";
  lastSpeed  = 0;
}

void sendCmd(String msg) {
  if (out != null) out.println(msg);
}

void pollIncoming() {
  try {
    String line;
    while ((line = in.readLine()) != null) {
      parseIncoming(line.trim());
    }
  } catch (Exception e) {
    // timeout = no data, that's fine
  }
}

void parseIncoming(String line) {
  if (line.length() == 0) return;

  // expect lines like:  STATUS:Moving  or  ENC:35,36  or  DIST:12.4
  if (line.startsWith("STATUS:")) {
    statusText = line.substring(7);
  }
  else if (line.startsWith("DIST:")) {
    float d = float(line.substring(5));
    if (d > 0 && d < 30) statusText = "⚠ Obstacle detected! (" + nf(d,1,1) + " cm)";
  }
  else if (line.startsWith("ENC:")) {
    // ENC:rightCount  — use to calculate speed
    String[] parts = split(line.substring(4), ',');
    if (parts.length >= 1) {
      int encR = int(trim(parts[0]));
      int now  = millis();
      int dt   = now - lastSpeedTime;
      if (dt > 200) {
        int delta = encR - lastEncR;
        float speed = (delta * DIST_PER_PULSE) / (dt / 1000.0);
        lastSpeed  = speed;
        speedText  = nf(speed, 1, 1) + " cm/s";
        lastEncR      = encR;
        lastSpeedTime = now;
      }
    }
  }
  else {
    // fallback: show raw line in status
    if (line.length() > 2) statusText = line;
  }
}
