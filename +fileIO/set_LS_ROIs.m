function ROIs=set_LS_ROIs(refStack)

global refstack_c;global h_window;global z_position;global dim;global h_text;global refstack_c2;
global ROIs;global hf;global OK;
z_position=1;

dim=size(refStack);
ROIs=struct;
ROIs.yrange=[1 dim(1)];
ROIs.xrange=[1 dim(2)];
ROIs.zrange=[1 dim(3)];

refstack_c=zeros(dim(1),dim(2),3,dim(3));
for i=1:dim(3)
    refstack_c(:,:,:,i) = repmat(imNormalize99(double(refStack(:,:,i))),[1 1 3 1]);
end

refstack_c2=refstack_c;

hf=figure;
set(hf,'Position',[100 100 1000 1200]);
h_window=axes('Parent',hf,'Units','normalized','Position', [0.05 0.05 0.9 0.8]);
h_slider = uicontrol(hf,'Style','slider','Units','normalized','Position', [0.1 0.9 0.8 0.02],'SliderStep',[1/(dim(3)-1) 1/(dim(3)-1)],'Callback',@slicer_callback);axis off;
h_text = uicontrol(hf,'Style','text','Units','normalized','Position', [0.45 0.93 0.1 0.01]);axis off;
h_startROI = uicontrol(hf,'Style','Pushbutton','Units','normalized','Position', [0.15 0.86 0.1 0.03],'String','Start ROI','Callback',@startROI);
h_resetROI = uicontrol(hf,'Style','Pushbutton','Units','normalized','Position', [0.3 0.86 0.1 0.03],'String','Reset ROI','Callback',@resetROI);
h_exit= uicontrol(hf,'Style','Pushbutton','Units','normalized','Position', [0.8 0.86 0.1 0.03],'String','EXIT','Callback',@exitROI);
h_zmin= uicontrol(hf,'Style','edit','Units','normalized','Position', [0.5 0.86 0.05 0.03],'String',num2str(1),'Callback',@zmin_change);
h_zmax= uicontrol(hf,'Style','edit','Units','normalized','Position', [0.6 0.86 0.05 0.03],'String',num2str(dim(3)),'Callback',@zmax_change);

image(squeeze(refstack_c(:,:,:,z_position)));axis off;
set(h_text,'String',['Z=',num2str(z_position)]);

set(h_exit,'Callback',@exitROI);
   
OK=0; 
while OK==0
    uiwait(hf);
end

end


function slicer_callback(src,evt)
    
global refstack_c;global h_window;global z_position;global dim;global h_text;

v=get(src,'Value');
z_position=round(v*(dim(3)-1))+1;

image(squeeze(refstack_c(:,:,:,z_position)),'Parent',h_window);axis off;
set(h_text,'String',['Z=',num2str(z_position)]);

end

function startROI(src,evt)

global refstack_c;global h_window;global ROIs;global dim;global z_position;

marg=30;
h2=imrect(h_window);

BW=createMask(h2);
rinds=find(imdilate(BW,strel('arbitrary',makeDisk2(3,7)))-BW);

for i=1:dim(3)
    temp=refstack_c(:,:,:,i);
    temp(rinds)=1;
    temp(rinds+dim(1)*dim(2))=0;
    temp(rinds+dim(1)*dim(2)*2)=0;    
    refstack_c(:,:,:,i) = temp;
end

p=getPosition(h2);
ROIs.yrange=[max([round(p(2)-marg) 1]) min([round(p(2)+p(4)+marg) dim(1)])];
ROIs.xrange=[max([round(p(1)-marg) 1]) min([round(p(1)+p(3)+marg) dim(2)])];

image(squeeze(refstack_c(:,:,:,z_position)),'Parent',h_window);axis off;

end


function resetROI(src,evt)

global refstack_c; global refstack_c2;global h_window;global dim;global ROIs;
global z_position;

refstack_c=refstack_c2;

image(squeeze(refstack_c(:,:,:,z_position)),'Parent',h_window);axis off;

ROIs.yrange=[1 dim(1)];
ROIs.xrange=[1 dim(2)];
ROIs.zrange=[1 dim(3)];

end


function zmax_change(src,evt)

global ROIs;

zz=str2double(get(src,'String'));
if zz<ROIs.zrange(1)
    zz=zrange(1);
end

ROIs.zrange(2)=zz;

end

function zmin_change(src,evt)

global ROIs;

zz=str2double(get(src,'String'));
if zz>ROIs.zrange(2)
    zz=zrange(2);
end

ROIs.zrange(1)=zz;

end

function exitROI(src,evt)

global hf;global OK;
uiresume(hf);
OK=1;
close all;
end




