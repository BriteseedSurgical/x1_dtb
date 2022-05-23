function out = unpack_udp_packet(bytes,config)
%UNPACK_UDP_PACKET Summary of this function goes here
%   Detailed explanation goes here
format = config.format;
names = config.names;
indx = 1;
out = [];
if length(bytes) ~= config.size
    return
end

for i = 1:length(format)
    chr = format(i);
    switch chr
        case 'f'    %float (4 bytes)
            out.(names{i}) = typecast(uint8(bytes(indx:indx+3)), 'single');
            indx = indx + 4;
        case 'i'    %int (4 bytes)
            out.(names{i}) = typecast(uint8(bytes(indx:indx+3)), 'int32');
            indx = indx + 4;
        case 'h'    %short (2 bytes)
            out.(names{i}) = typecast(uint8(bytes(indx:indx+1)), 'int16');
            indx = indx + 2;
        case 'H'    %unsigned short (2 bytes)
            out.(names{i}) = typecast(uint8(bytes(indx:indx+1)), 'uint16');
            indx = indx + 2;
        case 'I'    %unsigned int (4 bytes)
            out.(names{i}) = typecast(uint8(bytes(indx:indx+3)), 'uint32');
            indx = indx + 4;
        case 'd'    %double (8 bytes)
            out.(names{i}) = typecast(uint8(bytes(indx:indx+7)), 'double');
            indx = indx + 8;
    end
end
end

