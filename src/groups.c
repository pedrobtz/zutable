// grp(): the R side of zutable/groups.h. A thin translation, as the kernel
// design says (section 4): validate, call the header, wrap the results.
// Scratch comes from R_alloc, so an R error frees it.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <Rversion.h>
#include <zutable.h>

// Rf_error here is unreachable from R (#68): zt_key_columns() checks the
// kinds, one length and the row limit before grp() and the executor call;
// the checks stand for an internal caller (test-native-guards.R).

// Whether a CHARSXP is all ASCII. Rf_charIsASCII() is API from R 4.5;
// before it, the bytes say the same as R's flag.
static int zt_char_is_ascii(SEXP s) {
#if R_VERSION >= R_Version(4, 5, 0)
  return Rf_charIsASCII(s);
#else
  const unsigned char *p = (const unsigned char *) CHAR(s);
  for (int i = 0, n = LENGTH(s); i < n; i++) {
    if (p[i] > 0x7F) return 0;
  }
  return 1;
#endif
}

// A character column's pointers, translated to UTF-8 unless every element
// is ASCII or marked UTF-8 (design-kernel 6.1), so equal text is an equal
// pointer. The test is the mark, not Rf_charIsUTF8(), which also passes an
// unmarked (native) string in a UTF-8 locale, a CHARSXP other than its
// marked twin's (#50). The R layer refuses "bytes" first (zt_check_text()).
// Translated vectors are kept alive in `keep`.
static const void *const *zt_str_ptrs(SEXP x, SEXP keep, int slot) {
  R_xlen_t n = XLENGTH(x);
  int need = 0;
  for (R_xlen_t i = 0; i < n; i++) {
    SEXP s = STRING_ELT(x, i);
    if (s != NA_STRING && Rf_getCharCE(s) != CE_UTF8 && !zt_char_is_ascii(s)) {
      need = 1;
      break;
    }
  }
  if (need) {
    SEXP y = Rf_allocVector(STRSXP, n);
    SET_VECTOR_ELT(keep, slot, y);
    for (R_xlen_t i = 0; i < n; i++) {
      SEXP s = STRING_ELT(x, i);
      SET_STRING_ELT(y, i, s == NA_STRING ? NA_STRING :
                     Rf_mkCharCE(Rf_translateCharUTF8(s), CE_UTF8));
    }
    x = y;
  }
  return (const void *const *) STRING_PTR_RO(x);
}

// The 1-based index of x's first "bytes"-encoded element, or 0: such a
// string has no text to compare, and the R layer refuses it as a
// zutable_value_error (zt_check_text()) before the kernel translates.
SEXP zt_str_bytes_at(SEXP x) {
  if (TYPEOF(x) != STRSXP) return Rf_ScalarReal(0);
  R_xlen_t n = XLENGTH(x);
  for (R_xlen_t i = 0; i < n; i++) {
    SEXP s = STRING_ELT(x, i);
    if (s != NA_STRING && Rf_getCharCE(s) == CE_BYTES) return Rf_ScalarReal((double) i + 1);
  }
  return Rf_ScalarReal(0);
}

// Every key column holds n rows (#85), as zt_key_order() checks: the R
// layer checks the lengths first (zt_key_columns()), so this is for an
// internal caller. Also used by join.c.
void zt_check_key_length(SEXP keys, R_xlen_t n, const char *who) {
  for (R_xlen_t c = 0; c < XLENGTH(keys); c++) {
    if (XLENGTH(VECTOR_ELT(keys, c)) != n) Rf_error("%s: key columns differ in length", who);
  }
}

// Fill a zt_key from a list of key vectors, already checked in R: integer,
// logical, double (i64 when `i64[c]`), character, or a list of raw. Also
// used by join.c.
void zt_fill_key(SEXP keys, SEXP i64, zt_column *cols, SEXP keep) {
  int ncol = (int) XLENGTH(keys);
  for (int c = 0; c < ncol; c++) {
    SEXP x = VECTOR_ELT(keys, c);
    switch (TYPEOF(x)) {
    case INTSXP: cols[c].kind = ZT_KIND_INT32; cols[c].data = INTEGER_RO(x); break;
    case LGLSXP: cols[c].kind = ZT_KIND_LGL; cols[c].data = LOGICAL_RO(x); break;
    case REALSXP:
      cols[c].kind = LOGICAL(i64)[c] ? ZT_KIND_I64 : ZT_KIND_F64;
      cols[c].data = REAL_RO(x);
      break;
    case STRSXP: cols[c].kind = ZT_KIND_STR; cols[c].data = zt_str_ptrs(x, keep, c); break;
    case VECSXP: {
      R_xlen_t n = XLENGTH(x);
      zt_bytes *b = (zt_bytes *) R_alloc((size_t) n, sizeof(zt_bytes));
      for (R_xlen_t i = 0; i < n; i++) {
        SEXP e = VECTOR_ELT(x, i);
        if (TYPEOF(e) == RAWSXP) { b[i].data = RAW(e); b[i].len = (int32_t) XLENGTH(e); }
        else { b[i].data = NULL; b[i].len = -1; }
      }
      cols[c].kind = ZT_KIND_BYTES;
      cols[c].data = b;
      break;
    }
    default: Rf_error("zt_grp: unsupported key column");
    }
  }
}

