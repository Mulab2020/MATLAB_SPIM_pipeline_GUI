function image=read_LSstack_fast3(fpath,imsize,z)


info=dir(fpath);
if (isempty(info))
    error('File Does not exist');
end


image=fileIO.read_LSstack_fast3_mex64(fpath,int32(imsize),int32(z));

