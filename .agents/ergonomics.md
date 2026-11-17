# zutable: ergonomics tests

The fixed computations of design §19 (D15), written on the working
implementation of Stages 1 to 7 on 2026-11-17 in each candidate spelling,
and the choices recorded as D55. Each computation, in the spelling kept, is
a test against base R in `tests/testthat/test-ergonomics.R`.

## The computations

1. **VWAP and trade count per instrument**, over a date range, top five.

   ```r
   t[where  = day >= "2026-01-02",
     select = .(vwap = sum(px * qty) / sum(qty), n = count()),
     by     = id,
     order  = desc(vwap),
     limit  = 5]
   ```

2. **Each trade's share of its instrument's notional**, keeping every
   column (a window).

   ```r
   t[select = .(.all, share = px * qty / over(sum(px * qty), by = id))]
   ```

3. **Fill two placeholders in one pass**, sequentially, per group.

   ```r
   t[, {
     w <- px * qty
     notional := w
     share    := w / sum(w)
   }, by = id]
   ```

4. **Monthly totals** with a named key expression.

   ```r
   t[, .(total = sum(px * qty)), by = .(month = date_trunc("month", day))]
   ```

5. **A join, then an aggregate** over the joined table.

   ```r
   join(t, instruments, on = id)[, .(n = count()), by = sector]
   ```

6. **A column chosen by a variable**, in a function.

   ```r
   top_by <- function(t, col, n) t[order = desc(.col(col)), limit = n]
   ```

7. **Chained steps**: filter, compute, filter on the computed column.

   ```r
   t[qty > 0][, .(id, notional = px * qty)][notional > 1000]
   ```

8. **Distinct keys**, ordered.

   ```r
   t[, .(id), distinct = TRUE, order = id]
   ```

## The questions and the choices

| Question (§19) | Candidates | Kept, and why |
| --- | --- | --- |
| `.()` inside `select` | `.()`, `list()`, `c()`, a bare call | `.()`: short, data.table's, and `list()` would read as R's list in a vocabulary that has a `list` type |
| the star | `.all`, `everything()`, `*` | `.all`: `*` does not parse; `everything()` looks like a function the vocabulary lacks |
| `let()` and `expr()` | add them, or rely on blocks | blocks: computations 3 and the select block cover both, in order, with locals |
| a pipe form | verbs `filter()`/`mutate()`, or brackets | brackets: computation 7 chains steps already; a second spelling of every clause doubles the surface and its tests. Revisit with users |
| D28 against a `:=` block first | accept it, or keep the error | keep D28: the first position is always `where`, so a reader never guesses; the error shows the second-position spelling |
| a column named by a variable (§7.4) | `get()`, `..name`, `.data[[x]]`, `.col(x)` | `.col(x)`: resolved at plan time to a column, so types stay static; `..name` already means the caller's value, `get()` would be arbitrary R, and `.data` is rlang's |
