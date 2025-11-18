//    Central BLE software added originally (2025) by KJR, using open-source
//  software from: https://docs.arduino.cc/tutorials/nano-33-ble-sense/ble-device-to-device/.
//  Arduino tutorials referring to this software can be found at:
//  https://docs.arduino.cc/hardware/nano-33-ble-sense-rev2/#tutorials.

#include <ArduinoBLE.h>
////////////////////////////////// These first "#define" values must match NanoP.
#define ADC_CHANS  1            // ADC channels.
#define ADC_CHAN_LEN  10        // ADC samples/channel before xmit packet. CI = ADC_CHAN_LEN/ADC_Hz.
#define ADC_HZ  1000            // ADC sampling rate (Hz).                 CI must be >= 7.5 ms.

#define PKT_DAT_BYT (2*ADC_CHANS*ADC_CHAN_LEN) // Number data bytes in a packet---EXCLUDES header.
#define PKT_HDR_BYT 26                         // Number header bytes in a packet---EXCLUDES data.
#define PKT_BYT (PKT_HDR_BYT+PKT_DAT_BYT)      // Total bytes in a packet. Must be <= 251.

static uint8_t Pkt[PKT_BYT] = {0}; // Full packet (header + data). See spec. Little endian.

void setup() {
  // Initialize non-zero header values. See spec.
  uint16_t Temp16; // Needed so can pass-by-address for uint16_t values.
  Pkt[0]=0x5A; Pkt[1]=0x0F; Pkt[2]=0xBE; Pkt[3]=0x66; // Sync. Endianess??
  Temp16 =         256; memcpy(&Pkt[4], &Temp16, 2);  // Version.
  Temp16 =      ADC_HZ; memcpy(&Pkt[6], &Temp16, 2);  // Sampling rate.
  Pkt[8] = ADC_CHANS-1;                               // ADC channels - 1.
  Pkt[9] = 1;                                         // Type.
  // Set up serial port, BLE.
  Serial.begin(115200);                      // Initialize and set serial port baud rate.
  while (!Serial);                           // Wait for serial port to be ready.
  BLE.begin();                               // Initialize BLE library.
  BLE.setConnectionInterval(0x0008, 0x0008); // Set CI, increment=1.25 ms. So, min, max CI=8x1.25 ms=10 ms.
  TextPkt("C: Bluetooth® Setup");            // Send welcome message.
  BLE.scanForUuid("2c56a03e-794e-47f4-a5c8-45f41c233442");  // Scan for device with custom-specified UUID.
}

void loop() {
  BLEDevice peripheral = BLE.available(); // Check if custom-specified peripheral has been discovered.

  if (peripheral) { // Discovered peripheral; print address, local name, advertised service.
    char text[200]; // Buffer for text message.
    TextPkt("C: Found"); // Break up message to fit data packet size = 2*ADC_CHANS*ADC_CHAN_LEN bytes.
    sprintf(text, "  %s",   peripheral.address());               TextPkt(text);
    sprintf(text, "  '%s'", peripheral.localName());             TextPkt(text);
    sprintf(text, "  %s",   peripheral.advertisedServiceUuid()); TextPkt(text);

    BLE.stopScan();                // Stop scanning for custom-specific peripheral.
    getPeripheralData(peripheral); // While discovered, infinite loop checking for data.
  }
}

void TextPkt(char* Text) { // Transmit text packet. 
  // Text: Character vector to send. Coerce to same length as data!
  uint32_t Length = strlen(Text); // Message length, excluding ending null.
  if (Length >= PKT_DAT_BYT) { Length = PKT_DAT_BYT; } // Truncate overlength.
  Text[Length-1] = '\0';           // Coerce null at text end.
  uint8_t Type = Pkt[9];           // Temp storage of existing data type.
  Pkt[ 9] = (uint8_t) 255;         // Set packet data type to text.
  memcpy(&Pkt[10], &Length, 4);    // For text, Length in ts_a.
  Pkt[25] = (uint8_t) PKT_DAT_BYT; // Always send full data packet.
  memcpy(&Pkt[26], Text, Length);  // Copy text into data field; packet ready.
  //delay(10);                       // Pause 10 ms so do not flood BLE.
  Serial.write((uint8_t *) Pkt, PKT_HDR_BYT+Length); // Write full packet.
  //delay(10);                       // Pause 10 ms so do not flood BLE.
  Pkt[9] = Type;                  // Reset packet data type.
}

void getPeripheralData(BLEDevice peripheral) {

  TextPkt("C: Connecting?");

  if (peripheral.connect()) { TextPkt("C: Connected");} // Successful connection?
  else {                      TextPkt("C: Connect failed!"); return;
  }

  // Discover peripheral attributes. Return if attributes fail.
  TextPkt("C: Attributes?");
  if (peripheral.discoverAttributes()) { TextPkt("C: Attributes OK");  }
  else {
    TextPkt("C: Attributes failed");
    peripheral.disconnect();
    return;
  }
  // Subscribe to sensor characteristic to wait for updates (i.e., data) from peripheral.
  BLECharacteristic sensorCharacteristic = peripheral.characteristic("2c56a03e-794e-47f4-a5c8-45f41c233442");
  sensorCharacteristic.subscribe(); 
  while (peripheral.connected()) { // While connected to the peripheral.
    if (sensorCharacteristic.valueUpdated()) { // Characteristic/data has been updated.
      int count; // Number of bytes read.
      count = sensorCharacteristic.readValue(Pkt, PKT_BYT);
      Serial.write(Pkt, count); // Serial stream to PC.
    } // if (sensorCharacteristic.valueUpdated())
  } // while (peripheral.connected())
} // void getPeripheralData()
