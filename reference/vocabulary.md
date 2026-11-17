# The expression vocabulary

Clauses of the bracket are written in a closed vocabulary of typed
functions: SQL's names, with R's spellings as synonyms. A function
outside it is a `zutable_type_error` at plan time; `r(expr, type)`
evaluates arbitrary R in the local executor, with its result type
declared and checked.

## Details

Where R and SQL differ the vocabulary chooses one rule, the same in
every engine: a double's `NA` is the missing value and `NaN` a value,
equal to itself and above every number; strings compare by bytes;
aggregates skip missing values and give `NA` over none; `int32`
arithmetic that overflows is an error;
[`paste0()`](https://rdrr.io/r/base/paste.html) gives `NA` when any part
is `NA`; [`ifelse()`](https://rdrr.io/r/base/ifelse.html) gives `NA` for
an `NA` condition, while `case()` skips it;
[`substr()`](https://rdrr.io/r/base/substr.html) takes R's start and
stop. A literal takes the type of its context when it is exactly
representable there, so `qty + 1` is `int32` and `day >= "2026-01-01"`
compares dates.

## Functions

Every function allowed in a clause, with the argument and result types
it takes. T is one type throughout a signature.

- `+`:

  Arithmetic. Types: (int32, int32) -\> int32; (float64, float64) -\>
  float64; (int32, float64) -\> float64; (float64, int32) -\> float64;
  (date, int32) -\> date; (int32, date) -\> date.

- `-`:

  Arithmetic. Types: (int32, int32) -\> int32; (float64, float64) -\>
  float64; (int32, float64) -\> float64; (float64, int32) -\> float64;
  (date, int32) -\> date; (date, date) -\> int32; (int32) -\> int32;
  (float64) -\> float64.

- `*`:

  Arithmetic. Types: (int32, int32) -\> int32; (float64, float64) -\>
  float64; (int32, float64) -\> float64; (float64, int32) -\> float64.

- `/`:

  Arithmetic; always float64. Types: (int32, int32) -\> float64;
  (float64, float64) -\> float64; (int32, float64) -\> float64;
  (float64, int32) -\> float64.

- `%/%`:

  Floor division; a zero int32 divisor gives NA. Types: (int32, int32)
  -\> int32; (float64, float64) -\> float64; (int32, float64) -\>
  float64; (float64, int32) -\> float64.

- `%%`:

  Modulo with the divisor's sign. Types: (int32, int32) -\> int32;
  (float64, float64) -\> float64; (int32, float64) -\> float64;
  (float64, int32) -\> float64.

- `^`:

  Power, as R's ^; always float64. Types: (int32, int32) -\> float64;
  (float64, float64) -\> float64; (int32, float64) -\> float64;
  (float64, int32) -\> float64.

- `abs`:

  Types: (int32) -\> int32; (float64) -\> float64.

- `sqrt`:

  Types: (int32) -\> float64; (float64) -\> float64.

- `exp`:

  Types: (int32) -\> float64; (float64) -\> float64.

- `log`:

  Natural logarithm. Types: (int32) -\> float64; (float64) -\> float64.

- `round`:

  Rounding half to even, as R. Types: (int32) -\> int32; (float64) -\>
  float64; (int32, int32) -\> int32; (float64, int32) -\> float64.

- `floor`:

  Types: (int32) -\> int32; (float64) -\> float64.

- `ceiling`:

  Types: (int32) -\> int32; (float64) -\> float64.

- `==`:

  Comparison. Types: (T, T) -\> bool; (int32, float64) -\> bool;
  (float64, int32) -\> bool; (timestamp, timestamp) -\> bool.

- `!=`:

  Comparison. Types: (T, T) -\> bool; (int32, float64) -\> bool;
  (float64, int32) -\> bool; (timestamp, timestamp) -\> bool.

- `<`:

  Comparison. Types: (T, T) -\> bool; (int32, float64) -\> bool;
  (float64, int32) -\> bool; (timestamp, timestamp) -\> bool.

- `<=`:

  Comparison. Types: (T, T) -\> bool; (int32, float64) -\> bool;
  (float64, int32) -\> bool; (timestamp, timestamp) -\> bool.

- `>`:

  Comparison. Types: (T, T) -\> bool; (int32, float64) -\> bool;
  (float64, int32) -\> bool; (timestamp, timestamp) -\> bool.

- `>=`:

  Comparison. Types: (T, T) -\> bool; (int32, float64) -\> bool;
  (float64, int32) -\> bool; (timestamp, timestamp) -\> bool.

- `between`:

  Lo \<= x \<= hi. Types: (T, T, T) -\> bool; (int32, float64, float64)
  -\> bool; (float64, int32, int32) -\> bool.

- `&`:

  Three-valued and. Types: (bool, bool) -\> bool.

- `|`:

  Three-valued or. Types: (bool, bool) -\> bool.

- `!`:

  Not. Types: (bool) -\> bool.

- `is.na`:

  Missing; NaN is a value, not missing. Also spelt `is_null`. Types:
  (bool) -\> bool; (int32) -\> bool; (float64) -\> bool; (string) -\>
  bool; (date) -\> bool; (timestamp) -\> bool; (enum) -\> bool; (binary)
  -\> bool; (list) -\> bool; (struct) -\> bool; (int64) -\> bool;
  (decimal) -\> bool.

- `coalesce`:

  The first value that is not missing. Types: (T, ...) -\> T.

- `ifelse`:

  An NA condition gives NA, as in R. Types: (bool, T, T) -\> T.

- `nchar`:

  Number of characters. Also spelt `length`. Types: (string) -\> int32.

- `upper`:

  Also spelt `toupper`. Types: (string) -\> string.

- `lower`:

  Also spelt `tolower`. Types: (string) -\> string.

- `substr`:

  Characters start to stop, as R's substr(). Types: (string, int32,
  int32) -\> string.

- `concat`:

  Joins strings; NA if any is NA. Also spelt `paste0`. Types: (string,
  ...) -\> string.

- `trim`:

  Removes spaces, tabs and line breaks at both ends. Also spelt
  `trimws`. Types: (string) -\> string.

- `like`:

  SQL LIKE: % any run, \_ one character. Types: (string, string) -\>
  bool.

- `starts_with`:

  Also spelt `startsWith`. Types: (string, string) -\> bool.

- `year`:

  Types: (date) -\> int32; (timestamp) -\> int32.

- `month`:

  Types: (date) -\> int32; (timestamp) -\> int32.

- `day`:

  Types: (date) -\> int32; (timestamp) -\> int32.

- `date_trunc`:

  The start of the year, quarter, month, week (Monday), day, hour,
  minute or second. Types: (string, date) -\> arg2; (string, timestamp)
  -\> arg2.

- `count`:

  Aggregate. Rows, or values that are not missing. Types: () -\> int32;
  (bool) -\> int32; (int32) -\> int32; (float64) -\> int32; (string) -\>
  int32; (date) -\> int32; (timestamp) -\> int32; (enum) -\> int32;
  (binary) -\> int32; (list) -\> int32; (struct) -\> int32; (int64) -\>
  int32; (decimal) -\> int32.

- `count_distinct`:

  Aggregate. Distinct values that are not missing. Also spelt
  `n_distinct`. Types: (bool) -\> int32; (int32) -\> int32; (float64)
  -\> int32; (string) -\> int32; (date) -\> int32; (timestamp) -\>
  int32; (enum) -\> int32.

- `sum`:

  Aggregate. Always float64. Types: (int32) -\> float64; (float64) -\>
  float64.

- `mean`:

  Aggregate. Also spelt `avg`. Types: (int32) -\> float64; (float64) -\>
  float64.

- `min`:

  Aggregate. Types: (bool) -\> arg1; (int32) -\> arg1; (float64) -\>
  arg1; (string) -\> arg1; (date) -\> arg1; (timestamp) -\> arg1.

- `max`:

  Aggregate. Types: (bool) -\> arg1; (int32) -\> arg1; (float64) -\>
  arg1; (string) -\> arg1; (date) -\> arg1; (timestamp) -\> arg1.

- `first`:

  Aggregate. The first value, missing or not. Types: (T) -\> T.

- `last`:

  Aggregate. The last value, missing or not. Types: (T) -\> T.

- `any`:

  Aggregate. Types: (bool) -\> bool.

- `all`:

  Aggregate. Types: (bool) -\> bool.

- `%in%`:

  Membership in a set of constants; NA for a missing value.

- `case`:

  `condition ~ value` pairs and `.default`; an NA condition is skipped.

- `cast`:

  Conversion that errors on the first value it cannot represent.
