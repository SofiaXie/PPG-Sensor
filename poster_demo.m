%% ================================================================
%  Offline PPG Processing Demonstration
%  Shows each processing stage in clean subplots
%  Now includes:
%     • Sample limiting
%     • SpO₂ time-series
%     • HR + SpO₂ over time on same subplot (dual axis)
% ================================================================

clear; close all; clc;

%% ====================== Load Offline Data ========================
load('test13.mat');   % WLpkt must exist

% Convert to raw ADC vector
WDcatWLpktData(WLpkt);
raw = ans;   % raw interleaved ADC values: IR = odd, RED = even

%% ===================== LIMIT SAMPLES =============================
MAX_SAMPLES = 3000;                 % <== change this freely
raw = raw(1 : min(MAX_SAMPLES, length(raw)));

%% ========== Extract IR and RED from interleaved sequence =========
IR_raw  = raw(1, 1:2:end);
RED_raw = raw(1, 2:2:end);

fs = 300;                    % sampling rate
N  = length(IR_raw);
t  = (0:N-1)/fs;             % time vector

%% ====================== Filters ================================

[b,a]     = butter(3, 40/(fs/2), 'low');   % lowpass <40 Hz
[bHP,aHP] = butter(3, 1/(fs/2),  'high');  % highpass >1 Hz
[bLP,aLP] = butter(3, 20/(fs/2), 'low');   % lowpass <20 Hz

%% ================================================================
%               PROCESSING STAGES
%% ================================================================

% 1) Noise-reduced versions
IR_clean  = filtfilt(b,a, IR_raw);
RED_clean = filtfilt(b,a, RED_raw);

% 2) Bandpass IR for heartbeat extraction
IR_bp = filtfilt(bHP,aHP, IR_raw);
IR_bp = filtfilt(bLP,aLP, IR_bp);

% 3) Peak detection (IR)
minDist = round(0.20 * fs);   % min 0.20 sec between beats
[pks, locs] = findpeaks(IR_bp, ...
    'MinPeakDistance', minDist, ...
    'MinPeakProminence', 25);

% 4) Heart Rate estimation
if numel(locs) >= 2
    ibi = diff(locs) / fs;          % interbeat intervals
    HR_series = 30 ./ ibi;          % HR for each interval
    HR = HR_series(end);
else
    HR = NaN;
    HR_series = [];
end

%% ---------------- SpO2 estimation per beat ----------------------
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
fprintf("SpO2 = %.1f %%\n", SpO2_last);

%% ================================================================
%                      PLOTTING STAGES
%% ================================================================

figure('Name','Offline PPG Processing','Color','w','Position',[50 50 900 1000]);

%% ---- Subplot 1: Raw Interleaved Data ----------------------------
subplot(5,1,1);
Nraw = min(100, length(raw));
scatter(1:Nraw, raw(1:Nraw), 18, [1 0.5 0], 'filled');  % orange dots
title('Raw Data Collected By the ADC (First 100 Samples)');
xlabel('Sample Index'); ylabel('ADC Counts');
grid on;


%% ---- Subplot 2: Raw IR + RED -----------------------------------
subplot(5,1,2);
plot(t, IR_raw,  'b', 'LineWidth', 1.2); hold on;
plot(t, RED_raw, 'r', 'LineWidth', 1.2);
title('Raw IR & RED After Split');
xlabel('Time (s)'); ylabel('ADC');
legend('IR','RED'); grid on;

%% ---- Subplot 3: Cleaned IR + RED -------------------------------
subplot(5,1,3);
plot(t, IR_clean,  'b', 'LineWidth', 1.2); hold on;
plot(t, RED_clean, 'r', 'LineWidth', 1.2);
title('Noise Reduction Lowpass Filtered (0–40 Hz)');
xlabel('Time (s)'); ylabel('ADC');
legend('IR','RED'); grid on;

%% ---- Subplot 4: Bandpass IR + Peaks ----------------------------
subplot(5,1,4);
plot(t, IR_bp, 'k', 'LineWidth', 1.2); hold on;
plot(t(locs), pks, 'rx', 'MarkerFaceColor', 'r', 'LineWidth', 3);
title('Bandpass IR (1–20 Hz) with Detected Peaks');
xlabel('Time (s)'); ylabel('Amplitude');
legend('Filtered IR','Peaks'); grid on;




%% ---- Subplot 5: Heart Rate and SpO2 Over Time ---------------------------
subplot(5,1,5);

if exist('HR_series','var') && ~isempty(HR_series)
    ts_HR = t(locs(2:end));

    %% --- Left axis: Heart Rate ---
    yyaxis left
    h1 = plot(ts_HR, HR_series, '-o', 'Color', 'm', 'LineWidth', 2);
    ylabel('Heart Rate (BPM)', 'Color','k');

    % Add padding to HR axis
    yL = ylim;
    ylim([yL(1)-5, yL(2)+5]);   % adjust ±5 as needed

    %% --- Right axis: SpO2 ---
    yyaxis right
    h2 = plot(ts_HR, SpO2_series, '-^', 'Color', 'g', 'LineWidth', 2);
    ylabel('SpO₂ (%)', 'Color','k');

    % Add padding to SpO2 axis
    yR = ylim;
    ylim([yR(1)-2, yR(2)+2]);   % ±2 is typical for SpO2

    % Legend
    legend([h1 h2], {'Heart Rate','SpO₂'}, 'Location', 'best');
end

title(sprintf('Heart Rate & SpO₂ Over Time   |   Last HR = %.1f bpm, Last SpO₂ = %.1f%%', ...
               HR, SpO2_series(end)));
xlabel('Time (s)');
grid on;
