// A second translation unit including the header: every kernel function
// is static inline, so two copies link without a clash.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <zutable.h>

SEXP zt_consume_version_c(void);

// The header's version, and its parts, as the consumer was compiled with.
SEXP zt_consume_version_c(void) {
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, Rf_mkString(ZUTABLE_VERSION));
  SEXP parts = Rf_allocVector(INTSXP, 4);
  SET_VECTOR_ELT(out, 1, parts);
  INTEGER(parts)[0] = ZUTABLE_VERSION_MAJOR;
  INTEGER(parts)[1] = ZUTABLE_VERSION_MINOR;
  INTEGER(parts)[2] = ZUTABLE_VERSION_PATCH;
  INTEGER(parts)[3] = ZUTABLE_VERSION_DEV;
  UNPROTECT(1);
  return out;
}
