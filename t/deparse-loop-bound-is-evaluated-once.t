# ABOUTME: a foreach range's bound is computed once, at loop entry.
# ABOUTME: re-reading a global the body mutates makes the bound chase the counter.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::Deparse;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub round_trip ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;

    my $want = qx{$PERL $file 2>&1};

    my $json = qx{$PERL -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null};
    return ( $want, undef, 'no graph' ) unless length $json;
    my $wire = eval { JSON::PP->new->decode($json) }
        or return ( $want, undef, 'undecodable graph' );

    my $out = eval { SoN::Deparse->new->render($wire) };
    return ( $want, undef, $@ || 'refused' ) unless defined $out;

    my $emitted = "$dir/$name.out.pl";
    open my $o, '>', $emitted or die "open $emitted: $!";
    print {$o} $out;
    close $o;

    # THE BOUND CHASING THE COUNTER IS AN INFINITE LOOP, not a wrong answer.
    # Without the timeout this test hangs the suite rather than failing it.
    my $got = qx{timeout 10 $PERL $emitted 2>&1};
    return ( $want, $got, undef, $out );
}

# THE DEFECT. perl evaluates a foreach range's endpoints ONCE, when the loop
# is entered, and iterates the fixed list that produces. The graph says so:
# the bound is built over EntryDef 223 -- the version of $test_count that
# existed at loop entry -- not over whatever the global holds now.
#
# The deparser rendered that EntryDef as the live name `$main::test_count`,
# so the emitted `while ((($main::test_count + 3) + 1) > $phi)` recomputed the
# bound from a global the body increments. Bound and counter advanced in step
# and the loop never terminated: base/rs.t spun at 97% CPU emitting
# `ok 2106390 # skipped on non-VMS system`, where perl emits four lines.
subtest 'a range bound over a mutated global is fixed at loop entry' => sub {
    my ( $want, $got, $why ) = round_trip( <<'SRC', 'range-bound' );
$c = @ARGV ? $ARGV[0] : 1;
foreach $t ($c..$c+3) { print "ok $t\n"; $c++ }
print "done $c\n";
SRC

    is $want, "ok 1\nok 2\nok 3\nok 4\ndone 5\n",
        'perl itself iterates four times';
    ok defined($got), 'it renders rather than refusing' or diag($why), return;
    is $got, $want, 'and the emitted program agrees with perl';
};

done_testing;
