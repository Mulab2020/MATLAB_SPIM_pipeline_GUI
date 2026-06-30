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
    
    unsigned int *wh;
    wh    = (unsigned int *)mxCalloc(3, sizeof(unsigned int));
        
    FILE *f=NULL;

    f=fopen(input_buf,"rb");
    fread(wh,sizeof(unsigned int),3,f);     
    fclose(f); 
    
    whl[0] =  (int) wh[0];
    whl[1] =  (int) wh[1];
    whl[2] =  (int) wh[2];   

    
    mexUnlock();  
}