// Group identifiers (1-based, first appearance), the first row of each
// group, sizes, starts (1-based, into order) and the order putting each
// group's rows together; plus the partition bits used, for the tests.
// force_bits: NA, or the partition bits to use (a test hook).
SEXP zt_grp(SEXP keys, SEXP i64, SEXP nrows, SEXP force_bits) {
  int ncol = (int) XLENGTH(keys);
  double nd = REAL(nrows)[0];
  if (nd > ZT_MAX_ROWS) Rf_error("zt_grp: more than 2^31 - 1 rows");
  zt_row n = (zt_row) nd;
  zt_check_key_length(keys, n, "zt_grp");
  SEXP keep = PROTECT(Rf_allocVector(VECSXP, ncol > 0 ? ncol : 1));
  zt_column *cols = (zt_column *) R_alloc(ncol > 0 ? (size_t) ncol : 1, sizeof(zt_column));
  zt_fill_key(keys, i64, cols, keep);
  zt_key k = {cols, ncol};

  uint64_t *h = (uint64_t *) R_alloc(n > 0 ? (size_t) n : 1, sizeof(uint64_t));
  zt_key_hash(&k, n, h);
  uint64_t sample[2 * ZT_SAMPLE];
  int bits = zt_partition_bits(zt_estimate_distinct(h, n, sample));
  // A test hook: force the partitioned path (or none) at any size.
  int fb = Rf_asInteger(force_bits);
  if (fb != NA_INTEGER && fb >= 0 && fb <= ZT_MAX_BITS) bits = fb;

  SEXP id = PROTECT(Rf_allocVector(INTSXP, n));
  zt_row *ids = INTEGER(id);
  zt_row *first = (zt_row *) R_alloc(n > 0 ? (size_t) n : 1, sizeof(zt_row));
  zt_row ng = 0;
  // Tables start from the estimate of distinct keys, with headroom, and
  // double as they fill (design-kernel section 4); a table sized for every
  // row would miss cache on every probe for a key with few values.
  double est = zt_estimate_distinct(h, n, sample);
  if (bits == 0) {
    uint64_t cap = zt_table_capacity((zt_row) (est * 2 < n ? est * 2 : n));
    zt_table t;
    zt_table_init(&t, R_alloc(zt_table_bytes(cap), 1), cap);
    zt_row done = 0;
    for (;;) {
      done += zt_groups_one(&k, h, NULL, done, n - done, &t, ids, first, 0, &ng);
      if (done >= n) break;
      zt_table bigger;
      uint64_t cap2 = 2 * ((uint64_t) t.mask + 1);
      zt_table_init(&bigger, R_alloc(zt_table_bytes(cap2), 1), cap2);
      zt_table_rehash(&t, &bigger, h);
      t = bigger;
    }
  } else {
    int np = 1 << bits;
    zt_row *start = (zt_row *) R_alloc((size_t) np + 1, sizeof(zt_row));
    zt_row *perm = (zt_row *) R_alloc((size_t) n, sizeof(zt_row));
    zt_partition(h, n, bits, start, perm);
    // Per partition: its share of the estimate, with headroom, growing as
    // needed; one buffer, reused, as large as the largest table needed.
    uint64_t cap0 = zt_table_capacity((zt_row) (est / np * 2 + 16));
    uint64_t have = cap0;
    void *mem = R_alloc(zt_table_bytes(have), 1);
    for (int p = 0; p < np; p++) {
      zt_row m = start[p + 1] - start[p];
      if (m == 0) continue;
      zt_table t;
      uint64_t cap = cap0;
      zt_table_init(&t, mem, cap);
      zt_row g0 = ng, png = 0, done = 0;
      for (;;) {
        done += zt_groups_one(&k, h, perm + start[p] + done, 0, m - done, &t,
                              ids, first, g0, &png);
        if (done >= m) break;
        uint64_t cap2 = 2 * cap;
        void *mem2 = R_alloc(zt_table_bytes(cap2), 1);
        zt_table bigger;
        zt_table_init(&bigger, mem2, cap2);
        zt_table_rehash(&t, &bigger, h);
        t = bigger;
        cap = cap2;
        if (cap2 > have) { mem = mem2; have = cap2; cap0 = cap2; }
      }
      ng += png;
    }
    size_t words = ((size_t) n + 63) / 64;
    uint64_t *bitmap = (uint64_t *) R_alloc(words, sizeof(uint64_t));
    zt_row *word_rank = (zt_row *) R_alloc(words, sizeof(zt_row));
    zt_row *newid = (zt_row *) R_alloc(ng > 0 ? (size_t) ng : 1, sizeof(zt_row));
    zt_groups_relabel(n, ng, ids, first, bitmap, word_rank, newid);
  }

  SEXP sizes = PROTECT(Rf_allocVector(INTSXP, ng));
  SEXP starts = PROTECT(Rf_allocVector(INTSXP, ng));
  SEXP order = PROTECT(Rf_allocVector(INTSXP, n));
  SEXP firsts = PROTECT(Rf_allocVector(INTSXP, ng));
  zt_groups_order(n, ng, ids, INTEGER(sizes), INTEGER(starts), INTEGER(order));
  for (zt_row i = 0; i < n; i++) { ids[i]++; INTEGER(order)[i]++; }
  for (zt_row g = 0; g < ng; g++) { INTEGER(starts)[g]++; INTEGER(firsts)[g] = first[g] + 1; }

  const char *names[] = {"id", "n", "sizes", "starts", "order", "first", "bits", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, id);
  SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ng));
  SET_VECTOR_ELT(out, 2, sizes);
  SET_VECTOR_ELT(out, 3, starts);
  SET_VECTOR_ELT(out, 4, order);
  SET_VECTOR_ELT(out, 5, firsts);
  SET_VECTOR_ELT(out, 6, Rf_ScalarInteger(bits));
  UNPROTECT(7);
  return out;
}

