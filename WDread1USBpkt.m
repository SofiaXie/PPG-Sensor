function WLpkt1 = WDread1USBpkt(Sobj)
% Read bytes from an open serial stream Sobj and return first found packet in
%   a WLpkt packet structure. Leading stream data not identified by the
%   syncrhonization byte are ignored, but counted.

% INPUTS:
%  Sobj: Input stream object.
%
% OUTPUTS:
%  WLpkt: MATLAB WLpkt structure which contains one packet. The
%         structure fields are defined in the packet specification.
%         They are briefly listed here.
%   .sync:  (uint32) synchronization code uint32(0x5A0FBE66).
%   .bcnt:  NOT sent by the microcontroller. Byte count to find .sync.
%   .ver:   Version number.
%   .Fsamp: Sampling rate (Hz).
%   .chans: One LESS than the number of channels.
%   .type:  Data type.
%   .chan1: Logical channel number of first channel (starts from 0).
%   .ts_a:  Native ADC timestamp.
%   .ts_c:  Native cental timestamp.
%   .ts_p:  Native peripheral timestamp (paired with .ts_c).
%   .data:  Data matrix (channels, samples).
%   .text   NOT set by the microcontroller. Stores text message data.
%   .Dlen:  Number of total packet data bytes.

% Find the first 4-byte synchronization code.  Search byte-by-byte.
Code = uint32(0); % Should be all zeros, fail at least until 4 bytes.
WLpkt1.bcnt = 0; % Initial byte count.
while Code ~= uint32(0x5A0FBE66)  % Have we found the synch code?
  NewByte = read(Sobj, 1, 'uint8');  % Read next byte.
  WLpkt1.bcnt = WLpkt1.bcnt + 1; % Increment byte count.
  Code = bitshift(Code, 8)+uint32(NewByte); % Shift in new byte.
end                               % When exit loop, synch code found.
WLpkt1.sync = uint32(0x5A0FBE66); %  and .bcnt is number of bytes searched.

% Read remaining header (not data), storing in WLpkt.
WLpkt1.ver   = read(Sobj, 1, 'uint16'); % Version number.
WLpkt1.Fsamp = read(Sobj, 1, 'uint16'); % Sampling rate (Hz).
WLpkt1.chans = read(Sobj, 1, 'uint8' ); % Number chans - 1.
WLpkt1.type  = read(Sobj, 1, 'uint8' ); % Data type.
WLpkt1.ts_a  = read(Sobj, 1, 'uint32'); % ADC native timestamp.
WLpkt1.ts_c  = read(Sobj, 1, 'uint32'); % Central native timestamp.
WLpkt1.ts_p  = read(Sobj, 1, 'uint32'); % Peripheral native timestamp.
WLpkt1.crc   = read(Sobj, 1, 'uint16'); % CRC. Not presently used.
WLpkt1.chan1 = read(Sobj, 1, 'uint8' ); % Logical chan number.
WLpkt1.Dlen  = read(Sobj, 1, 'uint8' ); % Number of total packet data bytes.
WLpkt1.data  = [];%zeros(WLpkt1.chans+1, WLpkt1.Dlen/(WLpkt1.chans+1)); % Place-hold.
WLpkt1.text  = '';                      % Place-holder.

% Read the data based on the data type and length.
if WLpkt1.type == 255 % Special case, read ASCII message; store in .text.
  WLpkt1.text = read(Sobj, WLpkt1.Dlen, 'char'); % Returns character vector.
else  % Thus, packet contains ADC data.
  switch WLpkt1.type
    case 1, Slen = 2; Styp = 'int16';  % 2-byte 16-bit
    case 2, Slen = 4; Styp = 'float';  % 4-byte float.
    case 3, Slen = 3; Styp = 'int24';  % 3-byte 24-bit. % bit24 or ubit24??
    otherwise, error(['Bogus packet type: ' int2str(WLpkt1.type)]);
  end
  WLpkt1.data = read(Sobj, WLpkt1.Dlen/Slen, Styp);  % Multiplexed data vector.
  WLpkt1.data = reshape(WLpkt1.data, WLpkt1.chans+1, ... % Matrix dimension:
      length(WLpkt1.data)/(WLpkt1.chans+1));             %  WLpkt1.data(c,s),

  % try WLpkt1.data = reshape(WLpkt1.data, WLpkt1.chans+1, ... % Matrix dimension:
  %     length(WLpkt1.data)/(WLpkt1.chans+1));             %  WLpkt1.data(c,s),
  % catch, WLpkt1.chans+1, length(WLpkt1.data)
  % end
end                                                      %  where c=channel,
                                                         %  s=sample.
return
