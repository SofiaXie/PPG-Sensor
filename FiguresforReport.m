%% Figures for report

%% PPG SENSOR TOPOLOGY AND SYNCHRONIZED ILLUMINATION CONTROL
b = load("PPG_BLE_CL18_Housing.mat"); 
c = load("PPG_BLE_CL18_no_house.mat");

B = WDcatWLpktData(b.WLpkt);
B1 = B(1:2:end); %IR
B2 = B(2:2:end); %red

C = WDcatWLpktData(c.WLpkt);
C1 = C(1:2:end); %IR
C2 = C(2:2:end); %red

fs = 300; %Hz
t_B = (0:length(B1)-1) / fs; 
t_C = (0:length(C1)-1) / fs;

figure;
subplot(1,2,1); plot(t_B, B1(1, :), 'b'); hold on;
subplot(1,2,1); plot(t_B, B2(1, :), 'r'); 
title("Housing"); xlabel("Time (seconds)"); ylabel("ADC Counts");
legend('IR','Red'); ylim([0 5000]); xlim([0 5]);

subplot(1,2,2); plot(t_C, C1(1, :), 'b'); hold on;
subplot(1,2,2); plot(t_C, C2(1, :), 'r'); 
title("No Housing"); xlabel("Time (seconds)"); ylabel("ADC Counts");
legend('IR','Red'); ylim([0 5000]); xlim([0 5]);



%% //////////////////////////////////////////
%% Wireless Communication Architecture:

d = load("PPG_BLE_CL18_Housing.mat");
e = load("PPG_BLE_CL4_housing.mat"); %Compare varying channel lengths
% e = load("PPG_USB_CL18_housing.mat"); %Compare Communication protocal

D = WDcatWLpktData(d.WLpkt);
D1 = D(1:2:end); %IR
D2 = D(2:2:end); %red
E = WDcatWLpktData(e.WLpkt);
E1 = E(1:2:end); %IR
E2 = E(2:2:end); %red
F = WDcatWLpktData(f.WLpkt);
F1 = F(1:2:end); %IR
F2 = F(2:2:end); %red

fs = 300; %Hz
t_d = (0:length(D1)-1) / fs; 
t_e = (0:length(E1)-1) / fs; 


figure;
subplot(2,1,1); plot(t_d, D1(1, :), 'b'); hold on;
subplot(2,1,1); plot(t_e, E1(1, :), 'm'); hold on;
title("IR Samples"); xlabel("Time (seconds)"); ylabel("ADC Counts");
legend('CL 18','CL 4'); xlim([0 5]);

subplot(2,1,2); plot(t_d, D2(1, :), 'b'); hold on;
subplot(2,1,2); plot(t_e, E2(1, :), 'm'); hold on;
title("Red Samples"); xlabel("Time (seconds)"); ylabel("ADC Counts");
legend('CL 18','CL 4'); xlim([0 5]);


%% Calculate and print Dropped Packets
fprintf('----------------------------------------\n');
fprintf('Dropped Packet Analysis\n');
fprintf('----------------------------------------\n');

% --- Analysis for CL 18 (Variable d) ---
% Extract timestamps from the struct (Vectorized method)
ts_d = [d.WLpkt.ts_p]; 

% Calculate logic: (Last - First + 1) is expected packets. 
% Subtract length(ts_d) (received packets) to find drops.
expected_d = (ts_d(end) - ts_d(1)) + 1;
received_d = length(ts_d);
dropped_d  = expected_d - received_d;

fprintf('Dataset CL 18:\n');
fprintf('  Expected Packets: %d\n', expected_d);
fprintf('  Received Packets: %d\n', received_d);
fprintf('  Dropped Packets:  %d\n', dropped_d);
fprintf('\n');

% --- Analysis for CL 4 (Variable e) ---
% Extract timestamps
ts_e = [e.WLpkt.ts_p];

% Calculate logic
expected_e = (ts_e(end) - ts_e(1)) + 1;
received_e = length(ts_e);
dropped_e  = expected_e - received_e;

fprintf('Dataset CL 4:\n');
fprintf('  Expected Packets: %d\n', expected_e);
fprintf('  Received Packets: %d\n', received_e);
fprintf('  Dropped Packets:  %d\n', dropped_e);
fprintf('----------------------------------------\n');

% Optional: Plot packet diffs to visualize where drops occurred
figure;
subplot(2,1,1); plot(diff(ts_d)); title('CL 18 Packet Intervals'); ylabel('Step Size');
subplot(2,1,2); plot(diff(ts_e)); title('CL 4 Packet Intervals'); ylabel('Step Size');