#include <zutable.h>
int main(){ zt_row o[3]; double d[3]={2,1,3}; zt_sort_col c={ZT_KIND_F64,d,0}; zt_codebook cb; void*m=malloc(zt_sort_scratch_bytes(3)); return zt_order(&c,1,3,1,&cb,o,m)==3 && o[0]==1 ? 0:1; }
