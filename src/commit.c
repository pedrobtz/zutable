// In-place updates (design §6.4, §6.7). A commit swaps column pointers in
// the table's list and never writes into a vector (D27), so a vector shared
// with another table or a plain data frame is never changed. Every alias of
// the table sees the commit (D14). The frozen mark is checked here, so no
// R-level route writes past it.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Rf_error here is unreachable from R (#68): R/update.R passes a table, the
// column indices match() found and one column per index; the checks stand
// for an internal caller (test-native-guards.R).

static int zt_is_frozen_sexp(SEXP x) {
  SEXP mark = Rf_getAttrib(x, Rf_install("frozen"));
  return TYPEOF(mark) == LGLSXP && XLENGTH(mark) == 1 && LOGICAL(mark)[0] == TRUE;
}

// Replace columns `which` (1-based) of the list `x` with `cols`, clear its
// column properties, and set its plan record when `plan` is not NULL.
// Returns 0, or 1 without writing anything when `x` is frozen; the caller
// raises the classed condition.
SEXP zt_commit(SEXP x, SEXP which, SEXP cols, SEXP plan) {
  if (TYPEOF(x) != VECSXP) Rf_error("zt_commit: a table is required");
  if (TYPEOF(which) != INTSXP || TYPEOF(cols) != VECSXP ||
      XLENGTH(which) != XLENGTH(cols)) {
    Rf_error("zt_commit: `which` and `cols` must match");
  }
  if (zt_is_frozen_sexp(x)) return Rf_ScalarInteger(1);
  R_xlen_t ncol = XLENGTH(x);
  const int *pw = INTEGER(which);
  // Validate every target before writing one, so a commit is all or nothing.
  for (R_xlen_t i = 0; i < XLENGTH(which); i++) {
    if (pw[i] == NA_INTEGER || pw[i] < 1 || pw[i] > ncol) {
      Rf_error("zt_commit: column index out of range");
    }
  }
  for (R_xlen_t i = 0; i < XLENGTH(which); i++) {
    SET_VECTOR_ELT(x, pw[i] - 1, VECTOR_ELT(cols, i));
  }
  SEXP props = PROTECT(Rf_allocVector(VECSXP, 0));
  Rf_setAttrib(x, Rf_install("properties"), props);
  if (plan != R_NilValue) Rf_setAttrib(x, Rf_install("plan"), plan);
  UNPROTECT(1);
  return Rf_ScalarInteger(0);
}

// Mark a table frozen, in place, so every alias is frozen. One-way.
SEXP zt_freeze(SEXP x) {
  if (TYPEOF(x) != VECSXP) Rf_error("zt_freeze: a table is required");
  SEXP mark = PROTECT(Rf_ScalarLogical(TRUE));
  Rf_setAttrib(x, Rf_install("frozen"), mark);
  UNPROTECT(1);
  return x;
}

// An independent table for one allocation: a new list holding the same
// column vectors (commits never write into them), the same attributes,
// and no frozen mark.
SEXP zt_copy(SEXP x) {
  if (TYPEOF(x) != VECSXP) Rf_error("zt_copy: a table is required");
  R_xlen_t n = XLENGTH(x);
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
  for (R_xlen_t i = 0; i < n; i++) SET_VECTOR_ELT(out, i, VECTOR_ELT(x, i));
  SHALLOW_DUPLICATE_ATTRIB(out, x);
  Rf_setAttrib(out, Rf_install("frozen"), R_NilValue);
  UNPROTECT(1);
  return out;
}
