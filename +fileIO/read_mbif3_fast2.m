function [dim,stack,scanV]=read_mbif3_fast2(fpath)

info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end

[dim, stack, scanV]=read_mbif3_fast2_mex64(fpath);
disp(dim);
dim=double(dim);
scanV=double(scanV);
stack=reshape(stack,dim);
