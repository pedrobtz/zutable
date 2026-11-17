# a zutable prints its schema under the names

    Code
      print(z)
    Output
      <zutable> 3 rows x 5 columns
        id      name     score     day        tags
        <int32> <string> <float64> <date>     <list(int32)>
      1 1       Ada      1.5       2026-01-01 <integer[2]>
      2 2       Linus    NA        2026-01-02 NULL
      3 3       NA       3.0       2026-01-03 <integer[1]>

---

    Code
      print(zutable(a = 1:12), n = 3)
    Output
      <zutable> 12 rows x 1 column
        a
        <int32>
      1 1
      2 2
      3 3
      # ... 9 more rows

---

    Code
      print(zutable())
    Output
      <zutable> 0 rows x 0 columns

---

    Code
      print(as_zutable(data.frame(a = 1L), schema(a = not_null(int32))))
    Output
      <zutable> 1 row x 1 column
        a
        <not_null(int32)>
      1 1

