# explain() prints one step per line

    Code
      explain(z)
    Output
      table  id int32, px float64, qty int32, g string

---

    Code
      explain(z[px > 1.6 & g == "a", .(id, notional = px * qty), order = .(desc(
        notional), id), limit = 2])
    Output
      source  <anonymous table>  id int32, px float64, qty int32, g string
      filter  ((px > 1.6) & (g == "a"))
      project id int32, notional float64 = (px * qty)
      sort    notional desc, id
      limit   2

---

    Code
      explain(z[, .(g), distinct = TRUE][order = g])
    Output
      source  <anonymous table>  id int32, px float64, qty int32, g string
      project g string
      distinct
      sort    g

---

    Code
      explain(z[, .(day = cast("2026-01-01", date), s = case(px > 2 ~ "hi"))])
    Output
      source  <anonymous table>  id int32, px float64, qty int32, g string
      project day not_null(date) = cast("2026-01-01", date), s string = case((px > 2) ~ "hi", .default = NA)

