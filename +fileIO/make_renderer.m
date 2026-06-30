clear all; close all;

dim=size(imread('Y:\Takashi\SPIM\10312013\Fish1-3\Background_0.tif'));
height=dim(2);
width=dim(1);
dim(3)=41;
zplanes=41;
tlen=240;

%%
disp(1);
root_dir='Y:\Takashi\SPIM\10312013\Fish1-3\Registered';

imgstack = read_LSstack_fast_float(fullfile(root_dir,'trial_ave.stackf'),[height width tlen zplanes]);
ave      = read_LSstack_fast_float(fullfile(root_dir,'ave.stackf'),[height width zplanes]);

%%

disp(2);
timelist=ones(1,24)*10;
cum_timelist = cumsum(timelist);
cum_timelist(2:end+1)=cum_timelist(1:end);
cum_timelist(1)=0;
planelist=zeros(tlen,1);

for i=1:length(timelist)
    planelist(cum_timelist(i)+1:cum_timelist(i+1)) = i;
end

disp(3);
resp_stack=create_resp_ave(single(imgstack),int32(height*width),int32(tlen),int32(zplanes),int32(planelist),int32(max(planelist)));

%%


disp(4);
resp_stack=reshape(resp_stack,[height width, zplanes, length(timelist)]);


disp(5);
baseline=single(squeeze(min(resp_stack,[],4)));


%%
disp(6);

aven=zeros(size(ave));
aven(:,:,1:2:41)=ave(:,:,1:21);
aven(:,:,2:2:40)=ave(:,:,41:-1:22);
aven=(aven/max(aven(:)))*255;

for i=1:240
    name=['tseries_T',num2str(i,'%.3d'),'.tif'];
    writetiff(uint8(aven),fullfile(root_dir,name));
end

%%
for i=1:240
    name=['tseriesR_T',num2str(i,'%.3d'),'.tif'];
    ave2=(squeeze(imgstack(:,:,i,:))./baseline)-1;
    ave2(ave2<0)=0;
    ave2=ave2*128;
    ave2(ave2>255)=255;
    
    ave3=zeros(size(ave));
    ave3(:,:,1:2:41)=ave2(:,:,1:21);
    ave3(:,:,2:2:40)=ave2(:,:,41:-1:22);
    
    writetiff(uint8(ave3),fullfile(root_dir,name));
end