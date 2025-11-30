function RealTime_PPG_GUI(ComPort)

if nargin==0
    ComPort = "COM5";
end
BaudRate = 115200;

% --- Open Serial Port ---
USB = serialport(ComPort, BaudRate);
flush(USB);
disp("Connected. Reading interleaved IR/RED (IR=odd, RED=even)...");

%% ====== Parameters ======
fs = 300;       % Arduino sample rate
winSec = 5;      % seconds of data for display
N = fs*winSec;   % number of samples in buffer
HRbufLen = 100;    % moving average length for HR
IRbuf  = zeros(1,N);
REDbuf = zeros(1,N);
idx = 1;

% Filters
[b,a] = butter(4, 40/(fs/2), 'low');
[bHP,aHP] = butter(4, 0.8/(fs/2), 'high');
[bLP,aLP] = butter(4, 3/(fs/2), 'low');


HRbuf = zeros(1, HRbufLen);
HRidx = 1;

% ===== GUI Setup =====
f = figure('Name','Real-Time PPG','NumberTitle','off',...
    'Position',[200 200 800 400]);

ax = subplot(2,1,1);
hIR  = plot(ax, zeros(1,N), 'b'); hold on;
hRED = plot(ax, zeros(1,N), 'r');
xlabel('Samples'); ylabel('ADC'); title('RAW ADC DATA');
ylim([0 4095]);
legend('IR LED','RED LED');


%% ===== Real-Time Display with Fixed Spacing =====

% Figure background
set(gcf,'Color','k');

% Graph setup
ax = subplot(2,1,1);
hIR  = plot(ax, zeros(1,1000), 'b'); hold on;
hRED = plot(ax, zeros(1,1000), 'r');
set(ax,'Color','k','XColor','w','YColor','w'); % black bg, white axes
grid(ax,'on');
xlabel(ax,'Samples','Color','w');
ylabel(ax,'ADC Counts','Color','w');
title(ax,'IR (Blue) / RED (Red)','Color','w');
legend(ax,{'IR','RED'},'TextColor','k','Location','northeast'); % legend text black

%
dispPanel = uipanel('Title','PGG Outputs','FontSize',14,'FontWeight','bold',...
    'Position',[0.1 0.15 0.8 0.25], 'BackgroundColor',[0 0 0], 'ForegroundColor','w');

% Pulse Rate Label
uicontrol('Parent', dispPanel, 'Style','text', 'Units','normalized', ...
    'Position',[0.05 0.55 0.4 0.35], 'String','Pulse Rate (bpm)', ...
    'FontSize',14, 'FontWeight','bold', 'BackgroundColor',[0 0 0], 'ForegroundColor','w');

% Pulse Rate Value
hHR = uicontrol('Parent', dispPanel, 'Style','text', 'Units','normalized', ...
    'Position',[0.05 0.05 0.4 0.45], 'String','0', ...
    'FontSize',32, 'FontWeight','bold', 'ForegroundColor',[0 1 0], 'BackgroundColor',[0 0 0]);

% SpO2 Label
uicontrol('Parent', dispPanel, 'Style','text', 'Units','normalized', ...
    'Position',[0.55 0.55 0.4 0.35], 'String','SpO2 (%)', ...
    'FontSize',14, 'FontWeight','bold', 'BackgroundColor',[0 0 0], 'ForegroundColor','w');

% SpO2 Value
hSpO2 = uicontrol('Parent', dispPanel, 'Style','text', 'Units','normalized', ...
    'Position',[0.55 0.05 0.4 0.45], 'String','0', ...
    'FontSize',32, 'FontWeight','bold', 'ForegroundColor',[0 0.8 1], 'BackgroundColor',[0 0 0]);

%% ===== Main Loop =====
persistent lastUpdateTime
if isempty(lastUpdateTime)
    lastUpdateTime = tic;
end

while ishandle(f)

    pkt = WDread1USBpkt(USB);

    if pkt.type == 255
        disp(pkt.text(1:pkt.ts_a));
        continue;
    end

    raw = double(pkt.data(:)'); % flatten
    if isempty(raw), continue; end

    % Split interleaved IR/RED
    IR  = raw(1:2:end);
    RED = raw(2:2:end);
    ns  = length(IR);

    % Circular buffer
    if idx+ns-1 <= N
        IRbuf(idx:idx+ns-1) = IR;
        REDbuf(idx:idx+ns-1) = RED;
        idx = idx + ns;
    else
        r = N-idx+1;
        IRbuf(idx:end) = IR(1:r);
        IRbuf(1:ns-r) = IR(r+1:end);

        REDbuf(idx:end) = RED(1:r);
        REDbuf(1:ns-r) = RED(r+1:end);

        idx = ns-r+1;
    end

    % Filter IR
    IRclean = filtfilt(b,a,IRbuf);
    REDclean = filtfilt(b,a,REDbuf);
    IRf = filtfilt(bHP,aHP,IRbuf);
    IRf = filtfilt(bLP,aLP,IRf);

    % Heart rate
    minDist = round(0.35*fs);
    [pks, locs] = findpeaks(IRf,'MinPeakDistance',minDist,'MinPeakProminence',25);
    if numel(locs)>=2
        ibi = diff(locs)/fs;
        HR = 60/ibi(end);
    else
        HR = NaN;
    end

    % Moving average HR
    HRbuf(HRidx) = HR;
    HRidx = mod(HRidx, HRbufLen) + 1;
    HRavg = mean2(HRbuf);

    % SpO2
    AC_IR  = max(IRclean)-min(IRclean);
    DC_IR  = mean(IRclean);
    AC_RED = max(REDclean)-min(REDclean);
    DC_RED = mean(REDclean);
    R = (AC_RED/DC_RED)/(AC_IR/DC_IR);
    SpO2 = min((130 - 22*R),100);

    % Update plots (always)
    set(hIR,'YData',IRbuf);
    set(hRED,'YData',REDbuf);

    % Update text at most once per second
    if toc(lastUpdateTime) >= 1
        set(hHR,'String',sprintf('%.1f',HRavg));
        set(hSpO2,'String',sprintf('%.1f',SpO2));
        lastUpdateTime = tic;
    end

    drawnow limitrate

end
