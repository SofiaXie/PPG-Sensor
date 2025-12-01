function WDscope_v01(ComPort)
% WDscope_v01(ComPort)
%EMG
% Inputs:
%   ComPort: (Optional) String USB serial port identifier, e.g., "COM1".
%            To find your Arduino port, plug in the Nano to the USB,
%            then use MATLAB: >> serialportlist('available').
%
% Online real-time monitoring and data logging on a PC of ADC data
%   streamed from one Arduino Nano 33 BLE (Sense) Rev. 2 to the PC,
%   over the PCs USB. To avoid errors due to slow logging to a hard
%   drive/cloud drive, logged data must be finite in duration as they
%   are streamed to RAM, then sampling is interrupted while data are
%   stored.f
% Currently supports a maximum of four Nano ADC channels.

%%%%% Items most commonly changed by users.
if nargin==0, ComPort = 'COM3'; end % Change to your own default.
BaudRate = 115200;
ChanVisible = logical([1 0 0 1]); % Default which channels are 1=visible.
SaveTime    =  7; % Initial time (s) when using SAVE. Approximately
                  %  realized, since we actually save packets.
ScreenTime  =  5; % Initial buffered data screen duration (s).
%%%%% Items changed likely only to modify the software.
ChanColor = [0 0 1; 1 0 0; 1 0 1; 0 1 0]; % Channel line colors (b,r,m,g).
ScreenDecim = 10; % Update display every ScreenDecim packets.

%%%%%%%%%%%%%%%%%%%%%% START: One-Time Setup %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Set up serial port, plot display and GUI.
% Open the indicated serial communications port (USB).
USB = serialport(ComPort, BaudRate); % If fail, MATLAB errors.
flush(USB); % Flush any old data in the serial port buffer.
WLpkt1 = WDread1USBpkt(USB); % Read 1 packet. Use: chans, Fsamp, length(data).
D_Chans = WLpkt1.chans + 1; % Number of channels -> MUST NOT CHANGE.
% Open & label figure window.
f_GUI = figure('Name', 'Wireless Devices (WD) Nano Serial Port Real-Time Plotter/Logger', ...
  'Units', 'normalized', 'Position', [0.2 0.2 0.8 0.7], ...
  'CloseRequestFcn', @Callback_close_fig);
CloseScope = 0;  % Default = Do not close scope.
function Callback_close_fig(~, ~) % For close "x" in window top right.
  CloseScope = 1;  % Close the scope AFTER next packet. Do not interrupt SAVE.
  ReStart = 1;  % Restart scope display.
end
subplot('Position', [0.06 0.087 0.93 0.7]); % [left bottom width height]
% GUI: Y-axis scale: ADC counts vs. Volts.
p01 = uipanel(f_GUI, 'Title', 'Y-Axis Scale', 'FontWeight', 'bold', ...
  'Position', [0.01 0.8, 0.1, 0.08]);
c01 = uicontrol(p01, 'Style', 'popupmenu', 'Callback', @Callback_c01, ...
  'String', {'ADC Counts', 'Volts'}, 'Value', 1, 'FontWeight', 'bold', ...
  'Units', 'normalized', 'Position', [0.1 0.1 0.9 0.9]);
function Callback_c01(~, ~) % Nested callback: Y-axis scale.
  ReStart = 1;  % Restart scope display.
end
% GUI: Save data controls.
%   Overall panel.
p02 = uipanel(f_GUI, 'Title', 'Save Raw Data (seconds)', ...
  'FontWeight', 'bold', 'Position', [0.01 0.9, 0.3, 0.1]);
%   Number of seconds to record.
c02a = uicontrol(p02, 'Style', 'edit', 'Callback', @Callback_c02a, ...
  'String', int2str(SaveTime), 'FontWeight', 'bold', ...
  'Units', 'normalized', 'Position', [0.1 0.05 0.3 0.4]);
function Callback_c02a(~, ~) % Nested callback, save data duration.
  ReStart = 1;  % Restart scope display.
end
%   START/Recording button.
c02b = uicontrol(p02, 'Style', 'togglebutton', 'Callback', @Callback_c02b, ...
  'String', 'START', 'FontWeight', 'bold', 'Units', 'normalized', ...
  'Position', [0.6 0.05 0.3 0.8]);
