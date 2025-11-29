clear; close all;

%% ---------------------------------------------------------
% 1. Load raw PPG data
%% ---------------------------------------------------------
load('test13.mat');
WDcatWLpktData(WLpkt);

raw = ans;
ir_data = raw(1, 1:2:end);   % alternating RED
red_data  = raw(1, 2:2:end);   % alternating IR
fs = 150;                     % sampling frequency (Hz)



processPPGOffline(red_data, ir_data, fs);

function processPPGOffline(red_data, ir_data, fs)

if nargin < 3, fs = 150; end


red_data = red_data(:); 
ir_data  = ir_data(:);

% 1. Bandpass filter (0.6–3 Hz)
[b,a] = butter(3, [0.5 4]/(fs/2));
y_red = filtfilt(b,a,red_data);
y_ir  = filtfilt(b,a,ir_data);

% 2. Peak detection (adaptive on IR)
[peak_locs, peak_vals] = detectPeaksAdaptive(y_ir, fs);
if isempty(peak_locs)
    error("No peaks detected");
end

% 3. Heart Rate
peak_times = peak_locs / fs;
RR = diff(peak_times);
HR_inst = 60 ./ RR;
HR_avg = mean(HR_inst);
fprintf("\nEstimated HEART RATE: %.1f bpm\n", HR_avg);

% 4. Offline SpO2 (robust, no reference)
window_len = round(2*fs); % 2-sec windows
step = round(fs);         % 50% overlap
num_windows = floor((length(y_red)-window_len)/step) + 1;

AC_red_all = zeros(1,num_windows);
AC_ir_all  = zeros(1,num_windows);
DC_red_all = zeros(1,num_windows);
DC_ir_all  = zeros(1,num_windows);

for i = 1:num_windows
    idx = (i-1)*step + (1:window_len);
    AC_red_all(i) = max(y_red(idx)) - min(y_red(idx));
    AC_ir_all(i)  = max(y_ir(idx))  - min(y_ir(idx));
    DC_red_all(i) = mean(y_red(idx));
    DC_ir_all(i)  = mean(y_ir(idx));
end

% Keep only valid windows to reduce noise impact
valid = AC_ir_all > 0.01;  
AC_red = median(AC_red_all(valid));
AC_ir  = median(AC_ir_all(valid));
DC_red = median(DC_red_all(valid));
DC_ir  = median(DC_ir_all(valid));

R = (AC_red/DC_red) / (AC_ir/DC_ir);

% Default reflective coefficients
A = 110;  
B = 25;
SpO2 = A - B * R;
fprintf("Estimated SpO2: %.1f %%\n", SpO2);

% 5. Plot results
figure;
subplot(2,1,1); hold on;
plot(y_ir,'b','LineWidth',1.1);
plot(y_red,'r','LineWidth',1.1);
plot(peak_locs, peak_vals,'ko','MarkerSize',6,'LineWidth',1.2);
legend('IR PPG','Red PPG','Detected Peaks');
title(sprintf('Filtered PPG Signals with Peaks (HR = %.1f bpm)', HR_avg));
xlabel('Sample'); ylabel('Amplitude');

subplot(2,1,2); hold on;
plot(y_red,'r','LineWidth',1.2);
title(sprintf('Filtered Red PPG (SpO2 = %.1f%%)', SpO2));
xlabel('Sample'); ylabel('Amplitude');

end



% =========================================================
function [peak_locs, peak_vals] = detectPeaksAdaptive(y_ir, fs)
% Adaptive IR peak detection
y_ir = y_ir(:);
N = length(y_ir);
dy = [0; diff(y_ir)];

% Parameters
win = round(0.75*fs); k = 1.0;
minRR = 0.3; maxRR = 1.5; slopeThresh = 0;

peak_locs = []; peak_vals = []; above = false; peakIndex = 0;

for n = win:N
    window = y_ir(n-win+1:n);
    mu = mean(window); sigma = std(window);
    thr_high = mu + k*sigma;
    thr_low  = mu + 0.4*k*sigma;

    if ~above && y_ir(n)>thr_high && dy(n)>slopeThresh
        above = true; peakIndex = n;
    end
    if above && y_ir(n)<thr_low
        above = false;
        if peakIndex>0
            peak_locs(end+1) = peakIndex;
            peak_vals(end+1) = y_ir(peakIndex);
            peakIndex=0;
        end
    end
end

% Enforce RR constraints
if numel(peak_locs)>1
    RR = diff(peak_locs)/fs;
    toRemove = false(size(peak_locs));
    for i=1:length(RR)
        if RR(i)<minRR || RR(i)>maxRR
            if peak_vals(i)<peak_vals(i+1), toRemove(i)=true;
            else, toRemove(i+1)=true; end
        end
    end
    peak_locs(toRemove) = [];
    peak_vals(toRemove) = [];
