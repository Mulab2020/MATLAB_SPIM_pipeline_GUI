#include"mex.h"   
#include<windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <io.h>

void mexFunction( int Nreturned, mxArray *returned[], int Noperand, const mxArray *operand[] ){    
    
    char *input_buf;
    int buflen,status;
    int i,j;
      
    buflen = (mxGetM(operand[0]) * mxGetN(operand[0])) + 1;
    input_buf = (char *)mxCalloc(buflen, sizeof(char));
    status = mxGetString(operand[0], input_buf, buflen);    
    
    int *wh;       
    (int *)wh =  (int *)mxGetData(operand[1]);
    
    int *pixpos;       
    (int *)pixpos =  (int *)mxGetData(operand[2]);
    int pixlen = (int) mxGetM(operand[2]) * (int) mxGetN(operand[2]);
    
    
    __int64 *pixpos2;
    (__int64 *)pixpos2=(__int64 *)mxCalloc(pixlen,sizeof(__int64));
    
    for (i=0;i<pixlen;i++){
        pixpos2[i]=((pixpos[i]-1)*sizeof(unsigned short));        
    }    
            
    double dpixlen = (double)pixlen;            
                    
    FILE *f=NULL;

    f=fopen(input_buf,"rb");
     // get file size
     // _lseeki64 was used instead of fseek for reading files > 3GB 
    
    __int64 length = _lseeki64(_fileno(f), 0, SEEK_END);   
    __int64 singlelen = (__int64) wh[0]*wh[1]*sizeof(unsigned short);
    
    length /= singlelen;
    int zlen  = (int)length;   
    
    fclose(f); 
    
    
    // read image files
    // minimized fread excution for communication between servers.
    double *tcourse;       
    returned[0] = mxCreateNumericMatrix(zlen,1,mxDOUBLE_CLASS,mxREAL);
    (double *)tcourse =  (double *)mxGetData(returned[0]);
    
    
    
    unsigned short tempu;
    double dtemp=0;
    
    __int64 zstart=0;    
    
    int ii,jj;
    f=fopen(input_buf,"rb");    
    
    for (jj = 0;jj < pixlen; jj++){
        fseek(f,pixpos2[jj], SEEK_SET); 
        for (ii = 0;ii < zlen-1; ii++){
            fread(&tempu,sizeof(unsigned short),1,f);
            tcourse[ii] += (double)tempu;
            _fseeki64(f,singlelen-sizeof(unsigned short), SEEK_CUR); 
        }
        fread(&tempu,sizeof(unsigned short),1,f);
        tcourse[zlen-1] += (double)tempu;
    }
    fclose(f);
    
     for (ii = 0;ii < zlen; ii++){    
         tcourse[ii] /=dpixlen;
    }
    
    
    mexUnlock();  
}