SaveFlag = -1; % Save flag: -1=>Not saving, 0=>Start, >0=>In process.
function Callback_c02b(~, ~) % Nested callback, save data start.
  c02b.BackgroundColor = [1 0 0]; % In use red "START" color.
  c02b.String = 'Recording ...'; % Indicate recording in progress.
  SaveFlag = 0; % 0=>Start saving.
end
%   Output file selection (.mat file vs. .stream file).
c02c = uicontrol(p02, 'Style', 'popupmenu', 'Callback', @Callback_c02c, ...
  'String', {'.mat File', 'Stream'}, 'Value', 1, 'FontWeight', 'bold', ...
  'Units', 'normalized', 'Position', [0.1 0.5 0.3 0.4]);
function Callback_c02c(~, ~) % Nested callback: Y-axis scale.
  ReStart = 1;  % Restart scope display.
end
% GUI: Channel display ON/OFF buttons.
Left = [0.05 0.30 0.55 0.80]; % Left edge of successive buttons.
p03 = uipanel(f_GUI, 'Title', 'Channel Display ON/OFF (White --> OFF)', ...
  'FontWeight', 'bold', 'Position', [0.65 0.9, 0.3, 0.1]);
for m = D_Chans:-1:1 % Set up each channel button. Each calls-back to same function.
  c03(m) = uicontrol(p03, 'Style', 'togglebutton', 'Callback', @Callback_c03, ...
    'String', int2str(m), 'FontWeight', 'bold', 'Units', 'normalized', ...
    'BackgroundColor', [1 1 1], 'Position', [Left(m) 0.05 0.2 0.6]);
end
function Callback_c03(src, ~)
  c = str2double(src.String); % Get channel that initiated this callback.
  ChanVisible(c) = ~ChanVisible(c); % Switch its visible flag.
  ReStart = 1;  % Restart scope display.
end

