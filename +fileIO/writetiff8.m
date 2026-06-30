function writetiff8(image, fname, normalize)

% write an image (or volume) as a 8bit tif 
% map 0-1 in original image to 0-255, with and without normalization
% Kenichi Ohki

if nargin < 3
    normalize=0;
end

image=double(image);
if normalize==1
    image=image./max(image(:));
end

warning off
writetiff(uint8(floor(image*255)), fname);
warning on