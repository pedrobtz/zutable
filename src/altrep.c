// Sorted values (design-kernel 4.1, 6.3; D22): an ALTREP class wrapping a
// plain vector with what key_sort() knows of it, so base R's sort(),
// is.unsorted() and anyNA() answer without a pass. Base R exposes no API
// to create its own wrapper, hence this one, one class per type.
//
// data1 is the payload, a vector without attributes (the wrapper carries
// them); data2 an integer pair, private to the wrapper: the sortedness in
// R's codes (SORTED_INCR and the rest) and whether no element is missing.
//
// Lifetime and ownership: the wrapper owns its payload as an ordinary R
// reference, and nothing native outlives a call. A payload may be shared
// with another object (key_sort()'s caller's, or a duplicate's), so every
// writable access copies it first when it is shared, as base R's wrapper
// does, and drops the metadata: a write can make it false.
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>
#include <Rversion.h>

// ATTRIB() left the API in R 4.5, which added ANY_ATTRIB().
#if R_VERSION >= R_Version(4, 5, 0)
#define ZT_HAS_ATTRIB(x) ANY_ATTRIB(x)
#else
#define ZT_HAS_ATTRIB(x) (ATTRIB(x) != R_NilValue)
#endif

static R_altrep_class_t zt_sorted_int, zt_sorted_real, zt_sorted_lgl, zt_sorted_str;

static int zt_is_sorted_class(SEXP x) {
  return ALTREP(x) && (R_altrep_inherits(x, zt_sorted_int) ||
                       R_altrep_inherits(x, zt_sorted_real) ||
                       R_altrep_inherits(x, zt_sorted_lgl) ||
                       R_altrep_inherits(x, zt_sorted_str));
}

// The class for a payload of type t.
static R_altrep_class_t zt_class_for(int t) {
  switch (t) {
  case INTSXP: return zt_sorted_int;
  case REALSXP: return zt_sorted_real;
  case LGLSXP: return zt_sorted_lgl;
  case STRSXP: return zt_sorted_str;
  default: Rf_error("zutable: sorted values of an unsupported type");
  }
}

static SEXP zt_payload(SEXP x) { return R_altrep_data1(x); }
static int *zt_meta(SEXP x) { return INTEGER(R_altrep_data2(x)); }

// Before any write: forget the metadata, and take a payload of our own.
static SEXP zt_writable_payload(SEXP x) {
  int *m = zt_meta(x);
  m[0] = UNKNOWN_SORTEDNESS;
  m[1] = 0;
  SEXP p = zt_payload(x);
  if (MAYBE_SHARED(p)) {
    p = PROTECT(Rf_shallow_duplicate(p));
    R_set_altrep_data1(x, p);
    UNPROTECT(1);
  }
  return p;
}

// --- methods common to every type ------------------------------------------

static R_xlen_t zt_sorted_length(SEXP x) { return XLENGTH(zt_payload(x)); }

static Rboolean zt_sorted_inspect(SEXP x, int pre, int deep, int pvec,
                                  void (*inspect_subtree)(SEXP, int, int, int)) {
  int *m = zt_meta(x);
  if (m[0] == UNKNOWN_SORTEDNESS) {
    Rprintf(" zutable sorted values (sortedness unknown, no_na %d)\n", m[1]);
  } else {
    Rprintf(" zutable sorted values (sorted %d, no_na %d)\n", m[0], m[1]);
  }
  inspect_subtree(zt_payload(x), pre, deep, pvec);
  return TRUE;
}

// A copy shares the payload, which a write to either side then copies;
// a deep copy copies it now. The metadata is the copy's own.
static SEXP zt_sorted_duplicate(SEXP x, Rboolean deep) {
  SEXP p = PROTECT(deep ? Rf_duplicate(zt_payload(x)) : zt_payload(x));
  SEXP m = PROTECT(Rf_duplicate(R_altrep_data2(x)));
  SEXP y = R_new_altrep(zt_class_for(TYPEOF(p)), p, m);
  UNPROTECT(2);
  return y;
}

