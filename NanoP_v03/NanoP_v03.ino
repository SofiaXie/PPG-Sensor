// ADC sampling adapted from: https://forum.arduino.cc/t/increase-the-adc-sample-rate/701813/3
//  (open source) and subsequently enhanced.  Original example sampled one nRF52840 SAADC
//  channel using a Timer and PPI. The SAADC uses EasyDMA to copy each sample into a memory
//  location. Current version samples from 1-4 channels (user selectable at compilation)
//  from AnalogInput2 through AnalogInput5. A "scan" is comprised of samples from all
//  in-use channels. An interrupt is generated after each scan. The interrupt service routine (ISR)
//  transfers the ADC data to a software buffer each scan. When a sufficient number of scans have
//  been acquired, a flag is set and an alternate software buffer is toggled. When the main
//  routine ("loop") finds this flag set, it transfers the acquired data in a packet.
//    Peripheral BLE software added originally (2025) by KJR, using open-source
//  software from: https://docs.arduino.cc/tutorials/nano-33-ble-sense/ble-device-to-device/.
//  Arduino tutorials referring to this software can be found at:
//  https://docs.arduino.cc/hardware/nano-33-ble-sense-rev2/#tutorials.
//  ADC Notes:
//  - the maximum sampling rate is 200k Samples/s
//  - the original ADC code has not been tested with a debugger, some samples might be lost due to mbedOS (needs further testing)
//  - this code will likely not work when using analogRead() on other pins
//  Target microcontroller: Arduino Nano 33 BLE/ BLE Sense board.

#include "mbed.h"
////////////////////// "#define" values most likely to be changed. //////////////////////
#define ADC_CHANS  1            // ADC channels.
#define ADC_CHAN_LEN  10        // ADC samples/channel before xmit packet. CI = ADC_CHAN_LEN/ADC_Hz.
#define ADC_HZ  300           // ADC sampling rate (Hz).                 CI must be >= 7.5 ms.
#define USBorBLE  1             // Data communication channel: 0 = USB, 1 = BLE.

#define ADC_HBUF_LEN  ADC_CHANS                // ADC hardware samples before interrupt issued.
#define PKT_DAT_BYT (2*ADC_CHANS*ADC_CHAN_LEN) // Number data bytes in a packet---EXCLUDES header.
#define PKT_HDR_BYT  26                        // Number header bytes in a packet---EXCLUDES data.
#define PKT_BYT (PKT_HDR_BYT+PKT_DAT_BYT)      // Total bytes in a packet. Must by <= 251.

#define PPI_CHANNEL         (7)

#define LED_A  9 
#define LED_B  10


#if USBorBLE == 1 // 1 ==> Enable BLE.
  #include <ArduinoBLE.h>
  BLEService sensorService("2c56a03e-794e-47f4-a5c8-45f41c23567a"); // BLE custom UUID (generate at https://www.uuidgenerator.net).
  // Bluetooth® Low Energy Characteristic - custom 128-bit UUID, read, notify and write enabled
  BLECharacteristic sensorCharacteristic("3d0f70f0-3fe0-462a-827f-ce0cce193442", BLERead | BLEWrite | BLENotify, PKT_BYT); 
#endif

volatile nrf_saadc_value_t adcBuffer[ADC_HBUF_LEN]; // Hardware ADC samples. Must be 2 bytes/sample.
static uint16_t adc_buf[2][ADC_CHAN_LEN*ADC_CHANS]; // Software ADC samples before x-mitting. Double-buffered.
static uint8_t Pkt[PKT_BYT] = {0}; // Full packet (header + data). See spec. Little endian.
static uint16_t IbufISR = 0;       // Index to ADC buffer in adc_buf[] currently in use by ISR.
static uint32_t ts_a = 0;          // ADC timestamp. Init. to 0 for debugging.
static uint32_t ts_p = 1;          // Supposed to be peripheral timestamp. Using now as packet counter.
volatile bool newScan = false;
static bool ledToggle = false;

