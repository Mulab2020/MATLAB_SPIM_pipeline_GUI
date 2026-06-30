#include "mex.h"   
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
    
    
    unsigned short *input_stack;
    (unsigned short*)input_stack = (unsigned short*) mxGetData(operand[1]);
        
    size_t stacklen = (size_t)mxGetM(operand[1])* (size_t)mxGetN(operand[1]);    
    
    FILE *f=NULL;

    f=fopen(input_buf,"wb");
        fwrite(input_stack, sizeof(unsigned short),stacklen,f);
    fclose(f);
    
    mexUnlock();  
}
