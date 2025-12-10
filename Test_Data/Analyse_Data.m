%% Data for final report
close all, clear;

% Data
d = load("PPG_BLE_CL18_Housing.mat"); %CL 18
% e = load("PPG_BLE_CL4.mat"); %CL 4
e = load("PPG_USB_CL18_housing.mat"); %CL 18

D = WDcatWLpktData(d.WLpkt);
D1 = D(1:2:end); %IR
D2 = D(2:2:end); %red
E = WDcatWLpktData(e.WLpkt);
E1 = E(1:2:end); %IR
E2 = E(2:2:end); %red
% F = WDcatWLpktData(f.WLpkt);
% F1 = F(1:2:end); %IR
% F2 = F(2:2:end); %red

fs = 300; %Hz
t_d = (0:length(D1)-1) / fs; 
t_e = (0:length(E1)-1) / fs; 


figure;
subplot(4,1,1); plot(t_d, D1(1, :), 'b'); xlim([0 5]);legend('BLE');
title("IR Samples"); ylabel("ADC Counts");
% ylim([1500 3000]); 
subplot(4,1,2); plot(t_e, E1(1, :), 'm'); xlim([0 5]);  legend('USB');
% ylim([1500 3000]);
ylabel("ADC Counts");
xlabel("Time (seconds)"); 


subplot(4,1,3); plot(t_d, D2(1, :), 'b'); xlim([0 5]);ylim([150 300]); legend('BLE');
title("Red Samples"); ylabel("ADC Counts");
subplot(4,1,4); plot(t_e, E2(1, :), 'm'); xlim([0 5]); ylim([150 300]); legend('USB');
ylabel("ADC Counts");
xlabel("Time (seconds)"); 

% subplot(2,2,3); plot(B1(1, :), 'b'); hold on;
% subplot(2,2,3); plot(B2(1, :), 'r'); title("Housing");
% legend('IR','Red'); ylim([0 5000]);
% 
% subplot(2,2,4); plot(C1(1, :), 'c'); hold on;
% subplot(2,2,4); plot(C2(1, :), 'm'); title("No Housing");
% legend('IR','Red'); ylim([0 5000]);
% 
% %% close up of the IR signals
% figure;
% subplot(2,1,1); plot(B1(1, :), 'b'); title("Housing"); 
% subplot(2,1,2); plot(C1(1, :), 'c'); title("No Housing");


% % see dropped packets for BLE
% load("ppg_ble_CL4.mat");
% 
% T = WDcatWLpktData(WLpkt);
% % A = zeros();
% A = zeros(length(WLpkt), 1); % Preallocate A to store timestamps
% 
% for i= 1:length(WLpkt)
%     A(i) = WLpkt(i).ts_p;
% end
% 
% plot(diff(A));
% 
% total_dropped = ((WLpkt(length(WLpkt)).ts_p - WLpkt(1).ts_p)-length(WLpkt))+1


% --- 4. Calculate and Print Dropped Packets ---
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

fprintf('Dataset BLE:\n');
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

fprintf('Dataset USB:\n');
fprintf('  Expected Packets: %d\n', expected_e);
fprintf('  Received Packets: %d\n', received_e);
fprintf('  Dropped Packets:  %d\n', dropped_e);
fprintf('----------------------------------------\n');

% Optional: Plot packet diffs to visualize where drops occurred
figure;
subplot(2,1,1); plot(diff(ts_d)); title('CL 18 Packet Intervals'); ylabel('Step Size');
subplot(2,1,2); plot(diff(ts_e)); title('CL 4 Packet Intervals'); ylabel('Step Size');