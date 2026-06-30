function [dim,stack]=read_mbif3_fast(fpath)

info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end

[dim, stack]=read_mbif3_fast_mex64(fpath);
disp(dim);
dim=double(dim);
stack=reshape(stack,dim);
