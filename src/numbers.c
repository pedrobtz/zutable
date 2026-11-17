// Text and doubles, exactly (design D49): zufast's correctly rounded
// parser (fast_float) and shortest round-trip formatter (Ryu). R's own
// R_strtod is not correctly rounded on every platform (macOS arm64 reads
// "1.7976931348623157e+308" as Inf), so cast() cannot rest on as.double().
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <string.h>
#include <zufast/number.h>

// Parse each string as a double, the whole string or nothing: an optional
// sign, digits, a fraction and an exponent, or inf, infinity or nan. A
// string that is not one, or whose value overflows or underflows a double,
// gives NA; NA gives NA. Leading and trailing whitespace is the caller's to
// remove.
SEXP zt_parse_f64(SEXP x) {
  if (TYPEOF(x) != STRSXP) Rf_error("zt_parse_f64: a character vector is required");
  R_xlen_t n = XLENGTH(x);
  SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
  double *po = REAL(out);
  zuf_num_options opt = {ZUF_NUM_LEADING_PLUS, 0, 0};
  for (R_xlen_t i = 0; i < n; i++) {
    SEXP s = STRING_ELT(x, i);
    po[i] = NA_REAL;
    if (s == NA_STRING) continue;
    const char *first = CHAR(s);
    const char *last = first + LENGTH(s);
    double v;
    zuf_result r = zuf_parse_f64_opt(first, last, &v, &opt);
    if (r.status == ZUF_OK && r.ptr == last && first != last) po[i] = v;
  }
  UNPROTECT(1);
  return out;
}

// The shortest text that reads back as each double, in ECMAScript's
// Number::toString notation; non-finite values and NA are the caller's.
SEXP zt_format_f64(SEXP x) {
  if (TYPEOF(x) != REALSXP) Rf_error("zt_format_f64: a double vector is required");
  R_xlen_t n = XLENGTH(x);
  const double *px = REAL(x);
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
  char buf[ZUF_F64_MAX_CHARS];
  for (R_xlen_t i = 0; i < n; i++) {
    if (!R_FINITE(px[i])) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }
    size_t len = zuf_format_f64(buf, sizeof buf, px[i]);
    SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int) len, CE_UTF8));
  }
  UNPROTECT(1);
  return out;
}
