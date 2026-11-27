# Conditions. Every condition the package raises inherits from
# `zutable_error` and is raised from base R (design §13); tests assert on
# the class, never on the message.

zutable_error_kinds <- c(
  # The table layer (design §13).
  "syntax", "type", "schema", "value", "frozen", "engine",
  # The kernel (design-kernel §7).
  "length", "multiple", "levels", "fn", "collate"
)

# Build a condition of class `zutable_<kind>_error`. `...` become fields of
# the condition, for callers that want to inspect it.
zutable_condition <- function(kind, message, call = NULL, ...) {
  if (!is.character(kind) || length(kind) != 1L ||
      !kind %in% zutable_error_kinds) {
    stop("internal error: unknown zutable condition kind", call. = FALSE)
  }
  structure(
    class = c(paste0("zutable_", kind, "_error"), "zutable_error", "error",
              "condition"),
    list(message = message, call = call, ...)
  )
}

# Raise it. `call` defaults to the caller of the function that raises;
# a helper passes the exported function's call down instead (D62).
zutable_abort <- function(kind, message, ..., call = sys.call(-1L)) {
  stop(zutable_condition(kind, message, call = call, ...))
}

# The exported call whose plan is being evaluated (D62): zt_execute() and
# zt_run_update() set it, so a value error raised while evaluating an
# expression (a lossy cast, an overflow, an r() result) names the user's
# bracket, not a helper. NULL outside an evaluation.
zt_eval_call <- function() zt_state$eval_call

zt_with_eval_call <- function(call, code) {
  old <- zt_state$eval_call
  zt_state$eval_call <- call
  on.exit(zt_state$eval_call <- old, add = TRUE)
  force(code)
}
