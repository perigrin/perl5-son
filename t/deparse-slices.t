# ABOUTME: List, array and hash slices must round-trip through the oracle.
# ABOUTME: A hash slice subscripts with braces; only the container's sigil says so.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub run_src ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $file 2>&1);
    unlink $file;
    return $out;
}

sub emit ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return SoN::Deparse->new->render($data);
}

sub round_trips ($name, $src) {
    my $emitted = emit($src);
    ok defined $emitted, "$name: it renders" or return;
    is run_perl_pair($emitted, $src), 1, "$name: it agrees with perl"
        or diag "emitted:\n$emitted";
}

sub run_perl_pair ($emitted, $src) {
    return run_src($emitted) eq run_src($src) ? 1 : 0;
}

# `(qw(p q r))[1]` is lslice over TWO mark-delimited lists. A fixed arity of 2
# took the last two stack entries: the index and the first value were dropped
# and "p" leaked into the print. The one-element form was a silent WRONG
# ANSWER -- `print( (qw(b))[0] )` emitted nothing where perl prints "b".
subtest 'a list slice renders as (VALUES)[INDICES]' => sub {
    round_trips 'single index', qq{print( (qw(p q r))[1], "\\n" );\n};
    round_trips 'one element',  qq{print( (qw(b))[0], "\\n" );\n};
    round_trips 'two indices',  qq{print( (qw(p q r))[0,2], "\\n" );\n};
    round_trips 'string list',  qq{print( ("a","b","c")[2], "\\n" );\n};
};

# The container form puts the container LAST and every index before it. The
# renderer accepted only two inputs, so a multi-index array slice -- three
# inputs -- was refused although it is perfectly spellable.
subtest 'an array slice takes every index' => sub {
    round_trips 'two indices',
        qq{my \@a = ("x","y","z");\nprint( \@a[0,2], "\\n" );\n};
    round_trips 'one index',
        qq{my \@a = ("x","y","z");\nprint( \@a[1], "\\n" );\n};
};

# `@h{...}` and `@a[...]` are both Slice nodes carrying an `@` sigil of their
# own. Only the CONTAINER's sigil says which brackets to emit, and `@h[...]`
# would index a different variable that need not even exist.
subtest 'a hash slice subscripts with braces' => sub {
    round_trips 'two keys',
        qq{my \%h = (k1=>"v1", k2=>"v2");\nprint( \@h{"k1","k2"}, "\\n" );\n};
};

done_testing;
