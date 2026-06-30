%% test stack reader

volFolder    = 'Y:\SPIM\07262013\imFish1-5';
doRefStack   = 0;
timeRange    = 0 : 10;%limits.data(1);
slices       = 1 : 41;%limits.data(2) + 1; 
poolWorkers  = 12;
masterClock = tic;

%%mkdir(regFolder);

xSize = 2048;
ySize = 2048;
zSize = numel(slices);
tSize = numel(timeRange);
%% create time-averaged reference stack, over all time points
referenceStack = zeros(xSize, ySize, zSize, 'uint16');
referenceStack2 = zeros(xSize, ySize, zSize, 'uint16');
refTimePoint = 1;
%refStackName = [volFolder,'\TM',num2str(refTimePoint, '%.5d'),'\TM',num2str(refTimePoint, '%.5d'),'_CM0_CHN00.stack' ];
refStackName = 'Y:\SPIM\08092013\08092013\Fish1-2\TM00005_CM0_CHN00.stack';
tic;


 referenceStack = read_LSstack_fast1(refStackName,[ySize,xSize]);
 toc;

tic;
for z = 1:zSize
    referenceStack(:,:,z) = uint16(multibandread(refStackName,[xSize ySize zSize],...
                            'uint16',0,'bsq','ieee-le',...
                            {'Band','Direct',z},...
                            {'Column','Range',[1, 1, xSize]},...
                            {'Row','Range',[1, 1, ySize]}));
end
toc