void setup() {
  // Initialize non-zero header values. See spec.
  uint16_t Temp16; // Needed so can pass-by-address for uint16_t values.
  Pkt[0]=0x5A; Pkt[1]=0x0F; Pkt[2]=0xBE; Pkt[3]=0x66; // Sync. Endianess??
  Temp16 =         256; memcpy(&Pkt[4], &Temp16, 2);  // Version.
  Temp16 =      ADC_HZ; memcpy(&Pkt[6], &Temp16, 2);  // Sampling rate.
  Pkt[8] = ADC_CHANS-1;                               // ADC channels - 1.
  Pkt[9] = 1;                                         // Type.
  // Set up serial port, and, if selected, BLE.
  Serial.begin(115200); // Initialize and set serial port baud rate.
  while (!Serial);      // Wait for serial port to be ready.

  #if USBorBLE == 1  // 1 ==> Enable BLE.
    if (!BLE.begin()) { while (1); }
    else { // Initialize BLE parameters and configure sensor service.
      BLE.setDeviceName("Arduino Nano 33 BLE Sense"); // Device name seen in BLE scanning software.
      BLE.setLocalName("WPI Sensors");                // Local name seen when scanning for BLE devices.
      BLE.setAdvertisedService(sensorService);
      BLE.setConnectionInterval(0x0008, 0x0008); // Set CI, increment=1.25 ms. So, min, max CI=8x1.25 ms=10 ms.
      sensorService.addCharacteristic(sensorCharacteristic);
      BLE.addService(sensorService);
      sensorCharacteristic.writeValue((byte) 0x00); // Set characteristic initial value.
      BLE.advertise(); // Start to advertise that this peripheral is available.
      Serial.println("P: Advertising as peripheral");
    }
  #endif

  initADC();            // Local function to initialize SAADC.
  initTimer4();         // Local function to setup, start Timer 4.
  initPPI();            // Local function: assign/connect Timer 4 to SAADC.
  
  pinMode(LED_A, OUTPUT); //red
  pinMode(LED_B, OUTPUT); //ir
}

void loop() { // Main (infinite) loop.
  static int16_t IbufLoop = 0; // Next ADC buffer (0 or 1) to transmit.

  #if USBorBLE == 1 // 1 ==> BLE.
    BLEDevice central = BLE.central(); // Listen for BLE peripherals to connect.
    if (central) { // If a central is connected to peripheral.
      Serial.print("P: Connected to central: ");
      Serial.println(central.address()); // Print the central's MAC address.
      while (central.connected()) { // Send packets while central connected to peripheral.
  #endif

        if (IbufISR != IbufLoop) { // Is an ADC buffer ready to transmit?
          // Ready packet.
          memcpy(&Pkt[10], &ts_a, 4);      // ADC timestamp this packet.
          memcpy(&Pkt[18], &ts_p, 4);      // Packet counter.
          Pkt[25] = (uint8_t) PKT_DAT_BYT; // .Dlen for this packet.
          memcpy(&Pkt[PKT_HDR_BYT], adc_buf[IbufLoop], PKT_DAT_BYT); // Insert data; packet ready.
          // Transmit packet.
          #if USBorBLE == 1 //1 ==> BLE; else USB. Either method, transmit full packet.
            sensorCharacteristic.writeValue(Pkt, PKT_BYT);
          #else
            Serial.write((uint8_t *) Pkt, PKT_BYT);
          #endif
          IbufLoop = IbufISR; // Switch to other ADC buffer for subsequent passes.
        } // if (IbufISR ....

  #if USBorBLE == 1 // 1 ==> BLE.
      } // while (central.connected...)
      Serial.print(("P: Disconnected from central: ")); // Messages when central disconnects.
      Serial.println(central.address());
    } // if (central)....
  #endif
  // if(newScan) {
  //   newScan = false;
  //   ledToggle = !ledToggle;
  //   digitalWrite(LED_A, ledToggle);
  //   digitalWrite(LED_B, !ledToggle);
  // }

}

extern "C" void SAADC_IRQHandler_v( void ) { // Apparently hardcoded IRQ function name.
  static int m = 0; // Sample index into storage buffer adc_buf[];
  if ( NRF_SAADC->EVENTS_END != 0 ) { // Has SAADC filled up the result buffer?
    newScan = true;

    ledToggle = !ledToggle;
    digitalWrite(LED_A, ledToggle);
    digitalWrite(LED_B, !ledToggle);
    
    NRF_SAADC->EVENTS_END = 0;                            // Reset register flag.
    for (int chan = 0; chan < ADC_CHANS; chan++) {        // Store samples from all channels.
      adc_buf[IbufISR][m++] = (uint16_t) adcBuffer[chan]; // Get sample from hardware-directed memory.
    }
    if (m==ADC_CHAN_LEN*ADC_CHANS) {   // Is the buffer full?
      ts_a = micros();                 // ADC timestamp (us); ~corresponds to last sample.
      IbufISR = IbufISR ^ (uint16_t)1; // Switch buffers: 0^1=1 while 1^1=0. (Bitwise XOR.)
      ts_p++;                          // Increment packet counter.
      m = 0;                           // Reset buffer sample index to zero.
    }
  }
}

