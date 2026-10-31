use v5.36; sub f ($n) { $n > 1 ? $n * 1.5 : undef } my @r = (f(2), f(1)); print defined $r[0] ? $r[0] : "u", " ", defined $r[1] ? "d" : "u", "\n";
