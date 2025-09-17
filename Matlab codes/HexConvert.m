img = imread('cleaned1.png');         % grayscale
img = imresize(img,[256 256]);
img = uint8(img);
fid = fopen('image.hex','w');
fprintf(fid, '%02X\n', img(:));
fclose(fid);