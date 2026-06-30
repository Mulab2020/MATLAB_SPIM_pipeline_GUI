function array = ijplus2array(imp,newtype)
%IJPLUS2ARRAY Converts ImageJ ImagePlus object to MATLAB array
% array = ijplus2array(imp,newtype)
%
% by Vincent Bonin based on original code by Aaron Kerlin,

% changelog
% 01/25/08 vb corrects automatic unsigned integer cast
%          vb optimized speed and memory usage
%          vb allow bit depth conversion

% first convert to user-specified bit depth

% dummy object to disable automatic scaling in StackConverter
dummy = ij.process.ImageConverter(imp);
dummy.setDoScaling(0); % this is a static property

if nargin > 1
    converter = ij.process.StackConverter(imp); % may not work for single images
    switch newtype
        case 'uint8'
            converter.convertToGray8;
        case 'uint16'
            converter.convertToGray16;        
        case 'single'
            converter.convertToGray32;        
        otherwise
            error('type not supported by imagej');
    end
end

% figure out 
switch imp.getBitDepth
    case 8
        arraytype = 'int8';
        srctype = 'uint8';
    case 16
        arraytype = 'int16';
        srctype = 'uint16';
    case 32
        arraytype = 'single';
        srctype = 'single';
    otherwise
        error('unknown ij image type');
end

stack=imp.getImageStack();
nslices=stack.getSize();
width=stack.getWidth();
height=stack.getHeight();

%pixelarray = stack.getImageArray();
%cellarray=cell(pixelarray); % converts java array into MATLAB cell array
%array=cell2mat(cellarray(1:nslices)); 

pixelarray = stack.getImageArray();
array = zeros(width,height,nslices,srctype); % temporary type
for islice = 1:nslices
    % because java has not signed types, matlab casts unsigned ij integers to signed
    array(:,:,islice)=reshape(typecast(pixelarray(islice),srctype),width,height);
end

array=permute(array,[2 1 3]);
      
return;
