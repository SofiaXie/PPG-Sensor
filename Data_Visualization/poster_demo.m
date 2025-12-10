%% ================================================================
%  Offline PPG Processing Demonstration
%  - Processes ONLY the first 5 seconds of data
%  - Shows IR/RED raw, cleaned signals, bandpass + peaks,
%    and HR + SpO₂ time series
% ================================================================

clear; close all; clc;

%% ====================== Load Offline Data ========================
load('test13.mat');   % WLpkt must exist

% Convert WLpkt into raw ADC readings (interleaved IR/RED)
WDcatWLpktData(WLpkt);
raw = ans;     % odd = IR, even = RED

%% ===================== LIMIT TO FIRST 5 SECONDS ==================
fs = 300;                % sampling rate (Hz)
duration_sec = 5;        % <-- LIMITING WINDOW
MAX_SAMPLES = fs * duration_sec*2;     % 1500 interleaved samples

raw = raw(1 : min(MAX_SAMPLES/2, length(raw)));

%% ========== Extract IR and RED from interleaved sequence =========
IR_raw  = raw(1, 1:2:end);
RED_raw = raw(1, 2:2:end);

N  = length(IR_raw);
t  = (0:N-1) / 150;       % correct time vector (0–5 seconds)

%% ====================== Filters ================================
[b,a]     = butter(2, 5/(fs/2),  'low');   % <4 Hz lowpass
[bHP,aHP] = butter(2, 1/(fs/2),  'high');  % >1 Hz highpass
[bLP,aLP] = butter(2, 20/(fs/2), 'low');   % <20 Hz lowpass

%% ================================================================
%               PROCESSING STAGES
%% ================================================================

% 1) Noise reduction
IR_clean  = filtfilt(b,a, IR_raw);
RED_clean = filtfilt(b,a, RED_raw);

% 2) Bandpass IR for heartbeat extraction
IR_bp = filtfilt(bHP,aHP, IR_raw);
IR_bp = filtfilt(bLP,aLP, IR_bp);

% 3) Peak detection
minDist = round(0.20 * fs);    % minimum 0.20 sec between beats
[pks, locs] = findpeaks(IR_bp, ...
    'MinPeakDistance', minDist, ...
    'MinPeakProminence', 25);

% 4) Heart Rate estimation
if numel(locs) >= 2
    ibi = diff(locs) / fs;        % inter-beat intervals (seconds)
    HR_series = 30 ./ ibi;        % convert to BPM
    HR = HR_series(end);
else
    HR = NaN;
    HR_series = [];
end

%% ---------------- SpO₂ estimation per beat ----------------------
SpO2_series = nan(1, numel(locs)-1);

for k = 2:numel(locs)
    idx1 = locs(k-1);
    idx2 = locs(k);

    seg_IR  = IR_clean(idx1:idx2);
    seg_RED = RED_clean(idx1:idx2);

    AC_IR  = max(seg_IR)  - min(seg_IR);
    AC_RED = max(seg_RED) - min(seg_RED);

    DC_IR  = mean(seg_IR);
    DC_RED = mean(seg_RED);

    R = (AC_RED/DC_RED) / (AC_IR/DC_IR);
    SpO2_series(k-1) = min(130 - 17*R, 100);
end

SpO2_last = SpO2_series(end);

fprintf("HR = %.1f bpm\n", HR);
fprintf("SpO₂ = %.1f %%\n", SpO2_last);

%% ================================================================
%                      PLOTTING STAGES
%% ================================================================

figure('Name','Offline PPG Processing','Color','w','Position',[50 50 900 1000]);

%% ---- Subplot 1: Raw IR + RED -----------------------------------
subplot(4,1,1);
plot(t, IR_raw,  'b', 'LineWidth', 1.2); hold on;
plot(t, RED_raw, 'r', 'LineWidth', 1.2);
title('Raw IR & RED');
xlabel('Time (s)'); ylabel('ADC');
legend('IR','RED'); grid on;

%% ---- Subplot 2: Cleaned IR + RED -------------------------------
subplot(4,1,2);
plot(t, IR_clean,  'b', 'LineWidth', 1.2); hold on;
plot(t, RED_clean, 'r', 'LineWidth', 1.2);
title('Noise-Reduced Signals (Lowpass 5 Hz)');
xlabel('Time (s)'); ylabel('ADC');
legend('IR Clean','RED Clean'); grid on;

%% ---- Subplot 3: Bandpass IR + Peaks ----------------------------
subplot(4,1,3);
plot(t, IR_bp, 'k', 'LineWidth', 1.2); hold on;
plot(t(locs), pks, 'rx', 'MarkerFaceColor','r', 'LineWidth', 3);
title('IR with Detected Peaks and Addtional HighPass Filter (1Hz)');
xlabel('Time (s)'); ylabel('Amplitude');
legend('Filtered IR','Peaks'); grid on;

%% ---- Subplot 4: Heart Rate and SpO2 Over Time ------------------
subplot(4,1,4);

if ~isempty(HR_series)
    ts_HR = t(locs(2:end));

    % Left axis — Heart Rate
    yyaxis left
    h1 = plot(ts_HR, HR_series, '-o', 'LineWidth', 2);
    ylabel('Heart Rate (BPM)');
    yL = ylim; ylim([yL(1)-5, yL(2)+5]);

    % Right axis — SpO₂
    yyaxis right
    h2 = plot(ts_HR, SpO2_series, '-^', 'LineWidth', 2);
    ylabel('SpO₂ (%)');
    yR = ylim; ylim([yR(1)-2, yR(2)+2]);

    legend([h1 h2], {'Heart Rate','SpO₂'}, 'Location','best');
end

title(sprintf('Heart Rate & SpO₂ Over Time   |   HR = %.1f bpm, SpO₂ = %.1f%%', ...
               HR, SpO2_last));
xlabel('Time (s)');
grid on;
