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
SEXP zt_grp_sort(SEXP keys, SEXP i64, SEXP nrows, SEXP force);
SEXP zt_key_order(SEXP keys, SEXP i64, SEXP dec, SEXP na_last);
SEXP zt_key_rank(SEXP keys, SEXP i64, SEXP dec, SEXP na_last, SEXP ties);
SEXP zt_strings_rank(SEXP x);
SEXP zt_sorted_wrap(SEXP x, SEXP sorted, SEXP no_na);
SEXP zt_sorted_meta(SEXP x);
SEXP zt_join(SEXP xkeys, SEXP ykeys, SEXP i64, SEXP type, SEXP multiple,
             SEXP xmask, SEXP ymask);
void zt_init_altrep(DllInfo *dll);

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
  {"zt_grp_sort", (DL_FUNC) &zt_grp_sort, 4},
  {"zt_key_order", (DL_FUNC) &zt_key_order, 4},
  {"zt_key_rank", (DL_FUNC) &zt_key_rank, 5},
  {"zt_strings_rank", (DL_FUNC) &zt_strings_rank, 1},
  {"zt_sorted_wrap", (DL_FUNC) &zt_sorted_wrap, 3},
  {"zt_sorted_meta", (DL_FUNC) &zt_sorted_meta, 1},
  {"zt_join", (DL_FUNC) &zt_join, 7},
  {NULL, NULL, 0}
};

void attribute_visible R_init_zutable(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
  zt_init_altrep(dll);
}
