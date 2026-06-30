function stack=fix_mbif3_error(stack)

dim=size(stack);

for i=1:dim(3)
   
    image=stack(:,:,i);
    
    image(image >  63000)  = image(image >  63000)-63000;
    image(image <= 63000)  = image(image <= 63000) +2535;
    
    stack(:,:,i)=image;
end