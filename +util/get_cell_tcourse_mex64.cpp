#include"mex.h"   
#include<windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <io.h>

// first input == filename

// first output ==  size of the image; output stack;
// second output == 
void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){
    
    
    unsigned short *stack;       
    (unsigned short *)stack =  (unsigned short *)mxGetData(operand[0]);
    
    __int64 *sliceinds;       
    (__int64 *)sliceinds =  (__int64 *)mxGetData(operand[1]);
    
    __int64 *inds;       
    (__int64 *)inds =  (__int64 *)mxGetData(operand[2]);
    
    int zlen   = mxGetM(operand[1])*mxGetN(operand[1]);
    int area   = mxGetM(operand[2])*mxGetN(operand[2]);
    
    double *tcourse;       
    returned[0] = mxCreateNumericMatrix(1,zlen,mxDOUBLE_CLASS,mxREAL);
    tcourse =  mxGetPr(returned[0]);
    
    int ii=0;
    int jj=0;
    int i,j;
    double area2=(double)area;

            
    for(i=0;i<zlen;i++){                
        for (j=0;j<area;j++){
            tcourse[i] +=(double)(stack[sliceinds[i]+inds[j]-1]);            
        }    
        tcourse[i] /= area2;
    }
    
    mexUnlock();  
}