void initADC() {
  nrf_saadc_disable();                                // Disable SAADC.
  NRF_SAADC->RESOLUTION = NRF_SAADC_RESOLUTION_12BIT; // Set ADC resolution to 12 bits.

  // Channel 0: => AnalogInput2 (AIN2, A0)).
  NRF_SAADC->CH[0].CONFIG = ( SAADC_CH_CONFIG_GAIN_Gain1_4  << SAADC_CH_CONFIG_GAIN_Pos )   |
                            ( SAADC_CH_CONFIG_MODE_SE       << SAADC_CH_CONFIG_MODE_Pos )   |
                            ( SAADC_CH_CONFIG_REFSEL_VDD1_4 << SAADC_CH_CONFIG_REFSEL_Pos ) |
                            ( SAADC_CH_CONFIG_RESN_Bypass   << SAADC_CH_CONFIG_RESN_Pos )   |
                            ( SAADC_CH_CONFIG_RESP_Bypass   << SAADC_CH_CONFIG_RESP_Pos )   |
                            ( SAADC_CH_CONFIG_TACQ_3us      << SAADC_CH_CONFIG_TACQ_Pos );
  NRF_SAADC->CH[0].PSELP = SAADC_CH_PSELP_PSELP_AnalogInput2 << SAADC_CH_PSELP_PSELP_Pos;
  NRF_SAADC->CH[0].PSELN = SAADC_CH_PSELN_PSELN_NC << SAADC_CH_PSELN_PSELN_Pos;

 // Channel 1: => AnalogInput3 (AIN3, A1).
  #if ADC_CHANS > 1
  NRF_SAADC->CH[1].CONFIG = NRF_SAADC->CH[0].CONFIG;
  NRF_SAADC->CH[1].PSELP = SAADC_CH_PSELP_PSELP_AnalogInput3 << SAADC_CH_PSELP_PSELP_Pos;
  NRF_SAADC->CH[1].PSELN = SAADC_CH_PSELN_PSELN_NC           << SAADC_CH_PSELN_PSELN_Pos;
  #endif
 
  // Channel 2: => AnalogInput4 (AIN4, A6).
  #if ADC_CHANS > 2
  NRF_SAADC->CH[2].CONFIG = NRF_SAADC->CH[0].CONFIG;
  NRF_SAADC->CH[2].PSELP = SAADC_CH_PSELP_PSELP_AnalogInput4 << SAADC_CH_PSELP_PSELP_Pos;
  NRF_SAADC->CH[2].PSELN = SAADC_CH_PSELN_PSELN_NC           << SAADC_CH_PSELN_PSELN_Pos;
  #endif
  
  // Channel 3: => AnalogInput5 (AIN5, A3).
  #if ADC_CHANS > 3
  NRF_SAADC->CH[3].CONFIG = NRF_SAADC->CH[0].CONFIG;
  NRF_SAADC->CH[3].PSELP = SAADC_CH_PSELP_PSELP_AnalogInput5 << SAADC_CH_PSELP_PSELP_Pos;
  NRF_SAADC->CH[3].PSELN = SAADC_CH_PSELN_PSELN_NC           << SAADC_CH_PSELN_PSELN_Pos;
  #endif

  NRF_SAADC->RESULT.MAXCNT = ADC_HBUF_LEN; // Max 16-bit samples written to NRF_SAADC->RESULT.PTR.
  NRF_SAADC->RESULT.PTR = ( uint32_t )&adcBuffer; // Where ADC samples are stored.
  NRF_SAADC->EVENTS_END = 0;
  nrf_saadc_int_enable( NRF_SAADC_INT_END );
  NVIC_SetPriority( SAADC_IRQn, 1UL );
  NVIC_EnableIRQ( SAADC_IRQn );

  nrf_saadc_enable();  // Enable SAADC.

  NRF_SAADC->TASKS_CALIBRATEOFFSET = 1;
  while ( NRF_SAADC->EVENTS_CALIBRATEDONE == 0 );
  NRF_SAADC->EVENTS_CALIBRATEDONE = 0;
  while ( NRF_SAADC->STATUS == ( SAADC_STATUS_STATUS_Busy << SAADC_STATUS_STATUS_Pos ) );
}


void initTimer4() { // Setup and start Timer 4.
  NRF_TIMER4->MODE = TIMER_MODE_MODE_Timer;
  NRF_TIMER4->BITMODE = TIMER_BITMODE_BITMODE_16Bit;
  NRF_TIMER4->SHORTS = TIMER_SHORTS_COMPARE0_CLEAR_Enabled << TIMER_SHORTS_COMPARE0_CLEAR_Pos;
  NRF_TIMER4->PRESCALER = 0;
  NRF_TIMER4->CC[0] = 16000000 / ADC_HZ; // Needs prescaler set to 0 (1:1) 16MHz clock
  NRF_TIMER4->TASKS_START = 1;
}


void initPPI() { // Associate/connect Timer 4 to trigger the SAADC.
  NRF_PPI->CH[PPI_CHANNEL].EEP = ( uint32_t )&NRF_TIMER4->EVENTS_COMPARE[0];
  NRF_PPI->CH[PPI_CHANNEL].TEP = ( uint32_t )&NRF_SAADC->TASKS_START;
  NRF_PPI->FORK[PPI_CHANNEL].TEP = ( uint32_t )&NRF_SAADC->TASKS_SAMPLE;
  NRF_PPI->CHENSET = ( 1UL << PPI_CHANNEL );
}
