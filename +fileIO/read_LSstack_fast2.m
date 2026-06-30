function [stack,dim]=read_LSstack_fast2(fpath,imsize,range)


info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end


[stack,dim]=fileIO.read_LSstack_fast2_mex64(fpath,int32(imsize),int32(range));


stack=reshape(stack,dim);
