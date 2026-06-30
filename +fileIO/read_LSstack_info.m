function dim=read_LSstack_info(fpath,imsize)
%% reads whole stack

info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end


dim=fileIO.read_LSstack_info_mex64(fpath,int32(imsize));


