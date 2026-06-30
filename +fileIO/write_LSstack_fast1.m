function write_LSstack_fast1(outputName,currentStack)


if nargin<2
    error('2 input args needed');
end

fileIO.write_LSstack_fast1_mex64(outputName,currentStack);