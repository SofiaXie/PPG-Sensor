## PPG Sensor Project

This project develops a Bluetooth-based photoplethysmography (PPG) sensor for wireless pulse-rate monitoring in real-time. The PPG sensor estimates pulse rate by measuring variations in light absorption through the skin, while red and infrared (IR) LEDs approximate blood oxygen saturation (SpO₂) levels. Two Arduino Nano 33 BLE Rev2’s transmits PPG data using Bluetooth low energy (BLE). MATLAB processes are used to filter and compute pulse rate and SpO₂, displaying everything in real-time.

### Repo Organization
***Data_Visualization:***
contains the MATLAB files used to generate Figures 9 and 10. 

***Project Code:***
Files for running PPG sensor code. Files for programing the peripherial and central Arduino's. 

***Test_Data:***
Files captures from serial port used to visualize data and test the system.
