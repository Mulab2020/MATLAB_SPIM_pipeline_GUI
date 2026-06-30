function write_LSstack_fast_float(outputName,currentStack)


if nargin<2
    error('2 input args needed');
end

fileIO.write_LSstack_fast_float_mex64(outputName,currentStack);