end

% Remove duplicates
if ~isempty(peak_locs)
    [peak_locs,u] = unique(peak_locs,'stable');
    peak_vals = peak_vals(u);
end
end












% 
% %% ---------------------------------------------------------
% % 2. Bandpass filter
% %% ---------------------------------------------------------
% f_low = 0.6;  f_high = 3;      % 30–300 BPM
% [b,a] = butter(3, [f_low f_high]/(fs/2));
% 
% y_red = filtfilt(b, a, red_data);
% y_ir  = filtfilt(b, a, ir_data);
% 
% %% ---------------------------------------------------------
% % 3. Peak detection (IR only)
% %% ---------------------------------------------------------
% [peak_locs, peak_vals] = detectPeaksAdaptive(y_ir, fs);
% if isempty(peak_locs), error("No peaks detected"); end
% 
% %% ---------------------------------------------------------
% % 4. Heart Rate
% %% ---------------------------------------------------------
% peak_times = peak_locs / fs;
% RR = diff(peak_times);
% HR_inst = 60 ./ RR;
% HR_avg = mean(HR_inst);
% 
% fprintf("\n===========================================\n");
% fprintf(" Estimated HEART RATE: %.1f bpm\n", HR_avg);
% fprintf("===========================================\n\n");
% 
% %% ---------------------------------------------------------
% % 5. SpO2 (offline)
% %% ---------------------------------------------------------
% AC_red = max(y_red)-min(y_red);
% AC_ir  = max(y_ir)-min(y_ir);
% DC_red = mean(y_red);
% DC_ir  = mean(y_ir);
% 
% R = (AC_red/DC_red) / (AC_ir/DC_ir);
% SpO2 = 110 - 25*R;
% 
% fprintf(" Estimated SpO2: %.1f %%\n", SpO2);
% 
% %% ---------------------------------------------------------
% % 6. Plot results
% %% ---------------------------------------------------------
% figure;
% subplot(2,1,1); hold on;
% plot(y_ir, 'b', 'LineWidth',1.1);
% plot(peak_locs, peak_vals, 'kx','MarkerSize',6,'LineWidth',1.2);
% legend("IR PPG","Detected Peaks");
% title(sprintf("Combined Filtered PPG Signals with Peaks (HR = %.1f bpm)", HR_avg));
% xlabel("Sample"); ylabel("Amplitude");
% 
% subplot(2,1,2); hold on;
% plot(y_red,'r','LineWidth',1.2);
% title(sprintf("Filtered Red PPG (SpO2 = %.1f%%)", SpO2));
% xlabel("Sample"); ylabel("Amplitude");
% 
% %% =========================================================
% % Adaptive IR Peak Detection Function
% %% =========================================================
% function [peak_locs, peak_vals] = detectPeaksAdaptive(y_ir, fs)
% if nargin<2, fs=150; end
% 
% y_ir = y_ir(:);
% N = length(y_ir);
% dy = [0; diff(y_ir)];
% 
% % Parameters
% win = round(0.75*fs);  k = 1.0;
% minRR = 0.3; maxRR = 1.5;  slopeThresh = 0;
% 
% peak_locs = []; peak_vals = []; above = false; peakIndex = 0;
% 
% for n = win:N
%     window = y_ir(n-win+1:n);
%     mu = mean(window); sigma = std(window);
%     thr_high = mu + k*sigma;
%     thr_low  = mu + 0.4*k*sigma;
% 
%     % Start peak
%     if ~above && y_ir(n)>thr_high && dy(n)>slopeThresh
%         above = true; peakIndex = n;
%     end
%     % End peak
%     if above && y_ir(n)<thr_low
%         above = false;
%         if peakIndex>0
%             peak_locs(end+1) = peakIndex;
%             peak_vals(end+1) = y_ir(peakIndex);
%             peakIndex=0;
%         end
%     end
% end
% 
% % Enforce RR constraints
% if numel(peak_locs)>1
%     RR = diff(peak_locs)/fs;
%     toRemove = false(size(peak_locs));
%     for i=1:length(RR)
%         if RR(i)<minRR || RR(i)>maxRR
%             if peak_vals(i)<peak_vals(i+1), toRemove(i)=true;
%             else, toRemove(i+1)=true; end
%         end
%     end
%     peak_locs(toRemove) = [];
%     peak_vals(toRemove) = [];
% end
% 
% % Remove duplicates
% if ~isempty(peak_locs)
%     [peak_locs,u] = unique(peak_locs,'stable');
%     peak_vals = peak_vals(u);
% end
% end
