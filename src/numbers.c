// Text and doubles, exactly (design D49): zufast's correctly rounded
// parser (fast_float) and shortest round-trip formatter (Ryu). R's own
// R_strtod is not correctly rounded on every platform (macOS arm64 reads
// "1.7976931348623157e+308" as Inf), so cast() cannot rest on as.double().
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <string.h>
#include <zufast/number.h>
#include <zufast/datetime.h>

// Rf_error here is unreachable from R (#68): R/cast.R passes a character
// vector to zt_parse_f64 and a double one to zt_format_f64; the checks
// stand for an internal caller (test-native-guards.R).

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

// Each day count from 1970-01-01 as its ISO 8601 date (#58): YYYY-MM-DD for
// years 0000 to 9999, otherwise the expanded form with a sign and at least
// six digits. NA, a non-finite value or a count outside int32 gives NA;
// R/cast.R passes whole days.
SEXP zt_format_date_days(SEXP x) {
  if (TYPEOF(x) != REALSXP) Rf_error("zt_format_date_days: a double vector is required");
  R_xlen_t n = XLENGTH(x);
  const double *px = REAL(x);
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
  char buf[32];
  for (R_xlen_t i = 0; i < n; i++) {
    double v = px[i];
    if (!R_FINITE(v) || v < -2147483648.0 || v > 2147483647.0 || v != (double) (int32_t) v) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }
    size_t len = zuf_format_date(buf, sizeof buf, (int32_t) v);
    // zufast 0.1.0 pads an expanded year to five digits and 0.1.1 to six;
    // pad here so the text does not depend on the installed zufast.
    if (len > 0 && (buf[0] == '+' || buf[0] == '-')) {
      const char *dash = memchr(buf + 1, '-', len - 1);
      size_t digits = dash ? (size_t) (dash - buf) - 1 : 0;
      if (digits > 0 && digits < 6 && len + (6 - digits) < sizeof buf) {
        size_t pad = 6 - digits;
        memmove(buf + 1 + pad, buf + 1, len - 1);
        memset(buf + 1, '0', pad);
        len += pad;
      }
    }
    SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int) len, CE_UTF8));
  }
  UNPROTECT(1);
  return out;
}
