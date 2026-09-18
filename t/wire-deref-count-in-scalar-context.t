# ABOUTME: `@$r` in scalar context is the referent's element COUNT.
# ABOUTME: with no handler the rv2av vanished and the REFERENCE was used instead.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE DEFECT. `rv2av` in LIST context has a handler (it flattens the referent
# so an assignment builds N elements); SCALAR context had none, and its comment
# said the case was "handled by the scalar-of-aggregate path above". That path
# keys on the RHS op of an ASSIGNMENT, so it never saw this. The rv2av was
# dropped and the REFERENCE itself was used:
#
#     my @L=(1,2,3); my $r=\@L; print scalar(@$r)
#       perl 3, emitted ARRAY(0x...)
#
# and the graph showed it plainly -- Coerce(Ref -> Str) straight off the Ref,
# with no deref and no Count:
#
#     6 Ref     ArrayRef in=[5]
#     7 Coerce  Str      in=[6]   from_repr=Unknown
#
# BOTH SCALAR-CONTEXT SPELLINGS reach the same op, so both were wrong.
round_trips( <<'SRC', 'scalar(@$r) is the element count' );
my @L = (1,2,3);
my $r = \@L;
print scalar(@$r), "\n";
SRC

round_trips( <<'SRC', 'an assignment from @$r takes the count' );
my @L = (1,2,3);
my $r = \@L;
my $n = @$r;
print "$n\n";
SRC

# A HASH REF IS THE SAME OPERATION over the other aggregate kind -- rv2hv in
# scalar context is the key count in modern perl.
round_trips( <<'SRC', 'scalar(%$h) is the key count' );
my %H = (a => 1, b => 2);
my $h = \%H;
my $n = %$h;
print +($n ? "true\n" : "false\n");
SRC

# THE COUNT FOLLOWS THE REFERENT, so a mutation through the reference must be
# visible -- the property that makes this a memory read rather than a constant.
round_trips( <<'SRC', 'the count sees a push through the reference' );
my @L = (1,2,3);
my $r = \@L;
push @$r, 4;
print scalar(@$r), "\n";
SRC

# LIST CONTEXT IS UNCHANGED -- the handler that already worked, kept so the
# fix cannot trade one context for the other.
round_trips( <<'SRC', 'list-context deref still flattens' );
my $r = [1,2,3];
my @b = @$r;
print scalar(@b), "\n";
SRC

# A PLAIN ARRAY IS UNCHANGED.
round_trips( <<'SRC', 'scalar(@a) on a plain array is unchanged' );
my @L = (1,2,3);
print scalar(@L), "\n";
SRC

done_testing;
