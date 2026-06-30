function FOV=meanZ_large_stacks(stack)

dim=size(stack);

dim=double(dim);
FOV      = zeros(dim(1),dim(2),'double');
buffdata = zeros(dim(1),dim(2),100,'double');

nrepeats = floor(dim(3)/500);
remains  = dim(3)-500*nrepeats;

if nrepeats>0
    for i=1:nrepeats
        buffdata=double(stack(:,:,(i-1)*500+1:i*500));
        FOV = FOV + mean(buffdata,3)*(500/dim(3));
    end
end

if remains>0
    buffdata(:,:,1:remains)=double(stack(:,:,end-remains+1:end));
    FOV = FOV + mean(buffdata(:,:,1:remains),3)*(remains/dim(3));
end



