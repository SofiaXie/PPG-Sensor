clear; close all;

%% Load raw PPG data
load('test13.mat');
WDcatWLpktData(WLpkt);
raw = ans;
ir_data  = raw(1, 1:2:end);   % IR
red_data = raw(1, 2:2:end);   % Red
fs = 150;

% Process PPG offline
processPPGOffline(red_data, ir_data, fs);

% -------------------------------
function processPPGOffline(red, ir, fs)
    if nargin < 3, fs = 150; end
    red = red(:); ir = ir(:);

    % 1. Bandpass filter (0.5–4 Hz)
    [b,a] = butter(3, [0.5 4]/(fs/2));
    red_f = filtfilt(b,a,red);
    ir_f  = filtfilt(b,a,ir);

    % 2. Peak detection
    [peaks, locs] = detectPeaksAdaptive(ir_f, fs);
    if isempty(locs), error('No peaks detected'); end

    % 3. Heart Rate
    RR = diff(locs)/fs;
    HR = 60 ./ RR;
    fprintf('Estimated HR: %.1f bpm\n', mean(HR));

    % 4. SpO2 estimate (entire signal)
    AC_red = max(red_f) - min(red_f);
    AC_ir  = max(ir_f)  - min(ir_f);
    DC_red = mean(red_f);
    DC_ir  = mean(ir_f);

    R = (AC_red/DC_red) / (AC_ir/DC_ir);
    SpO2 = 110 - 28*R; % default coefficients
    fprintf('Estimated SpO2: %.1f%%\n', SpO2);

    % 5. Plot
    figure;
    subplot(2,1,1);
    plot(ir_f,'b'); hold on;
    plot(locs, peaks,'ko','MarkerSize',6);
    legend('IR','Peaks'); title(sprintf('HR = %.1f bpm', mean(HR)));
    xlabel('Sample'); ylabel('Amplitude');

    subplot(2,1,2);
    plot(red_f,'r'); title(sprintf('SpO2 = %.1f%%', SpO2));
    xlabel('Sample'); ylabel('Amplitude');
end

%% -------------------------------
function [peak_vals, peak_locs] = detectPeaksAdaptive(y, fs)
    % Simple peak detection for PPG using findpeaks
    % y  : input PPG signal
    % fs : sampling frequency (Hz)

    y = y(:); % ensure column vector

    % Minimum distance between peaks (in samples) based on max HR ~200 bpm
    minDist = round(0.3 * fs);  % 0.3 sec minimum RR

    % Use findpeaks with minimum peak height and minimum distance
    [peak_vals, peak_locs] = findpeaks(y, 'MinPeakDistance', minDist);

    % Optional: remove peaks that are too small
    if ~isempty(peak_vals)
        threshold = 0.1 * (max(y) - min(y)); % 10% of signal range
        keep = peak_vals > threshold;
        peak_vals = peak_vals(keep);
        peak_locs = peak_locs(keep);
    end
end
