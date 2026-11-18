# zutable: Typed Tables Queried with SQL Clauses

A data frame that always knows its schema: the name, logical type and
nullability of every column, with the types of 'Apache Arrow'. Queries
are written in the bracket, with the clauses of SQL (structured query
language) as named arguments over bare column names, and are translated
into typed expressions over a closed vocabulary, so the schema of every
result, and every type error, is known before any data is read. Existing
columns are updated in place, a table can be frozen against further
change, and grouping, sorting, joining and reducing run on a
cache-conscious kernel whose header other packages can use through
'LinkingTo'.

## See also

Useful links:

- <https://pedrobtz.github.io/zutable/>

- <https://github.com/pedrobtz/zutable>

- Report bugs at <https://github.com/pedrobtz/zutable/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Orson Peters (pdqsort, ported in inst/include/zutable/pdqsort.inc)
  \[contributor, copyright holder\]

- Morwenn (Vergesort, ported in inst/include/zutable/vergesort.inc)
  \[contributor, copyright holder\]

- Malte Skarupke (ska sort, ported in inst/include/zutable/skasort.inc)
  \[contributor, copyright holder\]
