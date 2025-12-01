function Data = WDcatWLpktData(WLpkt)
% Data = WDcatWLpktData(WLpkt)
%
% Simple sequential extraction-concatenation of data from packet
% vector WLpkt into output matrix Data(c,s), where c is the number
% of channels and s is the number of samples.
% INPUTS:
%  WLpkt(): MATLAB WLpkt structure vector containing each packet.
% OUTPUTS:
%  Data(c,s): Concatenated data matrix, where c is the number
%    of channels and s is the number of samples.

% Compute total number of data samples. Assumes each packet not
%  necessarily has the same number of samples, but DOES have the same
%  number of channels.
Chans = WLpkt(1).chans + 1; % Number of channels per packet.
Samples = 0;
for m = 1:length(WLpkt)
  Samples = Samples + size(WLpkt(m).data, 2);
end

% Now, copy those samples to matrix Data(chan, samp).
Data = zeros(Chans, Samples); % Pre-allocate.
I = 1; % Initialize sample count index.
for m = 1:length(WLpkt) % Loop over all packets.
  Data( :, I : (I+length(WLpkt(m).data)-1) ) = WLpkt(m).data; % Copy.
  I = I + length(WLpkt(m).data); % Increment index.
end

end
