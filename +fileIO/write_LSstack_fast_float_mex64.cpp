#include "mex.h"   
#include<windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <io.h>

void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){
    
    
    char *input_buf;
    int buflen,status;
	__int64 max_size=3000000000;
	__int64  zstepf= (max_size/((__int64)(sizeof(float))));
      
    buflen = (mxGetM(operand[0]) * mxGetN(operand[0])) + 1;
    input_buf = (char *)mxCalloc(buflen, sizeof(char));
    status = mxGetString(operand[0], input_buf, buflen);
    
    
     float* input_stack;
    (float*)input_stack = (float*) mxGetData(operand[1]);
        
    __int64 stacklen = (__int64)mxGetM(operand[1])* (__int64)mxGetN(operand[1]);        
	__int64 zrepeatf=  stacklen/zstepf;
    
    
    __int64  amarif= stacklen-zstepf*zrepeatf;
	if (amarif!=0){
		zrepeatf +=1;
	}
    
    mexPrintf("%d\n",amarif);
    
	__int64 *zlistf;
	zlistf=(__int64 *)calloc(zrepeatf,sizeof(__int64));
    
    for (int i=0;i<(int)zrepeatf; i++){
		if(amarif != 0 && i == zrepeatf-1){
			zlistf[i]=amarif;
		}
		else{
			zlistf[i]=zstepf;
		}
	}
    
    FILE *_ff=fopen(input_buf,"wb");
	
	for (int i=0; i< zrepeatf;i++){
		fwrite(input_stack, sizeof(float),zlistf[i],_ff);
		input_stack=input_stack + zlistf[i];
	}

	fclose(_ff);
    
   
    
    mexUnlock();  
}
