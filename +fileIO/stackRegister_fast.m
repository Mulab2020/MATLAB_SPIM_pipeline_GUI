function [stack,outs]=stackRegister_fast(stack,target)

TARGET = fft2(double(target));
[ny,nx,nframes]=size(stack);
outs = zeros(nframes,2);

tic;
fprintf(1, 'Starting, frame 0\n');

for index = 1:nframes
    if mod(index,100)==0 
        fprintf(1,'Frame %i (%2.1f fps)\n',index,index/toc);
    end
    
    SLICE = fft2(double(stack(:,:,index)));
    outs(index,:) = dftregistration2(TARGET,SLICE);
    stack(:,:,index)=circshift(stack(:,:,index),[outs(index,1),outs(index,2)]);
end

t = toc;
fprintf('Registered %i frames in %2.1f seconds (%2.1f fps)\n',nframes,t,nframes/t);

return;

function output = dftregistration2(buf1ft,buf2ft)

[m,n]=size(buf1ft);
CC = ifft2(buf1ft.*conj(buf2ft));
[max1,loc1] = max(CC);
[max2,loc2] = max(max1);
rloc=loc1(loc2);
cloc=loc2;
CCmax=CC(rloc,cloc); 

md2 = fix(m/2); 
nd2 = fix(n/2);
if rloc > md2
    row_shift = rloc - m - 1;
else
    row_shift = rloc - 1;
end

if cloc > nd2
    col_shift = cloc - n - 1;
else
    col_shift = cloc - 1;
end
output=double([row_shift,col_shift]);
    
return

