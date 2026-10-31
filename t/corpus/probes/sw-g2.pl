sub h { f() } *f = sub { 7 }; print h(), "\n";
