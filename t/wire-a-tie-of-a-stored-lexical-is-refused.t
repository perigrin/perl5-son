# ABOUTME: a tie of a lexical the sub also stores is refused: the walk folds a
# ABOUTME: stored value into later reads, where perl calls STORE and FETCH.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

my $pkg = qq{package C;\nsub TIESCALAR { bless {}, "C" }\nsub FETCH { 42 }\nsub STORE { }\npackage main;\n};
# `$x = 5; print $x` reached the wire as `print 5` (pvm 415's neighbours).
like warnings_of($pkg . qq{tie my \$x, "C";\n\$x = 5;\nprint \$x, "\\n";\n}),
    qr/GAP: a tie of a lexical the sub also stores/, 'a store after the tie';
like warnings_of($pkg . qq{my \$y = 1;\ntie \$y, "C";\nprint \$y, "\\n";\n}),
    qr/GAP: a tie of a lexical the sub also stores/, 'a value before the tie';
unlike warnings_of($pkg . qq{tie my \$x, "C";\nprint \$x, "\\n";\n}),
    qr/GAP: a tie/, 'a tie read only is not refused';
unlike warnings_of($pkg . qq{tie my \$x, "C";\nprint tied(\$x) ? "t" : "u", "\\n";\n}),
    qr/GAP: a tie/, 'tied() of it is not a store (pvm 416)';

done_testing;
