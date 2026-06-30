clear all;close all;

volFolder    = 'Y:\Minoru\2013-09-10\Timeseries_20130910_134808';
regFolder = [volFolder '\registered'];
timeRange    = 0:588;

mkdir(regFolder);

ySize = 2048;
xSize = 1084;
tSize = numel(timeRange);
%% create time-averaged reference stack, over all time points
refTimePoint = 1;
refStackName = [volFolder,'\TM',num2str(refTimePoint, '%.5d'),'_CM0_CHN00.stack' ];

referenceStack=read_LSstack_fast1(refStackName,[ySize xSize]);
ROIs=set_LS_ROIs(referenceStack);


slices=ROIs.zrange(1):ROIs.zrange(2);
zSize = numel(slices);
xrange=ROIs.xrange(1):ROIs.xrange(2);
yrange=ROIs.yrange(1):ROIs.yrange(2);
tranges=repmat(timeRange,[zSize 1]);
startslice=slices(1);
referenceStack=referenceStack(:,:,slices);

tic;
matlabpool(12);

parfor z=1:length(slices)
    
    refImg=referenceStack(:,:,z);
    refImg=refImg(yrange,xrange);
    
    refImg =double(refImg);
    refImg_fft=conj(fft2(refImg - mean(refImg(:))));
    
    outputName = fullfile(regFolder,['reg_slice',num2str(startslice+z-1),'.stack']);
    
    for t = 1:tSize

        if (mod(t,50)==0)
            disp([num2str(t)]);
        end

        timePoint =tranges(z,t);  
        stackName = [volFolder,'\TM',num2str(timePoint, '%.5d'),'_CM0_CHN00.stack' ];
        img = read_LSstack_fast3(stackName,[ySize xSize],z);   
        img = img(yrange,xrange);

        [dx, dy] = registerImages(refImg_fft, img);
        if dx > 0 && dy > 0
            img(1:(end - dx), 1:(end - dy)) = img((1 + dx):end, (1 + dy):end);
        elseif dx > 0 && dy < 0
            img(1:(end - dx), (1 - dy):end) = img((1 + dx):end, 1:(end + dy));
        elseif dx < 0 && dy > 0
            img((1 - dx):end, 1:(end - dy)) = img(1:(end + dx), (1 + dy):end);
        elseif dx < 0 && dy < 0
            img((1 - dx):end, (1 - dy):end) = img(1:(end + dx), 1:(end + dy));
        end;
                
        write_LSstack_fast1(outputName,img);

    end
end

matlabpool close;

%%
save(fullfile(regFolder,'ROIs.mat'),'ROIs');
toc;
