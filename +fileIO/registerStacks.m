volFolder    = 'Y:\Minoru\2013-09-10\Timeseries_20130910_134808';
regFolder = [volFolder '\registered'];
doRefStack   = 0;
timeRange    = 0 : 10;%limits.data(1);
slices       = 1 : 40;%limits.data(2) + 1; 
poolWorkers  = 12;
masterClock = tic;

if matlabpool('size') > 0
    matlabpool('close');
end;
%matlabpool(poolWorkers);

mkdir(regFolder);

xSize = 2048;
ySize = 2048;
zSize = numel(slices);
tSize = numel(timeRange);
%% create time-averaged reference stack, over all time points
refTimePoint = 1;
refStackName = [volFolder,'\TM',num2str(refTimePoint, '%.5d'),'\TM',num2str(refTimePoint, '%.5d'),'_CM0_CHN00.stack' ];
tic;
referenceStack=read_LSstack_fast2(refStackName,[xSize ySize],[1 40]);

for t = 2:tSize
        timePoint = timeRange(t);  
        stackName = [volFolder,'\TM',num2str(timePoint, '%.5d'),'\TM',num2str(timePoint, '%.5d'),'_CM0_CHN00.stack' ];
        currentStack = read_LSstack_fast2(stackName,[xSize ySize],[1 40]);
        for z = 1:zSize
            [dx, dy] = registerImages(referenceStack(:,:,z), currentStack(:,:,z));
            if dx > 0 && dy > 0
                currentStack(1:(end - dx), 1:(end - dy),z) = currentStack((1 + dx):end, (1 + dy):end,z);
            elseif dx > 0 && dy < 0
                currentStack(1:(end - dx), (1 - dy):end,z) = currentStack((1 + dx):end, 1:(end + dy),z);
            elseif dx < 0 && dy > 0
                currentStack((1 - dx):end, 1:(end - dy),z) = currentStack(1:(end + dx), (1 + dy):end,z);
            elseif dx < 0 && dy < 0
                currentStack((1 - dx):end, (1 - dy):end,z) = currentStack(1:(end + dx), 1:(end + dy),z);
            end;
        end
        mkdir([regFolder,'\TM',num2str(timePoint, '%.5d')]);
        outputName = [regFolder,'\TM',num2str(timePoint, '%.5d'),'\TM',num2str(timePoint, '%.5d'),'_CM0_CHN00.stack' ];
        multibandwrite(currentStack, outputName, 'bsq', 'machfmt', 'ieee-le');
end;

if matlabpool('size') > 0
    matlabpool('close');
end;

toc