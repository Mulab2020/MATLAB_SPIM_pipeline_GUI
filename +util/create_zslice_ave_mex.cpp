#include"mex.h"   
#include <stdio.h>
#include <stdlib.h>


void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){
    
    int ii,jj;
    
    unsigned short *stack,*stack_ori;       
    (unsigned short *)stack =  (unsigned short *)mxGetData(operand[0]);
    stack_ori=stack;
    
    int *dim;       
    (int *)dim =  (int *)mxGetData(operand[1]);
    
    int slicelen=dim[0]*dim[1];
    
    int *zrange;       
    (int *)zrange =  (int *)mxGetData(operand[2]);
    int zlen=mxGetM(operand[2])*mxGetN(operand[2]);
        

    
    double *output, *output_ori;;       
    returned[0] = mxCreateNumericMatrix(dim[0],dim[1],mxDOUBLE_CLASS,mxREAL);
    output =  (double *)mxGetData(returned[0]);
    output_ori=output;
    
   
     __int64 startpoint;        
    for (ii=0; ii<zlen; ii++){        
         
        startpoint=((__int64)(zrange[ii]-1))*((__int64)(slicelen)); 
        stack=stack_ori+startpoint;
        output=output_ori;
        
        for (jj=0; jj<slicelen; jj++){               
            *output += (double)*stack;    
            stack++;
            output++;
        }        
    }
     
    output=output_ori;
    for (jj=0; jj<slicelen; jj++){               
        *output /= (double)zlen;    
        output++;
    }
            
    mexUnlock();  
}
