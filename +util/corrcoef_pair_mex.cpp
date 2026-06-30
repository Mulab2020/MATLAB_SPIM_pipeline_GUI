#include"mex.h"
#include <stdlib.h>
#include <math.h>

void mexFunction( int Nreturned,  mxArray *returned[], int Noperand, const  mxArray *operand[] ){
  double  *X        = mxGetPr(operand[0]);
  double  *Y        = mxGetPr(operand[1]);
  
    
  double *corr_coef;
  returned[0] = mxCreateNumericMatrix(1,1,mxDOUBLE_CLASS,mxREAL);    
  corr_coef= mxGetPr(returned[0]);
  
  
  int len =mxGetM(operand[0])*mxGetN(operand[0]);
  int len2=mxGetM(operand[1])*mxGetN(operand[1]);
  
  if (len!=len2){
        *corr_coef=0;
        mexPrintf("Error: input length mismatch \n");
        return;
  }else{
        double x_mean,x_dist,y_mean,y_dist,sub;
        x_mean=0;
        x_dist=0;
        sub =0;
        y_dist=0;
        y_mean=0;
        

        int i=len;
        while (i--){
            x_mean +=X[i];  
            y_mean +=Y[i];  
        }
        x_mean=x_mean/(len);  
        y_mean=y_mean/(len);  

        i=len;
        while (i--){ 
         x_dist   +=pow((X[i]-x_mean),2);
         y_dist   +=pow((Y[i]-y_mean),2);
         sub      +=(X[i]-x_mean)*(Y[i]-y_mean);
        }
        *corr_coef=sub/(sqrt(x_dist)*sqrt(y_dist));
  }
  
      
  
}

