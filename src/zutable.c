#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

// Native routines are registered here as stages add them. Symbols are
// hidden (Makevars) and only R_init_zutable is exported (design §3, R3).
static const R_CallMethodDef call_methods[] = {
  {NULL, NULL, 0}
};

void attribute_visible R_init_zutable(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
