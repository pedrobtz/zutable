# Sorted values (test-altrep.R): the metadata of a zutable ALTREP wrapper,
# c(sorted, no_na) or NULL, and a wrapper with metadata of the caller's
# choosing, true or not.
sorted_meta <- function(x) .Call(zt_sorted_meta, x)
sorted_wrap <- function(x, sorted, no_na) .Call(zt_sorted_wrap, x, sorted, no_na)

# Strings for test-collate.R: case, accents, punctuation, digits, and one
# text composed and decomposed.
collate_pool <- function() {
  c(
    "b", "a", "B", "A", "", NA, "\u00e9", "e", "E", "f", "ab", "Ab", "a b",
    "co-op", "coop", "\u00e9a", "eb", "\u00c5ngstr\u00f6m", "zebra", "Zebra",
    # The same text composed and decomposed: equal to the collator.
    "\u00e9t\u00e9", "e\u0301te\u0301", "10", "9", "\u4e2d\u6587"
  )
}
