source("pre.R")
l1 <- "caf\xe9"; Encoding(l1) <- "latin1"
x <- zutable(id = 1:7, s = c("a", "bbb", "café", "Z", NA, "new\nline", "100%_x"), f = c(0.1 + 0.2, 1e15 + 0.3, 1/3, 1e-5, 123456.7, 2^53 + 2, 1e5), i = c(100000L, 123456L, 1L, NA, -5L, 2147483647L, 0L), d = as.Date("2020-01-01") + c(0, 31, 59, 366, NA, 5000, -1000), t = as.POSIXct("2020-03-08 06:59:59.5", tz = "UTC") + c(0, 1, 3600, 86400, NA, 0.25, 1e6))
q <- function() {
  list(
    cmp = as.data.frame(x[s == l1 | s > "Z", .(id)]),
    inn = as.data.frame(x[s %in% c(l1, "a"), .(id)]),
    like = as.data.frame(x[select = .(a = like(s, "%é"), b = like(s, "new_line"), c = like(s, "100\\%%"), d = like(s, "___"), e = like(s, "caf_"), f = starts_with(s, "caf"), g = nchar(s), h = upper(s), k = substr(s, 2L, 3L), l = concat(s, "|", s), m = trim(s))]),
    casts = as.data.frame(x[select = .(fs = cast(f, string), is = cast(i, string), ds = cast(d, string), ts = cast(t, string), bs = cast(i > 0L, string), fi = cast(i, float64))]),
    lit = as.data.frame(x[f == 0.1 + 0.2 | f > 1e15, .(id)]),
    dlit = as.data.frame(x[d >= "2020-02-01" & t < "2020-03-09 07:00:00", .(id)]),
    dt = as.data.frame(x[select = .(y = year(t), m = month(d), dd = day(t), w = date_trunc("week", d), q = date_trunc("quarter", t), mo = date_trunc("month", d), td = cast(t, date), dts = cast(d, timestamp), dts2 = cast(d, timestamp("us", "America/New_York")), tt2 = cast(t, timestamp("us", "Asia/Tokyo")))]),
    ord = as.data.frame(x[order = s])$id,
    grp = as.data.frame(x[by = .(u = upper(s)), select = .(n = .N, mn = min(s), mx = max(s))]),
    rnd = as.data.frame(x[select = .(r = round(f, 2L), fl = floor(f), m = i %% 7L, dv = i %/% 7L, p = i^2L, e = exp(f), a = abs(i), sq = sqrt(f))]),
    explain = capture.output(explain(x[f > 0.30000000000000004 & s != "é" & d > "2020-01-01", .(id, z = f * 2)][order = desc(z), limit = 3])),
    printed = capture.output(print(x)),
    sch = capture.output(print(schema(x)))
  )
}
base <- q()
str(base[c("cmp", "inn", "lit", "dlit", "ord")])
print(base$like); print(base$casts); print(base$dt); print(base$grp); print(base$rnd); cat(base$explain, sep = "\n")
cmpq <- function(label, r) { for (n in names(base)) if (!identical(base[[n]], r[[n]])) { cat("SESSION DIFF [", label, "]", n, "\n"); if (is.data.frame(r[[n]])) { for (cn in names(r[[n]])) if (!identical(base[[n]][[cn]], r[[n]][[cn]])) { cat(" col", cn, "\n"); print(base[[n]][[cn]]); print(r[[n]][[cn]]) } } else { print(base[[n]]); print(r[[n]]) } } ; cat("done", label, "\n") }
op <- options(OutDec = ",", scipen = -5, digits = 3); cmpq("options", tryCatch(q(), error = function(e) { print(e); list() })); options(op)
op <- options(warn = 2); cmpq("warn2", tryCatch(q(), error = function(e) { print(e); list() })); options(op)
Sys.setenv(TZ = "Pacific/Auckland"); cmpq("TZ", tryCatch(q(), error = function(e) { print(e); list() })); Sys.setenv(TZ = "UTC")
Sys.setlocale("LC_COLLATE", "en_US.UTF-8"); cmpq("collate", q())
ref(cmpq("reference", q()))
saveRDS(base, "p09_base.rds")
