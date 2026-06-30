#include"mex.h"   
#include<windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <io.h>

// first input == filename

// first output ==  size of the image; output stack;
// second output == 
void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){
    
    
    char *input_buf;
    int buflen,status;
      
    buflen = (mxGetM(operand[0]) * mxGetN(operand[0])) + 1;
    input_buf = (char *)mxCalloc(buflen, sizeof(char));
    status = mxGetString(operand[0], input_buf, buflen);
    
    
    int *wh;       
    (int *)wh =  (int *)mxGetData(operand[1]);
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
    
    
    size_t stacklen=((size_t)wh[0])*((size_t)wh[1])*(size_t)zlen;
    
    // read image files
    // minimized fread excution for communication between servers.
    unsigned short *stack;       
    returned[0] = mxCreateNumericMatrix(wh[0],wh[1]*zlen,mxUINT16_CLASS,mxREAL);
    (unsigned short *)stack =  (unsigned short *)mxGetData(returned[0]);
    
    int *dim;       
    returned[1] = mxCreateNumericMatrix(1,3,mxINT32_CLASS,mxREAL);
    (int *)dim =  (int *)mxGetData(returned[1]);
    dim[0]=wh[0];
    dim[1]=wh[1];
    dim[2]=zlen;        
    
   
    int i,j,jj;
    
    f=fopen(input_buf,"rb");   
    fread(stack,sizeof(unsigned short),stacklen,f);
    fclose(f);
    
    mexUnlock();  
}
