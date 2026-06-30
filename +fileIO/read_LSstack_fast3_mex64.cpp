#include"mex.h"   
#include<windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <io.h>

void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){
    
    
    char *input_buf;
    int buflen,status;
      
    buflen = (mxGetM(operand[0]) * mxGetN(operand[0])) + 1;
    input_buf = (char *)mxCalloc(buflen, sizeof(char));
    status = mxGetString(operand[0], input_buf, buflen);
    
    
    int *wh;       
    (int *)wh =  (int *)mxGetData(operand[1]);
    
    int *z;       
    (int *)z =  (int *)mxGetData(operand[2]);
    
        
    int zlen;

        
    FILE *f=NULL;

    f=fopen(input_buf,"rb");
     // get file size
     // _lseeki64 was used instead of fseek for reading files > 3GB 
    
    __int64 length = _lseeki64(_fileno(f), 0, SEEK_END);   
    __int64 singlelen = (__int64) wh[0]*wh[1]*sizeof(unsigned short);
    
    length /= singlelen;
    zlen  = (int)length;   
    
    fclose(f); 
    
    if (*z < 1)   {*z =1;};
    if (*z > zlen){*z =zlen;};
    
    
    int imagelen=wh[0]*wh[1];
    
    // read image files
    // minimized fread excution for communication between servers.
    unsigned short *image;       
    returned[0] = mxCreateNumericMatrix(wh[0],wh[1],mxUINT16_CLASS,mxREAL);
    (unsigned short *)image =  (unsigned short *)mxGetData(returned[0]);
   
    int i,j,jj;
    
    f=fopen(input_buf,"rb");
        _lseeki64(_fileno(f), singlelen*(__int64) (*z-1), SEEK_SET);         
        fread(image,sizeof(unsigned short),imagelen,f);
    fclose(f);
    
    mexUnlock();  
}
