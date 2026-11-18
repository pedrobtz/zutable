# multiple picks the first, the last, or refuses

    Code
      with_executor(ex, join(y, x, on = k, how = "right", multiple = "error"))
    Condition
      Error in `join()`:
      ! row 1 of y matches 2 rows of x on key (1); multiple = "error"

---

    Code
      with_executor(ex, join(y, x, on = k, how = "right", multiple = "error"))
    Condition
      Error in `join()`:
      ! row 1 of y matches 2 rows of x on key (1); multiple = "error"

