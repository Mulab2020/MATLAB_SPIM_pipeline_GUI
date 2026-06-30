function outparams=align_ephysCh3_2P(ch3,minL,stimParam1,stimParam2,stimParam3,stimParam4,blocklist,frameNumber)


outparams=struct;

efn = round(ch3/0.05);
efn = efn';
efn = efn(:);
efn = efn(1:length(ch3));

minds_efn=find(abs(diff(efn))>0);
minds_efn(2:end+1)=minds_efn(1:end);
minds_efn(1)=1;
minds_efn(end+1)=length(efn);
nframes=max(frameNumber);

frame_inds=zeros(2,nframes+1);

fn=1;
for i = 2:length(minds_efn)
    dur=minds_efn(i)-minds_efn(i-1);
    if i==2
        frame_inds(1,fn)=minds_efn(i-1);
        frame_inds(2,fn)=minds_efn(i);
    end      
    
    if i>2 && dur>minL
        fn=fn+1;
        frame_inds(1,fn)=minds_efn(i-1)+1;
        frame_inds(2,fn)=minds_efn(i);
    else
        minds_efn(i)=minds_efn(i-1);
    end
end


outparams.s1 = zeros(1,nframes);
outparams.s2 = zeros(1,nframes);
outparams.s3 = zeros(1,nframes);
outparams.s4 = zeros(1,nframes);
outparams.bl = zeros(1,nframes);

for fN = 1:length(frameNumber)
    inds=frame_inds(1,fN):frame_inds(2,fN);
    if length(inds) > 1
        outparams.s1(fN) = median(stimParam1(inds));
        outparams.s2(fN) =   mean(stimParam2(inds));
        outparams.s3(fN) = median(stimParam3(inds));
        outparams.s4(fN) = median(stimParam4(inds));
        outparams.bl(fN) = median(blocklist(inds));
    else
        continue;
    end
end








