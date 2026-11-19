// A sibling's use of zutable's kernel (design-kernel 8, R10.4): LinkingTo
// for the header, nothing else. Each entry point is one kernel operation,
// written the way a consumer would, with its scratch from R_alloc().
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <zutable.h>

#if ZUTABLE_VERSION_MAJOR != 0
#error "zutabletest is written against zutable 0.x"
#endif

SEXP zt_consume_version_c(void);

// Group ids in first appearance, 1-based, and the number of groups.
static SEXP zt_consume_groups_c(SEXP x) {
  zt_row n = (zt_row) XLENGTH(x);
  zt_column col = {TYPEOF(x) == INTSXP ? ZT_KIND_INT32 : ZT_KIND_F64, DATAPTR_RO(x)};
  zt_key k = {&col, 1};
  uint64_t *h = (uint64_t *) R_alloc((size_t) n + 1, sizeof(uint64_t));
  zt_key_hash(&k, n, h);
  uint64_t cap = zt_table_capacity(n);
  zt_table t;
  zt_table_init(&t, R_alloc(zt_table_bytes(cap), 1), cap);
  SEXP id = PROTECT(Rf_allocVector(INTSXP, n));
  zt_row *ids = INTEGER(id);
  zt_row *first = (zt_row *) R_alloc((size_t) n + 1, sizeof(zt_row));
  zt_row ng = 0;
  zt_groups_one(&k, h, NULL, 0, n, &t, ids, first, 0, &ng);
  for (zt_row i = 0; i < n; i++) ids[i]++;
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, id);
  SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ng));
  UNPROTECT(2);
  return out;
}

// The stable order of a double vector, 1-based; na_last 1, 0, or -1 to
// drop missing values.
static SEXP zt_consume_order_c(SEXP x, SEXP decreasing, SEXP na_last) {
  zt_row n = (zt_row) XLENGTH(x);
  zt_sort_col col = {ZT_KIND_F64, REAL_RO(x), LOGICAL_RO(decreasing)[0] == TRUE};
  zt_codebook cb;
  zt_row *perm = (zt_row *) R_alloc((size_t) n + 1, sizeof(zt_row));
  void *mem = R_alloc(zt_sort_scratch_bytes(n), 1);
  zt_row m = zt_order(&col, 1, n, INTEGER_RO(na_last)[0], &cb, perm, mem);
  SEXP out = PROTECT(Rf_allocVector(INTSXP, m));
  for (zt_row j = 0; j < m; j++) INTEGER(out)[j] = perm[j] + 1;
  UNPROTECT(1);
  return out;
}

// The inner join of two integer keys, every pair, 1-based, in x order then
// y order.
static SEXP zt_consume_join_c(SEXP x, SEXP y) {
  zt_row nx = (zt_row) XLENGTH(x), ny = (zt_row) XLENGTH(y);
  zt_column xc = {ZT_KIND_INT32, INTEGER_RO(x)}, yc = {ZT_KIND_INT32, INTEGER_RO(y)};
  zt_key kx = {&xc, 1}, ky = {&yc, 1};
  uint64_t *hx = (uint64_t *) R_alloc((size_t) nx + 1, sizeof(uint64_t));
  uint64_t *hy = (uint64_t *) R_alloc((size_t) ny + 1, sizeof(uint64_t));
  zt_key_hash(&kx, nx, hx);
  zt_key_hash(&ky, ny, hy);
  uint64_t cap = zt_table_capacity(ny);
  zt_table t;
  zt_table_init(&t, R_alloc(zt_table_bytes(cap), 1), cap);
  zt_row *xcls = (zt_row *) R_alloc((size_t) nx + 1, sizeof(zt_row));
  zt_row *ycls = (zt_row *) R_alloc((size_t) ny + 1, sizeof(zt_row));
  zt_row *first = (zt_row *) R_alloc((size_t) ny + 1, sizeof(zt_row));
  zt_row ng = zt_join_build(&ky, hy, ny, &t, ycls, first);
  zt_join_probe(&t, &ky, ycls, &kx, hx, nx, xcls);
  zt_row *size = (zt_row *) R_alloc((size_t) ng + 1, sizeof(zt_row));
  zt_row *start = (zt_row *) R_alloc((size_t) ng + 1, sizeof(zt_row));
  zt_row *order = (zt_row *) R_alloc((size_t) ny + 1, sizeof(zt_row));
  zt_join_bucket(ny, ng, ycls, size, start, order);
  zt_row bad;
  int64_t np = zt_join_count(nx, xcls, size, ZT_JOIN_INNER, ZT_MULTIPLE_ALL, &bad);
  if (np > ZT_MAX_ROWS) Rf_error("zt_consume_join: too many pairs");
  SEXP ox = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) np));
  SEXP oy = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) np));
  zt_join_fill(nx, xcls, size, start, order, ZT_JOIN_INNER, ZT_MULTIPLE_ALL,
               INTEGER(ox), INTEGER(oy));
  for (int64_t p = 0; p < np; p++) { INTEGER(ox)[p]++; INTEGER(oy)[p]++; }
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, ox);
  SET_VECTOR_ELT(out, 1, oy);
  UNPROTECT(3);
  return out;
}

// zt_acc is long double, which wants 16-byte alignment on x86_64, and
// R_alloc() promises 8: the header asks its caller to align (reduce.h).
static zt_acc *aligned_acc(zt_row ng) {
  size_t align = _Alignof(zt_acc);
  char *p = R_alloc((size_t) ng * sizeof(zt_acc) + sizeof(zt_acc) + align, 1);
  return (zt_acc *) (((uintptr_t) p + align - 1) & ~(uintptr_t) (align - 1));
}

// Group sums of x, missing values left out, NA for a group with none.
static SEXP zt_consume_sum_c(SEXP id, SEXP ng_, SEXP x) {
  zt_row n = (zt_row) XLENGTH(x), ng = (zt_row) Rf_asInteger(ng_);
  zt_row *ids = (zt_row *) R_alloc((size_t) n + 1, sizeof(zt_row));
  for (zt_row i = 0; i < n; i++) ids[i] = INTEGER_RO(id)[i] - 1;
  SEXP out = PROTECT(Rf_allocVector(REALSXP, ng));
  int a, a2, cn, fl;
  zt_reduce_scratch(ZT_FN_SUM, ZT_KIND_F64, &a, &a2, &cn, &fl);
  zt_reduce_col c = {ZT_FN_SUM, ZT_KIND_F64, REAL_RO(x), 1, 1, REAL(out),
                     a ? aligned_acc(ng) : NULL, a2 ? aligned_acc(ng) : NULL,
                     cn ? (zt_row *) R_alloc((size_t) ng + 1, sizeof(zt_row)) : NULL,
                     fl ? (uint8_t *) R_alloc((size_t) ng + 1, 1) : NULL};
  zt_reduce(ids, n, ng, &c, 1);
  UNPROTECT(1);
  return out;
}

static const R_CallMethodDef calls[] = {
  {"zt_consume_groups_c", (DL_FUNC) &zt_consume_groups_c, 1},
  {"zt_consume_order_c", (DL_FUNC) &zt_consume_order_c, 3},
  {"zt_consume_join_c", (DL_FUNC) &zt_consume_join_c, 2},
  {"zt_consume_sum_c", (DL_FUNC) &zt_consume_sum_c, 3},
  {"zt_consume_version_c", (DL_FUNC) &zt_consume_version_c, 0},
  {NULL, NULL, 0}
};

void R_init_zutabletest(DllInfo *dll) {
  R_registerRoutines(dll, NULL, calls, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
