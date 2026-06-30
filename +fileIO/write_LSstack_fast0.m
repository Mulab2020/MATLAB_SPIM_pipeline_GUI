function write_LSstack_fast0(outputName,currentStack)


if nargin<2
    error('2 input args needed');
end

fileIO.write_LSstack_fast0_mex64(outputName,currentStack);