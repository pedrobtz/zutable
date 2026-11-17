#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

SEXP zt_parse_f64(SEXP x);
SEXP zt_format_f64(SEXP x);
SEXP zt_commit(SEXP x, SEXP which, SEXP cols, SEXP plan);
SEXP zt_freeze(SEXP x);
SEXP zt_copy(SEXP x);
SEXP zt_info(void);
SEXP zt_grp(SEXP keys, SEXP i64, SEXP nrows, SEXP force_bits);

// Native routines are registered here as stages add them. Symbols are
// hidden (Makevars) and only R_init_zutable is exported (design section 3,
// R3).
static const R_CallMethodDef call_methods[] = {
  {"zt_parse_f64", (DL_FUNC) &zt_parse_f64, 1},
  {"zt_format_f64", (DL_FUNC) &zt_format_f64, 1},
  {"zt_commit", (DL_FUNC) &zt_commit, 4},
  {"zt_freeze", (DL_FUNC) &zt_freeze, 1},
  {"zt_copy", (DL_FUNC) &zt_copy, 1},
  {"zt_info", (DL_FUNC) &zt_info, 0},
  {"zt_grp", (DL_FUNC) &zt_grp, 4},
  {NULL, NULL, 0}
};

void attribute_visible R_init_zutable(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
