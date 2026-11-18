// grp_reduce() and the executor's aggregates: the R side of
// zutable/reduce.h. A thin translation (design-kernel section 4): check
// the columns, give each its output and scratch, call the header once for
// all of them. Scratch comes from R_alloc, so an R error frees it.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <zutable.h>

// id: integer group ids 1 .. ng, one per row, no NA. xs: a list of value
// columns (integer, logical or double; or NULL for count, and for first
// and last without na.rm). fns: the statistic
// of each (0 sum, 1 prod, 2 mean, 3 min, 4 max, 5 count, 6 nobs, 7 first,
// 8 last); narm, nanmiss: logical, one per column.
//
// Returns a list with one result per column, ng long: double for sum,
// prod and mean; integer or double, as the column, for min and max;
// integer for count and nobs; for first and last the 1-based row, NA for
// none.
SEXP zt_reduce_r(SEXP id, SEXP ng_, SEXP xs, SEXP fns, SEXP narm, SEXP nanmiss) {
  R_xlen_t nl = XLENGTH(id);
  if (TYPEOF(id) != INTSXP || nl > ZT_MAX_ROWS) Rf_error("zt_reduce: bad group ids");
  zt_row n = (zt_row) nl;
  int ng = Rf_asInteger(ng_);
  if (ng == NA_INTEGER || ng < 0) Rf_error("zt_reduce: bad group count");
  int ncol = (int) XLENGTH(xs);
  if (XLENGTH(fns) != ncol || XLENGTH(narm) != ncol || XLENGTH(nanmiss) != ncol) {
    Rf_error("zt_reduce: one statistic per column");
  }
  const int *raw = INTEGER_RO(id);
  zt_row *ids = (zt_row *) R_alloc((size_t) n + 1, sizeof(zt_row));
  for (zt_row i = 0; i < n; i++) {
    if (raw[i] < 1 || raw[i] > ng) Rf_error("zt_reduce: group id %d out of 1 .. %d", raw[i], ng);
    ids[i] = raw[i] - 1;
  }

  SEXP out = PROTECT(Rf_allocVector(VECSXP, ncol));
  zt_reduce_col *cols = (zt_reduce_col *) R_alloc((size_t) ncol + 1, sizeof(zt_reduce_col));
  const int *fn = INTEGER_RO(fns);
  for (int k = 0; k < ncol; k++) {
    SEXP x = VECTOR_ELT(xs, k);
    if (fn[k] < 0 || fn[k] > (int) ZT_FN_LAST) Rf_error("zt_reduce: unknown statistic %d", fn[k]);
    zt_fn f = (zt_fn) fn[k];
    int kind = ZT_KIND_INT32;
    const void *data = NULL;
    // count never reads x, and first and last without na.rm do not.
    int needs_x = !(f == ZT_FN_COUNT ||
                    ((f == ZT_FN_FIRST || f == ZT_FN_LAST) && LOGICAL_RO(narm)[k] != TRUE));
    if (needs_x || !Rf_isNull(x)) {
      switch (TYPEOF(x)) {
      case INTSXP: kind = ZT_KIND_INT32; data = INTEGER_RO(x); break;
      case LGLSXP: kind = ZT_KIND_LGL; data = LOGICAL_RO(x); break;
      case REALSXP: kind = ZT_KIND_F64; data = REAL_RO(x); break;
      default: Rf_error("zt_reduce: column %d is not integer, logical or double", k + 1);
      }
      if (XLENGTH(x) != nl) Rf_error("zt_reduce: column %d is not one per row", k + 1);
    }
    SEXPTYPE otype;
    switch (f) {
    case ZT_FN_SUM:
    case ZT_FN_PROD:
    case ZT_FN_MEAN: otype = REALSXP; break;
    case ZT_FN_MIN:
    case ZT_FN_MAX: otype = kind == ZT_KIND_F64 ? REALSXP : INTSXP; break;
    default: otype = INTSXP; break;
    }
    SEXP o = Rf_allocVector(otype, ng);
    SET_VECTOR_ELT(out, k, o);
    int a, a2, cn, fl;
    zt_reduce_scratch(f, kind, &a, &a2, &cn, &fl);
    zt_reduce_col *c = &cols[k];
    c->fn = f;
    c->kind = kind;
    c->x = data;
    c->na_rm = LOGICAL_RO(narm)[k] == TRUE;
    c->nan_missing = LOGICAL_RO(nanmiss)[k] == TRUE;
    c->out = otype == REALSXP ? (void *) REAL(o) : (void *) INTEGER(o);
    c->acc = a ? (zt_acc *) R_alloc((size_t) ng + 1, sizeof(zt_acc)) : NULL;
    c->acc2 = a2 ? (zt_acc *) R_alloc((size_t) ng + 1, sizeof(zt_acc)) : NULL;
    c->cnt = cn ? (zt_row *) R_alloc((size_t) ng + 1, sizeof(zt_row)) : NULL;
    c->flag = fl ? (uint8_t *) R_alloc((size_t) ng + 1, 1) : NULL;
  }
  zt_reduce(ids, n, (zt_row) ng, cols, ncol);
  for (int k = 0; k < ncol; k++) {
    if (cols[k].fn != ZT_FN_FIRST && cols[k].fn != ZT_FN_LAST) continue;
    int *o = INTEGER(VECTOR_ELT(out, k));
    for (int g = 0; g < ng; g++) o[g] = o[g] < 0 ? NA_INTEGER : o[g] + 1;
  }
  UNPROTECT(1);
  return out;
}
