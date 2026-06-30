function dim=read_LSstack_size(fpath)
%% reads whole stack

info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end

dim=read_LSstack_size_mex(fpath);


