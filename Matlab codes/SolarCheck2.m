clc
clear all
close all

A = imread('20250907011742Lh.jpg');

% Cover timestamp (bottom left)
A(490:512, 1:150, :) = 0;

% Cover NSF + NOAA logos (bottom right)
A(458:512, 412:512, :) = 0;

% Cover top-left "NSO/GONG H-alpha"
A(1:25, 1:139, :) = 0;

% Cover top-right "Learmonth (AUS)"
A(1:35, 360:512, :) = 0;

img = imresize(A,[256 256]);
img = im2gray(img);
img_gray = im2double(img);

% Step 1: CLAHE for local contrast
img_eq = adapthisteq(img_gray,'ClipLimit',0.02,'NumTiles',[8 8]);

% Step 2: Adaptive threshold
T = graythresh(img_eq);   % try 0.4–0.7
bw = imbinarize(img_eq, 0.28);

% Step 3: Morphological cleaning
bw_clean = imclose(bw, strel('disk',3));
bw_clean = imopen(bw_clean, strel('disk',2));

% Step 4: Edge detection on cleaned binary mask
edges = edge(bw,'sobel');

% Show results
figure;
subplot(2,2,1); imshow(img_gray); title('Original');
subplot(2,2,2); imshow(img_eq); title('CLAHE Enhanced');
subplot(2,2,3); imshow(bw); title('Adaptive Threshold + Morphology');
subplot(2,2,4); imshow(edges); title('Edges after Binary Mask');

impixelinfo

%imwrite(img_gray,"cleaned1.png",'png', 'Background',0);


