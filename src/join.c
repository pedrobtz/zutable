// grp_join(), grp_match() and join(): the R side of zutable/join.h. A thin
// translation (design-kernel section 4): fill both keys, choose the build
// side, call the header, wrap the pairs. Scratch comes from R_alloc, so an
// R error frees it.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <zutable.h>

void zt_fill_key(SEXP keys, SEXP i64, zt_column *cols, SEXP keep);

static zt_row zt_nrow(SEXP keys) {
  if (XLENGTH(keys) == 0) return 0;
  R_xlen_t n = XLENGTH(VECTOR_ELT(keys, 0));
  if (n > ZT_MAX_ROWS) Rf_error("zt_join: more than 2^31 - 1 rows");
  return (zt_row) n;
}

// Rows the caller says match nothing (a logical vector, or NULL): their
// class becomes -1. Rows with an equal key share the flag, so a whole
// class goes, never part of one.
static void zt_mask(SEXP mask, zt_row n, zt_row *cls) {
  if (Rf_isNull(mask)) return;
  const int *m = LOGICAL_RO(mask);
  for (zt_row i = 0; i < n; i++) if (m[i] == TRUE) cls[i] = -1;
}

// xkeys, ykeys: lists of key vectors of one native type per position (R
// converts each pair); i64: which are integer64. type: 0 inner, 1 left,
// 2 semi, 3 anti; multiple: 0 all, 1 first, 2 last, 3 error. xmask, ymask:
// NULL, or rows that match nothing (na_equal = FALSE).
//
// Returns list(x, y), 1-based, NA in y for an unmatched left row; list(x)
// for semi and anti; list(bad, count) when multiple is "error" and x row
// `bad` matches `count` rows; list(pairs) when there would be more than
// 2^31 - 1 pairs.
SEXP zt_join(SEXP xkeys, SEXP ykeys, SEXP i64, SEXP type, SEXP multiple,
             SEXP xmask, SEXP ymask) {
  int ncol = (int) XLENGTH(xkeys);
  if (ncol < 1 || XLENGTH(ykeys) != ncol) Rf_error("zt_join: keys of unequal width");
  zt_row nx = zt_nrow(xkeys), ny = zt_nrow(ykeys);
  int ty = Rf_asInteger(type), mu = Rf_asInteger(multiple);
  SEXP keep = PROTECT(Rf_allocVector(VECSXP, 2 * ncol));
  SEXP keepx = PROTECT(Rf_allocVector(VECSXP, ncol));
  SEXP keepy = PROTECT(Rf_allocVector(VECSXP, ncol));
  SET_VECTOR_ELT(keep, 0, keepx);
  SET_VECTOR_ELT(keep, 1, keepy);
  zt_column *cx = (zt_column *) R_alloc((size_t) ncol, sizeof(zt_column));
  zt_column *cy = (zt_column *) R_alloc((size_t) ncol, sizeof(zt_column));
  zt_fill_key(xkeys, i64, cx, keepx);
  zt_fill_key(ykeys, i64, cy, keepy);
  zt_key kx = {cx, ncol}, ky = {cy, ncol};

  uint64_t *hx = (uint64_t *) R_alloc((size_t) nx + 1, sizeof(uint64_t));
  uint64_t *hy = (uint64_t *) R_alloc((size_t) ny + 1, sizeof(uint64_t));
  zt_key_hash(&kx, nx, hx);
  zt_key_hash(&ky, ny, hy);
  zt_row *xcls = (zt_row *) R_alloc((size_t) nx + 1, sizeof(zt_row));
  zt_row *ycls = (zt_row *) R_alloc((size_t) ny + 1, sizeof(zt_row));

  // The smaller side is built on (design-kernel 4); the classes, and so
  // the pairs, are the same either way (D23).
  int build_x = nx < ny;
  zt_row nb = build_x ? nx : ny;
  uint64_t cap = zt_table_capacity(nb);
  zt_table t;
  zt_table_init(&t, R_alloc(zt_table_bytes(cap), 1), cap);
  zt_row *first = (zt_row *) R_alloc((size_t) nb + 1, sizeof(zt_row));
  zt_row ng;
  if (build_x) {
    ng = zt_join_build(&kx, hx, nx, &t, xcls, first);
    zt_join_probe(&t, &kx, xcls, &ky, hy, ny, ycls);
  } else {
    ng = zt_join_build(&ky, hy, ny, &t, ycls, first);
    zt_join_probe(&t, &ky, ycls, &kx, hx, nx, xcls);
  }
  zt_mask(xmask, nx, xcls);
  zt_mask(ymask, ny, ycls);
  zt_row *size = (zt_row *) R_alloc((size_t) ng + 1, sizeof(zt_row));
  zt_row *start = (zt_row *) R_alloc((size_t) ng + 1, sizeof(zt_row));
  zt_row *order = (zt_row *) R_alloc((size_t) ny + 1, sizeof(zt_row));
  zt_join_bucket(ny, ng, ycls, size, start, order);

  SEXP out;
  if (ty >= 2) {
    zt_row *rows = (zt_row *) R_alloc((size_t) nx + 1, sizeof(zt_row));
    zt_row k = zt_join_filter(nx, xcls, size, ty == 3, rows);
    SEXP xs = PROTECT(Rf_allocVector(INTSXP, k));
    for (zt_row r = 0; r < k; r++) INTEGER(xs)[r] = rows[r] + 1;
    const char *names[] = {"x", ""};
    out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, xs);
    UNPROTECT(5);
    return out;
  }
  zt_row bad;
  int64_t total = zt_join_count(nx, xcls, size, (zt_join_type) ty, (zt_multiple) mu, &bad);
  if (bad >= 0) {
    const char *names[] = {"bad", "count", ""};
    out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_ScalarInteger(bad + 1));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(size[xcls[bad]]));
    UNPROTECT(4);
    return out;
  }
  if (total > ZT_MAX_ROWS) {
    const char *names[] = {"pairs", ""};
    out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_ScalarReal((double) total));
    UNPROTECT(4);
    return out;
  }
  SEXP xs = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) total));
  SEXP ys = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) total));
  int *ox = INTEGER(xs), *oy = INTEGER(ys);
  zt_join_fill(nx, xcls, size, start, order, (zt_join_type) ty, (zt_multiple) mu, ox, oy);
  for (int64_t r = 0; r < total; r++) {
    ox[r]++;
    oy[r] = oy[r] < 0 ? NA_INTEGER : oy[r] + 1;
  }
  const char *names[] = {"x", "y", ""};
  out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, xs);
  SET_VECTOR_ELT(out, 1, ys);
  UNPROTECT(6);
  return out;
}
