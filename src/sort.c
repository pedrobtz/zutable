// key_order() and key_rank(): the R side of zutable/sort.h. A thin
// translation (design-kernel section 4): the R layer has checked the keys
// (integer, logical, double, integer64 as double bits) and the options;
// this fills the sort columns, calls the header and wraps the result.
// Scratch comes from R_alloc, so an R error frees it.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <zutable.h>

static zt_sort_col *zt_fill_sort_cols(SEXP keys, SEXP i64, SEXP dec, zt_row *n) {
  int ncol = (int) XLENGTH(keys);
  zt_sort_col *cols = (zt_sort_col *) R_alloc(ncol > 0 ? (size_t) ncol : 1, sizeof(zt_sort_col));
  *n = ncol > 0 ? (zt_row) XLENGTH(VECTOR_ELT(keys, 0)) : 0;
  for (int c = 0; c < ncol; c++) {
    SEXP x = VECTOR_ELT(keys, c);
    if (XLENGTH(x) != *n) Rf_error("zt_key_order: key columns differ in length");
    switch (TYPEOF(x)) {
    case INTSXP: cols[c].kind = ZT_KIND_INT32; cols[c].data = INTEGER_RO(x); break;
    case LGLSXP: cols[c].kind = ZT_KIND_LGL; cols[c].data = LOGICAL_RO(x); break;
    case REALSXP:
      cols[c].kind = LOGICAL(i64)[c] ? ZT_KIND_I64 : ZT_KIND_F64;
      cols[c].data = REAL_RO(x);
      break;
    default: Rf_error("zt_key_order: unsupported key column");
    }
    cols[c].decreasing = LOGICAL(dec)[c] == 1;
  }
  return cols;
}

// The stable order, 1-based. na_last: 1 last, 0 first, -1 dropped. The
// scratch is what the plan asks for: none when the rows are in order.
SEXP zt_key_order(SEXP keys, SEXP i64, SEXP dec, SEXP na_last) {
  zt_row n;
  int ncol = (int) XLENGTH(keys);
  int na = Rf_asInteger(na_last);
  zt_sort_col *cols = zt_fill_sort_cols(keys, i64, dec, &n);
  zt_codebook *cb = (zt_codebook *) R_alloc(ncol > 0 ? (size_t) ncol : 1, sizeof(zt_codebook));
  zt_order_plan plan;
  size_t bytes = zt_order_prepare(cols, ncol, n, na, cb, &plan);
  void *mem = bytes ? R_alloc(bytes, 1) : NULL;
  SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
  int *o = INTEGER(out);
  zt_row m = zt_order_run(cols, ncol, n, na, cb, &plan, o, mem);
  for (zt_row j = 0; j < m; j++) o[j]++;
  if (m < n) out = Rf_xlengthgets(out, m);
  UNPROTECT(1);
  return out;
}

// Ranks by row, 1-based; 0 for a row left out (na_last -1). ties: 1 min,
// 2 first, 3 dense.
SEXP zt_key_rank(SEXP keys, SEXP i64, SEXP dec, SEXP na_last, SEXP ties) {
  zt_row n;
  int ncol = (int) XLENGTH(keys);
  zt_sort_col *cols = zt_fill_sort_cols(keys, i64, dec, &n);
  zt_codebook *cb = (zt_codebook *) R_alloc(ncol > 0 ? (size_t) ncol : 1, sizeof(zt_codebook));
  void *mem = R_alloc(zt_sort_scratch_bytes(n), 1);
  zt_row *ord = (zt_row *) R_alloc(n > 0 ? (size_t) n : 1, sizeof(zt_row));
  SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
  zt_rank(cols, ncol, n, Rf_asInteger(na_last), (zt_ties) Rf_asInteger(ties), cb,
          INTEGER(out), mem, ord);
  UNPROTECT(1);
  return out;
}
