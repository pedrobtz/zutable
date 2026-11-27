source("pre.R")
z2 <- zutable(s = c("2020-01-01 10:00:00", "2020-01-02", NA))
r <- try_(z2[select = .(t = cast(s, timestamp))]); print(unclass(r$t)); print(schema(r))
z <- zutable(s = c("2020-01-01", "2020-01-01 10:00:00"))
r <- try_(z[select = .(t = cast(s, timestamp))]); print(unclass(r$t))
# literal sets
tt <- zutable(t = as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 10:00:00"), tz = "UTC"))
print(try_(tt[t %in% c("2020-01-01", "2020-01-01 10:00:00")]))
print(try_(tt[t == "2020-01-01 10:00:00"]))
# date_trunc on DST
ts <- as.POSIXct(c(1541300400, 1541304000, 1541307600), origin="1970-01-01", tz = "America/New_York") # 2018-11-04 01:00 EDT, 01:00 EST, 02:00 EST? 
print(ts); print(unclass(ts))
w <- zutable(t = ts + 1800)
r <- try_(w[select = .(t, h = date_trunc("hour", t), d = date_trunc("day", t))]); print(as.data.frame(r)); print(unclass(r$h) - unclass(r$t))
sp <- zutable(t = as.POSIXct("2018-11-04 12:00:00", tz = "America/Sao_Paulo"))
r <- try_(sp[select = .(d = date_trunc("day", t), y = year(t), dt = cast(t, date))]); print(as.data.frame(r))
# string -> date cast
sd <- zutable(s = c("2020-01-01", NA, "2020-02-29"))
print(try_(sd[select = .(d = cast(s, date))]))
sd <- zutable(s = c("2020-01-01", "2021-02-30"))
print(try_(sd[select = .(d = cast(s, date))]))
sd <- zutable(s = c(NA_character_, NA))
print(try_(sd[select = .(d = cast(s, date), t = cast(s, timestamp), i = cast(s, int32), f = cast(s, float64), b = cast(s, bool))]))
sd <- zutable(s = character())
print(try_(sd[select = .(d = cast(s, date), t = cast(s, timestamp), i = cast(s, int32), f = cast(s, float64), b = cast(s, bool))]))
# string->numbers
sn <- zutable(s = c(" 12 ", "+5", "-0", "1e3", "0x10", "2147483647", "007"))
print(try_(sn[select = .(i = cast(s, int32))]))
print(try_(sn[s != "1e3" & s != "0x10", .(s, i = cast(s, int32))]))
print(try_(sn[select = .(f = cast(s, float64))]))
sn <- zutable(s = c("1e3", "Inf", "inf", "nan", "NaN", "NA", " 1.5", "1,5", "-inf", "infinity", "1d", ".5", "5."))
for (v in sn$s) { cat(v, ": "); r <- try_(zutable(s = v)[select = .(f = cast(s, float64))]); if (is_zutable(r)) print(r$f) }
# float->int
fn <- zutable(f = c(1, -0, 2147483647, NA))
print(try_(fn[select = .(i = cast(f, int32))]))
print(try_(zutable(f = NaN)[select = .(i = cast(f, int32))]))
print(try_(zutable(f = c(NA, 1.5))[select = .(i = cast(f, int32))]))
# enum casts
e <- zutable(e = factor(c("a", "b", NA)))
print(try_(e[select = .(s = cast(e, string), e2 = cast(e, enum(c("b", "a"))))]))
print(try_(e[select = .(e2 = cast(e, enum(c("b"))))]))