drawnow; pause(0.25); % Give 250ms for initial drawing.
%%%%%%%%%%%%%%%%%%%%%%%% END: One-Time Setup %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%% START: Main Loop %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
while CloseScope==0
  % ---------- Setup each re-start due to screen command/SAVE. %%%%%%%%%%%%
  % Resets.
  Screen_n = 0;    % Reset display update decimation index counter.
  Data_n = 0; % Reset end index into Data of last data sample. 0 => wrap.
  % Tasks that depend on the first packet (1st packet discarded).
  Data = zeros(D_Chans, round(WLpkt1.Fsamp*ScreenTime)); % Screen data buffer.
  Data_NN = round(WLpkt1.Fsamp*ScreenTime); % Current # samples displayed.
  t = ( 0:(Data_NN-1) ) / WLpkt1.Fsamp;
  WLpkt_NN = round(WLpkt1.Fsamp*str2double(c02a.String) / length(WLpkt1.data)); % # save packets.
  for m=WLpkt_NN: -1 : 1 % Pre-allocate WLpkt().
    WLpkt(m) = struct('sync', 0, 'bcnt', 0, 'ver', 0, 'Fsamp', 0, ...
      'chans', 0, 'type', 0, 'ts_a', 0, 'ts_c', 0', 'ts_p', 0, 'crc', 0, ...
      'chan1', 0, 'Dlen', 0, 'data', ...
      zeros(WLpkt1.chans+1, length(WLpkt1.data)), 'text', 'x');
  end
  plot(t, zeros(D_Chans,length(t)), '.'); %colororder(ChanColor);
  box('off'), xlim([0 ScreenTime]); % Establish plot window.
  Yscale = 1; ylim([0 4095]); % Guess that scale is ADC Counts, else fix below.
  if c01.Value==2, Yscale = 3.3/4095; ylim([0 3.3]); end % If Volts.
  ylabel(c01.String(c01.Value), 'FontWeight', 'bold')
  xlabel('Time (s)', 'FontWeight', 'bold')
  f_handle = get(gca, 'Children'); % Handle to line object.
  % GUI updates or setup.
  %   c02 is the START/Recording button.
  c02b.String = 'START';
  c02b.BackgroundColor = [0 1 0]; % Default green "START" color.
  %   c03() are the channel visibility buttons.
  for m = 1:D_Chans
    f_handle(m).Color = ChanColor(m,:); % Not GUI, but sets line colors.
    if ChanVisible(m)
      c03(m).BackgroundColor = ChanColor(m,:); % Assigned button color.
      f_handle(m).Visible = 'on'; % Plot IS visble.
    else
      c03(m).BackgroundColor = [1 1 1]; % White button.
      f_handle(m).Visible = 'off'; % Plot NOT visible.
    end
  end

  % For now, fix: ver=256, Fsample=2000, type=1 or 255, chan1=0.

  %------------ Loop & display packets until a command is issued. %%%%%%%%%
  ReStart = 0; % Assume one restart at a time.
  WLpkt_n = 1; % Reset index into WLpkt packet structure vector.
  flush(USB); % Catch up, in case (re-)initializing is slow.
  while (SaveFlag>=0) || (ReStart==0) % While no comands or saving.
    % Read next packet.
    WLpkt(WLpkt_n) = WDread1USBpkt(USB); % Read next packet.
    %%%%%%%%%% Special Processing If Text Message (Hack!!) %%%%%%%%%%
    if WLpkt(WLpkt_n).type == 255  % Display message to Command Window.
      disp(WLpkt(WLpkt_n).text(1:WLpkt(WLpkt_n).ts_a));
      ReStart = 1;  % Restart scope display.
      continue; % Go to next iteration of this while() loop (Hack!!).
    end
    %%%%%%%%%% NOT a text message, so regular data processing. %%%%%%%%%%
    % Update .data. Assume ver, Fsample, chans, type, chan1 not change.
    Samples = size(WLpkt(WLpkt_n).data, 2); % Samples per channel.
    if Data_n + Samples <= Data_NN % New data packet fits on screen (no wrap).
      Data(:, Data_n+1:Data_n+Samples) = WLpkt(WLpkt_n).data*Yscale; % Save.
      Data_n = Data_n + Samples; if Data_n==Data_NN, Data_n=0; end % Update.
    else % New data packet wraps around displayed portion of screen.
      I1 = Data_NN-Data_n; % Remaining samples in Data.
      Data(:, Data_n+1:Data_NN) = WLpkt(WLpkt_n).data(:, 1:I1)*Yscale;
      I2 = Samples - I1; % Number of additional samples to wrap.
      Data(:, 1:I2) = WLpkt(WLpkt_n).data(:, I1+1:end)*Yscale;
      Data_n = I2 - 1; % Update index.
    end
    Screen_n = mod(Screen_n+1, ScreenDecim);
    if Screen_n==0  % Update plot this pass.
      for m = 1:D_Chans, f_handle(m).YData = Data(m, 1:Data_NN); end
      drawnow;
    end
    WLpkt_n = WLpkt_n+1; if WLpkt_n==WLpkt_NN+1, WLpkt_n=1; end % For next pass.

    % ---------- SAVE processing (only when SAVE is occuring). %%%%%%%%%%%%
    % Count packets. When ready: halt, write to disk.
    if SaveFlag >= 0
      SaveFlag = SaveFlag + 1; % Increment number of packets since SAVE command.
      if SaveFlag == WLpkt_NN % Ready to store to disk?
        c02b.String = 'Saving to disk...';
        c02b.BackgroundColor = [1 1 0]; % Yellow "Saving to disk..." color.
        % Unwrap packets to save. First packet index is WLpkt_n.
        WLpkt = [WLpkt(WLpkt_n:WLpkt_NN) WLpkt(1:(WLpkt_n-1))];
        % Get filename, without extension.
        Fname = input('Filename (no extension)? ', 's'); % Get file name.
        while exist([Fname '.mat'], 'file') || exist([Fname '.stream'], 'file')
          beep;  disp('Cannot overwrite existing file.')
          Fname = input('Filename (no extension)? ', 's'); % Try again.
        end
        % Now, write to a .mat or .serial file, as selected.
        if c02c.Value == 1  % Write to .mat file.
          save(Fname, 'WLpkt');
        else  % Write as serial stream.
          WDwriteDiskPkts(Fname, WLpkt); % Save stream to disk.
        end
        c02b.String = 'START';
        c02b.BackgroundColor = [0 1 0]; % Default green "START" color.
        SaveFlag = -1; ReStart = 1;  % Restart scope display.
      end % if SaveFlag == WLpkt_NN.
    end % if SaveFlag >= 0.

  end % while (SaveFlag>=0) || (ReStart==0) % While no commands or saving.

end % While start/restart.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%% END: Main Loop %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Figure close has been signaled. Loops exited. Clean-up and exit.
delete(f_GUI); clear f_GUI; % Delete & clear figure window.
delete(USB);   clear USB;   % Delete & clear USB port.

end % Main function.