// grp(sort = TRUE) by sorting every row (design-kernel 4.2, axis O; D44):
// the same list as zt_grp, already in key order, or NULL when the keys
// should be hashed instead: not fixed width, too few distinct keys for the
// sort to pay (unless `force` is TRUE, a test hook), or an NA beside a NaN
// in a run the order ties.
SEXP zt_grp_sort(SEXP keys, SEXP i64, SEXP nrows, SEXP force) {
  int ncol = (int) XLENGTH(keys);
  double nd = REAL(nrows)[0];
  if (nd > ZT_MAX_ROWS) Rf_error("zt_grp_sort: more than 2^31 - 1 rows");
  zt_row n = (zt_row) nd;
  zt_check_key_length(keys, n, "zt_grp_sort");
  if (ncol == 0 || n < 2) return R_NilValue;
  SEXP keep = PROTECT(Rf_allocVector(VECSXP, ncol));
  zt_column *cols = (zt_column *) R_alloc((size_t) ncol, sizeof(zt_column));
  zt_fill_key(keys, i64, cols, keep);
  zt_key k = {cols, ncol};
  if (!zt_key_fixed_width(&k) ||
      (LOGICAL(force)[0] != TRUE && !zt_groups_sort_pays(&k, n))) {
    UNPROTECT(1);
    return R_NilValue;
  }
  zt_sort_col *sc = (zt_sort_col *) R_alloc((size_t) ncol, sizeof(zt_sort_col));
  zt_codebook *cb = (zt_codebook *) R_alloc((size_t) ncol, sizeof(zt_codebook));
  void *mem = R_alloc(zt_sort_scratch_bytes(n), 1);
  zt_row *first = (zt_row *) R_alloc((size_t) n, sizeof(zt_row));
  zt_row *start = (zt_row *) R_alloc((size_t) n, sizeof(zt_row));
  SEXP id = PROTECT(Rf_allocVector(INTSXP, n));
  SEXP order = PROTECT(Rf_allocVector(INTSXP, n));
  zt_row *ids = INTEGER(id), *ord = INTEGER(order);
  zt_row ng = zt_groups_by_sort(&k, n, sc, cb, ord, ids, first, start, mem);
  if (ng < 0) {
    UNPROTECT(3);
    return R_NilValue;
  }
  SEXP sizes = PROTECT(Rf_allocVector(INTSXP, ng));
  SEXP starts = PROTECT(Rf_allocVector(INTSXP, ng));
  SEXP firsts = PROTECT(Rf_allocVector(INTSXP, ng));
  int *sz = INTEGER(sizes), *st = INTEGER(starts), *fi = INTEGER(firsts);
  for (zt_row g = 0; g < ng; g++) {
    sz[g] = (g + 1 < ng ? start[g + 1] : n) - start[g];
    st[g] = start[g] + 1;
    fi[g] = first[g] + 1;
  }
  for (zt_row i = 0; i < n; i++) { ids[i]++; ord[i]++; }

  const char *names[] = {"id", "n", "sizes", "starts", "order", "first", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, id);
  SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ng));
  SET_VECTOR_ELT(out, 2, sizes);
  SET_VECTOR_ELT(out, 3, starts);
  SET_VECTOR_ELT(out, 4, order);
  SET_VECTOR_ELT(out, 5, firsts);
  UNPROTECT(7);
  return out;
}
