# ABOUTME: Braun's header (wire v2 stage 9b) carries no `my %h` the pass declares, and refuses a
# ABOUTME: `//=` into an element of an aggregate only where the loop really rebinds it.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use SoN::Deparse;
use JSON::PP;

# WHY. chalk's LR0DFA::_build_dfa_states and Earley::_run_parse were refused
# under the first Braun header: `my %kernels` declared in a while's body got
# a header Phi, and `$kernels{$k} //= []` in the inner foreach was read as a
# store "into an element of an aggregate rebound inside the loop" -- which
# the scouts never saw, since the pass never rebinds it. A `my %h` the pass
# declares is a fresh hash each pass; and whether a loop carries an
# aggregate is known at its sealing, where the refusal now waits.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub run ( $src, $name ) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    my $err = do { local ( @ARGV, $/ ) = "$dir/err"; <> } // '';
    unlike $err, qr/GAP/, "$name: translated" or return;
    my $out = SoN::Deparse->new->render( JSON::PP->new->utf8->decode($json) );
    ok defined $out, "$name: renders" or return;
    my $g = "$dir/g$n.pl";
    open my $o2, '>', $g or die $!;
    print $o2 $out;
    close $o2;
    is scalar(qx($^X $g)), scalar(qx($^X $f)), "$name: as perl";
}

run( <<'SRC', 'a hash declared in a while body, //= into it from a foreach' );
my @states = (1, 2); my $i = 0; my @out;
while ($i < @states) { my %k; for my $c (1, 2) { $k{"x$c"} //= []; push $k{"x$c"}->@*, $c } push @out, join ",", sort keys %k; $i++ }
print "@out\n";
SRC

# AND THE REFUSAL STILL STANDS where the loop does rebind the aggregate.
{
    my $f = "$dir/r.pl";
    open my $o, '>', $f or die $!;
    print $o 'my @a; for (1..2) { @a = (); $a[0] ||= $_ } print "@a\n";';
    close $o;
    like scalar(qx($^X -Ilib -MO=-q,SoN,json $f 2>&1 >/dev/null)), qr/GAP: `\|\|=` into an element of an aggregate rebound inside the loop/,
        'an aggregate the pass rebinds (`@a = ()`): refused by name';
}

done_testing;
