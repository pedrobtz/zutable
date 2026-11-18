# multiple = "error" is a zutable_multiple_error naming the key

    Code
      grp_join(x, y, multiple = "error")
    Condition
      Error in `grp_join()`:
      ! row 3 of x matches 2 rows of y on key (3, b); multiple = "error"

---

    Code
      grp_join(c(1, 0.123456789012), c(0.123456789012, 0.123456789012), multiple = "error")
    Condition
      Error in `grp_join()`:
      ! row 2 of x matches 2 rows of y on key (0.123456789012); multiple = "error"

