// zutable_info(): the versions the shared object was built with.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <zufast/version.h>
#include <zutable.h>

SEXP zt_info(void) {
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SEXP nms = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_VECTOR_ELT(out, 0, Rf_mkString(ZUTABLE_VERSION));
  SET_STRING_ELT(nms, 0, Rf_mkChar("header"));
  SET_VECTOR_ELT(out, 1, Rf_mkString(ZUFAST_VERSION));
  SET_STRING_ELT(nms, 1, Rf_mkChar("zufast"));
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(2);
  return out;
}
