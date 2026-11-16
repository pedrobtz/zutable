# schemas print with a type row per field

    Code
      print(s)
    Output
      <zutable_schema> 4 fields
        id not_null(int32)
        px float64
          unit: USD
        tags list(string)
        t timestamp("us", "UTC")
      metadata: source: x

---

    Code
      print(s$fields$tags$type)
    Output
      <zutable_type> list(string)

