function out=calc_rank_simple2(im, rank_one,radius,oop,one_inds,moveinds,mask_inds)

dim=size(im);
dimp=dim+2*radius;
imp=zeros(dimp,'single');

inds=one_inds(mask_inds);
imp(one_inds)=im(:);

out=zeros(size(im));
out(mask_inds)=double(util.localrank_2D_simple_mex(single(imp),int32(oop),int32(inds),int32(moveinds)))./rank_one(mask_inds);

