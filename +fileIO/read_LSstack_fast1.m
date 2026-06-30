function [stack,dim]=read_LSstack_fast1(fpath,imsize)
%% reads whole stack

info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end


[stack,dim]=fileIO.read_LSstack_fast1_mex64(fpath,int32(imsize));


stack=reshape(stack,dim);
