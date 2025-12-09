function RealTimeCode_Final(ComPort)

% ---------- PARAMETERS ----------
if nargin==0
    ComPort = "COM5";
end

BaudRate = 115200;
fs = 300;                 % sampling rate
winSec = 10;              % display window
N = (fs * winSec)/2;      % buffer size

HRbufLen   = 100;         %Number of samples for average
SpO2bufLen = 300;         %Number of samples for average

%Buffers
IRbuf  = zeros(1,N);
REDbuf = zeros(1,N);
idx    = 1;

HRbuf   = nan(1,HRbufLen);
HRidx   = 1;

SpO2buf = nan(1,SpO2bufLen);
SpO2idx = 1;

%defual display mode
showMode = "both";

%Used for pulse peak hysteresis
persistent lastHR
if isempty(lastHR), lastHR = NaN; end

%Filters
[b,a]     = butter(3, 10/(fs/2), 'low');
[bHP,aHP] = butter(3, 1/(fs/2),  'high');

% Serial Port Setup
USB = serialport(ComPort, BaudRate);
flush(USB);
disp("Connected. Reading interleaved IR/RED...");

% Converts to seconds from samples
tAxis = ((0:N-1) / 150);

%GUI Setup
f = figure('Name','Real-Time PPG','NumberTitle','off',...
    'Position',[200 200 850 450],'Color','k');

ax = subplot(2,1,1);
set(ax,'Color','k','XColor','w','YColor','w');
hold on; grid on;

hIR    = plot(ax, tAxis, zeros(1,N), 'b', 'LineWidth', 2);
hRED   = plot(ax, tAxis, zeros(1,N), 'r', 'LineWidth', 2);
hPeaks = plot(ax, NaN, NaN, 'wx', 'LineWidth', 2);

title(ax,'IR (Blue) / RED (Red)','Color','w');
xlabel(ax,'Time (s)','Color','w');
ylabel(ax,'ADC Counts','Color','w');

legend(ax,{'IR','RED'},'TextColor','k','Location','northeast');

%Pannel Setup
dispPanel = uipanel('Title','PPG Outputs','FontSize',14,'FontWeight','bold',...
    'Position',[0.1 0.15 0.8 0.25],...
    'BackgroundColor','k','ForegroundColor','w');

uicontrol('Parent',dispPanel,'Style','text','Units','normalized',...
    'Position',[0.05 0.55 0.4 0.35],'String','Pulse Rate (bpm)',...
    'FontSize',14,'FontWeight','bold','BackgroundColor','k','ForegroundColor','w');

hHR = uicontrol('Parent',dispPanel,'Style','text','Units','normalized',...
    'Position',[0.05 0.05 0.4 0.45],'String','0',...
    'FontSize',32,'FontWeight','bold','ForegroundColor',[0 1 0],'BackgroundColor','k');

uicontrol('Parent',dispPanel,'Style','text','Units','normalized',...
    'Position',[0.55 0.55 0.4 0.35],'String','SpO2 (%)',...
    'FontSize',14,'FontWeight','bold','BackgroundColor','k','ForegroundColor','w');

hSpO2 = uicontrol('Parent',dispPanel,'Style','text','Units','normalized',...
    'Position',[0.55 0.05 0.4 0.45],'String','0',...
    'FontSize',32,'FontWeight','bold','ForegroundColor',[0 0.8 1],'BackgroundColor','k');

uicontrol('Style','pushbutton','String','Toggle IR/RED',...
    'Units','normalized','Position',[0.42 0.42 0.18 0.06],...
    'FontSize',12,'BackgroundColor',[0.1 0.1 0.1],'ForegroundColor','w',...
    'Callback',@toggleMode);

% Main Loop
    
    %Used to slowdown how fast things update on the display 
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

    raw = double(pkt.data(:)');
    if isempty(raw), continue; end

    % Split IR/RED
    IR  = raw(1:2:end);
    RED = raw(2:2:end);
    ns = length(IR);

    % Circular buffer
    if idx + ns - 1 <= N
        IRbuf(idx:idx+ns-1) = IR;
        REDbuf(idx:idx+ns-1) = RED;
        idx = idx + ns;
    else
        r = N - idx + 1;
        IRbuf(idx:end) = IR(1:r);
        IRbuf(1:ns-r) = IR(r+1:end);

        REDbuf(idx:end) = RED(1:r);
        REDbuf(1:ns-r) = RED(r+1:end);

        idx = ns-r+1;
    end

    % Filter Data 
    IRclean  = filtfilt(b,a,IRbuf);
    REDclean = filtfilt(b,a,REDbuf);

    IRf = filtfilt(bHP,aHP,IRbuf);

    %Find Peaks and caluclate pulse rate 
    % around 220 BPM (0.1 * fs) = 30 samples before next peak using 150 samples for ir
    % per second to get 4Hz or 240 BPM
    minDist = round(0.2 * fs); 
    [pks, locs] = findpeaks(IRf,'MinPeakDistance',minDist,'MinPeakProminence',25);

    if numel(locs) >= 2
        ibi = diff(locs) / fs;
        HR = 30 / ibi(end);

        %hysteresis
        if ~isnan(lastHR)
            delta = HR - lastHR;
            maxChange = 25;
            if abs(delta) > maxChange
                HR = lastHR + sign(delta)*maxChange;
            end
        end

        lastHR = HR;
    end

    % Pulse Rate average
    HRbuf(HRidx) = lastHR;
    HRidx = mod(HRidx, HRbufLen) + 1;
    HRavg = mean(HRbuf,'omitnan');

    %SP02
    AC_IR  = rms(IR);
    DC_IR  = mean(IRclean);

    AC_RED = rms(RED);
    DC_RED = mean(REDclean);

    R = (AC_RED/DC_RED) / (AC_IR/DC_IR);
    SpO2 = min(max(125 - 21*R, 70), 100);

    SpO2buf(SpO2idx) = SpO2;
    SpO2idx = mod(SpO2idx, SpO2bufLen) + 1;
    SpO2avg = mean(SpO2buf,'omitnan');

    %Differnt Display windows ( IR/RED, IR, RED )
    switch showMode
        case "ir"
            set(hIR,'Visible','on','YData',IRclean);
            set(hRED,'Visible','off');
            set(hPeaks,'Visible','on');

        case "red"
            set(hIR,'Visible','off');
            set(hRED,'Visible','on','YData',REDclean);
            set(hPeaks,'Visible','off');

        otherwise
            set(hIR,'Visible','on','YData',IRclean);
            set(hRED,'Visible','on','YData',REDclean);
            set(hPeaks,'Visible','on');
    end

    % Peaks
    if ~isempty(locs)
        set(hPeaks,'XData',locs/(fs/2),'YData',IRclean(locs));
    else
        set(hPeaks,'XData',NaN,'YData',NaN);
    end

    %Update display 
    if toc(lastUpdateTime) >= 1
        set(hHR,  'String', sprintf('%.1f', HRavg));
        set(hSpO2,'String', sprintf('%.1f', SpO2avg));
        lastUpdateTime = tic;
    end

    drawnow limitrate
end

%Differnent display functions 
function toggleMode(~,~)
    switch showMode
        case "both"
            showMode = "ir";
        case "ir"
            showMode = "red";
        case "red"
            showMode = "both";
    end
    disp("Mode switched to: " + showMode);
end

end
