use v5.36; sub each2 ($cb) { $cb->(1) . $cb->(2) } my $p = "x"; print each2(sub ($n) { "$p$n" }), "\n";
