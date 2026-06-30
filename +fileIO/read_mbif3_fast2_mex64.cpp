#include"mex.h"   
#include<windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <io.h>

// first input == filename

// first output ==  size of the image; output stack;
// second output == 
void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){
    
    int *whl;       
    returned[0] = mxCreateNumericMatrix(1,3,mxINT32_CLASS,mxREAL);
    (int *)whl =  (int *)mxGetData(returned[0]);
    
    char *input_buf;
    int buflen,status;
      
    buflen = (mxGetM(operand[0]) * mxGetN(operand[0])) + 1;
    input_buf = (char *)mxCalloc(buflen, sizeof(char));
    status = mxGetString(operand[0], input_buf, buflen);

    int infospace=32; // bytes before imdata
    
    unsigned int *wh;
    wh    = (unsigned int *)mxCalloc(2, sizeof(unsigned int));
        
    FILE *f=NULL;

    f=fopen(input_buf,"rb");
    fread(wh,sizeof(unsigned int),2,f);
    
    whl[0] =  (int) wh[0];
    whl[1] =  (int) wh[1];
    int imlen=whl[0]*whl[1];    
    
     // get file size
     // _lseeki64 was used instead of fseek for reading files > 3GB 
    
    __int64 length = _lseeki64(_fileno(f), 0, SEEK_END);   
    __int64 singlelen = ((__int64) imlen )*2+infospace;
    
    length /= singlelen;
    whl[2] = (int)length;     
     
    fclose(f); 
    
    // read image files
    // minimized fread excution for communication between servers.
    
    int singlelen2 = (int) singlelen/2;
    
    unsigned short *stack;       
    returned[1] = mxCreateNumericMatrix(whl[0],whl[1]*whl[2],mxUINT16_CLASS,mxREAL);
    (unsigned short *)stack =  (unsigned short *)mxGetData(returned[1]);
    
    float *scanV;       
    returned[2] = mxCreateNumericMatrix(1,4,mxSINGLE_CLASS,mxREAL);
    (float *)scanV =  (float *)mxGetData(returned[2]);
       
    unsigned short *localbuf;
    localbuf    = (unsigned short *)mxCalloc(singlelen2 , sizeof(unsigned short));       
    
     
    int i,j,jj;
    
    f=fopen(input_buf,"rb");   
    i=whl[2];
    while(i--)
    {
        fread(localbuf,sizeof(unsigned short),singlelen2,f);
        
        j  = imlen;
        jj = infospace/2;
        
        while(j--)
        {
            *stack=localbuf[jj];   
            stack++;
            jj++;
        } 
    }
    fclose(f);
    
    f=fopen(input_buf,"rb");  
    fseek(f,16,SEEK_SET);
    fread(scanV,sizeof(float),4, f);
    fclose(f);    
    
    mexUnlock();  
}
