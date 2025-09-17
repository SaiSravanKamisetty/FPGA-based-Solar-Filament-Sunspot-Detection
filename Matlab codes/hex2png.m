function hex2png(infile, outfile)
% hex2png Convert a hex file (65,536 bytes worth of data) to 256x256 PNG.
% Usage:
%   hex2png('input.hex','out.png')
% The function tries to detect whether infile is text (hex tokens) or raw binary.
% It expects 65536 bytes (256*256). If fewer, it pads with zeros; if more, it truncates.

if nargin < 1 || isempty(infile)
    error('Please provide input filename, e.g. hex2png(''data.hex'',''out.png'')');
end
if nargin < 2 || isempty(outfile)
    outfile = 'out.png';
end

EXPECTED_LEN = 256*256; % 65536

% Try to open as text first
fid = fopen(infile,'r');
if fid == -1
    error('Cannot open file %s', infile);
end
txt = fread(fid, inf, '*char')';
fclose(fid);

% Heuristic: if text contains non-printable bytes, treat as binary
nonprint = any(double(txt) < 9 | (double(txt) > 13 & double(txt) < 32));
if nonprint
    % Binary mode
    fid = fopen(infile,'r','ieee-be'); % endian doesn't matter for bytes
    data = fread(fid, inf, 'uint8=>uint8');
    fclose(fid);
else
    % Text mode: extract hex tokens
    % Accept tokens like 0xAA, AA, aa, A, 0Xa (single nibble also allowed)
    % We'll capture pairs of hex digits, but also allow separated single-digit tokens by padding left with 0.
    % Use regexp to find hex sequences
    tokens = regexp(txt, '(?:0x)?([0-9A-Fa-f]+)', 'tokens');
    tokens = [tokens{:}]; % flatten
    % Normalize tokens to two-digit hex bytes: if token length odd, pad with leading 0, then split into bytes if longer than 2
    hexbytes = {};
    for k = 1:numel(tokens)
        t = tokens{k};
        if isempty(t); continue; end
        if mod(length(t),2)==1
            t = ['0' t];
        end
        % split into pairs
        nPairs = length(t)/2;
        for p = 1:nPairs
            hexbytes{end+1} = t(2*p-1:2*p); %#ok<AGROW>
        end
    end
    % convert hex strings to uint8
    if isempty(hexbytes)
        error('No hex tokens found in file %s (is it the correct format?)', infile);
    end
    try
        data = uint8(hex2dec(hexbytes(:)));
    catch ME
        error('Failed to parse hex tokens: %s', ME.message);
    end
end

% Now ensure length
n = numel(data);
if n < EXPECTED_LEN
    warning('Data length is %d bytes; padding with zeros to %d bytes.', n, EXPECTED_LEN);
    data = [data; zeros(EXPECTED_LEN - n,1,'uint8')];
elseif n > EXPECTED_LEN
    warning('Data length is %d bytes; truncating to %d bytes.', n, EXPECTED_LEN);
    data = data(1:EXPECTED_LEN);
end

% reshape to 256x256. Common image ordering is row-major: reshape by rows
img = reshape(data, 256, 256)'; % transpose so that the first byte becomes pixel (1,1) in usual visual orientation

% Optionally: flip vertically if your data ordering is different
% img = flipud(img);
img_mod = flip( rot90(img, -1), 2 );
% Write PNG
imwrite(img_mod, outfile);

fprintf('Wrote %s (256x256, %d bytes read)\n', outfile, n);
end