// Serialized as the payload and the metadata; attributes go with the
// wrapper, as for any ALTREP object.
static SEXP zt_sorted_serialized_state(SEXP x) {
  SEXP s = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(s, 0, zt_payload(x));
  SET_VECTOR_ELT(s, 1, R_altrep_data2(x));
  UNPROTECT(1);
  return s;
}

static SEXP zt_sorted_unserialize(SEXP cls, SEXP state) {
  (void) cls;
  SEXP p = VECTOR_ELT(state, 0);
  SEXP m = PROTECT(Rf_duplicate(VECTOR_ELT(state, 1)));
  SEXP y = R_new_altrep(zt_class_for(TYPEOF(p)), p, m);
  UNPROTECT(1);
  return y;
}

static int zt_sorted_is_sorted(SEXP x) { return zt_meta(x)[0]; }
static int zt_sorted_no_na(SEXP x) { return zt_meta(x)[1]; }

// --- per type ----------------------------------------------------------------

// No Get_region methods: base R asks for a region only when
// Dataptr_or_null returns NULL, which these never do, and R's default reads
// a region through Elt (native coverage, Stage 17).

static void *zt_int_dataptr(SEXP x, Rboolean writeable) {
  if (writeable) return INTEGER(zt_writable_payload(x));
  return (void *) INTEGER_RO(zt_payload(x));
}
static const void *zt_int_dataptr_or_null(SEXP x) { return INTEGER_RO(zt_payload(x)); }
static int zt_int_elt(SEXP x, R_xlen_t i) { return INTEGER_ELT(zt_payload(x), i); }

static void *zt_real_dataptr(SEXP x, Rboolean writeable) {
  if (writeable) return REAL(zt_writable_payload(x));
  return (void *) REAL_RO(zt_payload(x));
}
static const void *zt_real_dataptr_or_null(SEXP x) { return REAL_RO(zt_payload(x)); }
static double zt_real_elt(SEXP x, R_xlen_t i) { return REAL_ELT(zt_payload(x), i); }

static void *zt_lgl_dataptr(SEXP x, Rboolean writeable) {
  if (writeable) return LOGICAL(zt_writable_payload(x));
  return (void *) LOGICAL_RO(zt_payload(x));
}
static const void *zt_lgl_dataptr_or_null(SEXP x) { return LOGICAL_RO(zt_payload(x)); }
static int zt_lgl_elt(SEXP x, R_xlen_t i) { return LOGICAL_ELT(zt_payload(x), i); }

// Strings are written through Set_elt, under the write barrier; a
// writable pointer, which only R's internals take, drops the metadata too.
static void *zt_str_dataptr(SEXP x, Rboolean writeable) {
  if (writeable) return (void *) STRING_PTR_RO(zt_writable_payload(x));
  return (void *) STRING_PTR_RO(zt_payload(x));
}
static const void *zt_str_dataptr_or_null(SEXP x) { return STRING_PTR_RO(zt_payload(x)); }
static SEXP zt_str_elt(SEXP x, R_xlen_t i) { return STRING_ELT(zt_payload(x), i); }
static void zt_str_set_elt(SEXP x, R_xlen_t i, SEXP v) {
  SET_STRING_ELT(zt_writable_payload(x), i, v);
}

static void zt_common_methods(R_altrep_class_t c) {
  R_set_altrep_Length_method(c, zt_sorted_length);
  R_set_altrep_Inspect_method(c, zt_sorted_inspect);
  R_set_altrep_Duplicate_method(c, zt_sorted_duplicate);
  R_set_altrep_Serialized_state_method(c, zt_sorted_serialized_state);
  R_set_altrep_Unserialize_method(c, zt_sorted_unserialize);
}

