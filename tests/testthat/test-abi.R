# The shared object's ABI (design-kernel 8, R10.4): the kernel reaches
# siblings as a header, never as symbols, so nothing but R_init_zutable
# leaves zutable.so. Every .Call entry point goes through the registration
# table, and $(C_VISIBILITY) in src/Makevars hides the rest; a symbol that
# leaked could bind to a sibling's copy of the same name in one process.

test_that("the shared object exports R_init_zutable only", {
  skip_if(is_instrumented_build(), "instrumented build: its runtime exports symbols of its own")
  expect_identical(sort(unique(exported_symbols())), "R_init_zutable")
})

test_that("the entry points resolve through registration alone", {
  dll <- getLoadedDLLs()[["zutable"]]
  skip_if(is.null(dll), "zutable's shared object is not loaded")
  expect_false(dll[["dynamicLookup"]])
  calls <- getDLLRegisteredRoutines(dll)$.Call
  expect_true(length(calls) > 0L)
  expect_true(all(c("zt_reduce_r", "zt_join") %in% names(calls)))
})
