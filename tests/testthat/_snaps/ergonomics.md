# D28 is kept: an update in the first position is a syntax error

    Code
      t[{
        px := 1
      }]
    Condition
      Error in `[.zutable`:
      ! an update goes in the second position: x[, col := value] or x[cond, { a := ...; b := ... }]

