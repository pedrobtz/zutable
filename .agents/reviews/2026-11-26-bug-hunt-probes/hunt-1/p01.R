source("pre.R")
x <- zutable(i = c(1L, 100000L, 123456789L, NA), d = c(0.1, 1e5, 1e15, 123456.7), s = c("a","bbb",NA,"é"))
print(try_(x[select = .(a = cast(i, string), b = cast(d, string))]))
ref(print(try_(x[select = .(a = cast(i, string), b = cast(d, string))])))
options(scipen = -5)
print(try_(x[select = .(a = cast(i, string))]))
options(scipen = 0)
# timestamp to string rounding
t <- as.POSIXct(c(0.9999996, 1700000000.9999998, 1.5, NA), origin = "1970-01-01", tz = "UTC")
y <- zutable(t = t)
print(try_(as.data.frame(y[select = .(a = cast(t, string))])))
# mixed format strings to timestamp
z <- zutable(s = c("2020-01-01", "2020-01-01 10:00:00"))
r <- try_(z[select = .(t = cast(s, timestamp))]); print(r); 
z2 <- zutable(s = c("2020-01-01 10:00:00", "2020-01-02"))
r <- try_(z2[select = .(t = cast(s, timestamp))]); print(r)
z3 <- zutable(s = c("2020-01-01 10:00", "2020-01-01 10:00:30"))
r <- try_(z3[select = .(t = cast(s, timestamp))]); print(r)
# date to timestamp in DST-midnight-gap zone
dd <- zutable(d = as.Date(c("2018-11-04", "2018-11-05")))
r <- try_(dd[select = .(t = cast(d, timestamp("us", "America/Sao_Paulo")))]); print(r)