void zt_init_altrep(DllInfo *dll) {
  zt_sorted_int = R_make_altinteger_class("zt_sorted_int", "zutable", dll);
  zt_common_methods(zt_sorted_int);
  R_set_altvec_Dataptr_method(zt_sorted_int, zt_int_dataptr);
  R_set_altvec_Dataptr_or_null_method(zt_sorted_int, zt_int_dataptr_or_null);
  R_set_altinteger_Elt_method(zt_sorted_int, zt_int_elt);
  R_set_altinteger_Is_sorted_method(zt_sorted_int, zt_sorted_is_sorted);
  R_set_altinteger_No_NA_method(zt_sorted_int, zt_sorted_no_na);

  zt_sorted_real = R_make_altreal_class("zt_sorted_real", "zutable", dll);
  zt_common_methods(zt_sorted_real);
  R_set_altvec_Dataptr_method(zt_sorted_real, zt_real_dataptr);
  R_set_altvec_Dataptr_or_null_method(zt_sorted_real, zt_real_dataptr_or_null);
  R_set_altreal_Elt_method(zt_sorted_real, zt_real_elt);
  R_set_altreal_Is_sorted_method(zt_sorted_real, zt_sorted_is_sorted);
  R_set_altreal_No_NA_method(zt_sorted_real, zt_sorted_no_na);

  zt_sorted_lgl = R_make_altlogical_class("zt_sorted_lgl", "zutable", dll);
  zt_common_methods(zt_sorted_lgl);
  R_set_altvec_Dataptr_method(zt_sorted_lgl, zt_lgl_dataptr);
  R_set_altvec_Dataptr_or_null_method(zt_sorted_lgl, zt_lgl_dataptr_or_null);
  R_set_altlogical_Elt_method(zt_sorted_lgl, zt_lgl_elt);
  R_set_altlogical_Is_sorted_method(zt_sorted_lgl, zt_sorted_is_sorted);
  R_set_altlogical_No_NA_method(zt_sorted_lgl, zt_sorted_no_na);

  zt_sorted_str = R_make_altstring_class("zt_sorted_str", "zutable", dll);
  zt_common_methods(zt_sorted_str);
  R_set_altvec_Dataptr_method(zt_sorted_str, zt_str_dataptr);
  R_set_altvec_Dataptr_or_null_method(zt_sorted_str, zt_str_dataptr_or_null);
  R_set_altstring_Elt_method(zt_sorted_str, zt_str_elt);
  R_set_altstring_Set_elt_method(zt_sorted_str, zt_str_set_elt);
  R_set_altstring_Is_sorted_method(zt_sorted_str, zt_sorted_is_sorted);
  R_set_altstring_No_NA_method(zt_sorted_str, zt_sorted_no_na);
}

// x wrapped, with sortedness `sorted` (R's codes) and `no_na`. x is a
// plain integer, double, logical or character vector without attributes.
SEXP zt_sorted_wrap(SEXP x, SEXP sorted, SEXP no_na) {
  if (ZT_HAS_ATTRIB(x)) Rf_error("zt_sorted_wrap: the payload has attributes");
  R_altrep_class_t c = zt_class_for(TYPEOF(x));
  int s = Rf_asInteger(sorted);
  if (!(s == UNKNOWN_SORTEDNESS || (s >= SORTED_DECR_NA_1ST && s <= SORTED_INCR_NA_1ST))) {
    Rf_error("zt_sorted_wrap: not a sortedness code");
  }
  SEXP m = PROTECT(Rf_allocVector(INTSXP, 2));
  INTEGER(m)[0] = s;
  INTEGER(m)[1] = Rf_asLogical(no_na) == TRUE;
  SEXP y = R_new_altrep(c, x, m);
  UNPROTECT(1);
  return y;
}

// The metadata, c(sorted, no_na), or NULL when x is not sorted values.
SEXP zt_sorted_meta(SEXP x) {
  if (!zt_is_sorted_class(x)) return R_NilValue;
  return Rf_duplicate(R_altrep_data2(x));
}
