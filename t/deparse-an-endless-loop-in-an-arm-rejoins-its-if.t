# ABOUTME: An endless loop (`while (1) { ... last ... }`) in an if's arm: what follows the
# ABOUTME: if runs after either arm, as perl runs it -- not after the loop alone.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

# Found by the wire v2 verifier on chalk's Earley::_force (write-unreachable on
# chalk2, the baseline's known issue 4): `if (C) { A } else { while (1) {
# ...; last if D } }` then the rest. The two arms rejoin at the op after the
# if, which _find_join_addr finds as the first op both arms' op_next chains
# share; the endless loop's chain cycles in its body and never reaches it, so
# no join was found, the rest was walked as the loop arm's, and the other arm
# ended in nothing: its stores, and the rest, lost on that path. Silent: the
# deparsed program printed "undef" where perl prints 7.
my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub round_trips ( $src, $name ) {
    my $want = run_perl($src);
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    my $d = SoN::Deparse->new;
    my $out = eval { $d->render( decode_json($j) ) };
    unless ( defined $out ) { fail "$name: renders"; diag $d->gap // $@; return }
    is run_perl($out), $want, "$name: perl's answer" or diag "--- emitted ---\n$out";
}

round_trips( q{my $h = {a=>1}; my $r; if ($h->{a}) { $r = 7 } else { my $n = 3; while (1) { $n--; last if $n < 1 } $r = $n } $h->{m} = $r; print $h->{m}, "\n";},
    'the rest after the true arm, at the top level' );
round_trips( q{sub f { my ($v) = @_; my $r; if ($v->{a}) { $r = 7 } else { my $n = 3; while (1) { $n--; last if $n < 1 } $r = $n } $v->{m} = $r; return $r } my $h = {a=>1}; f($h); print $h->{m} // "undef", "\n";},
    'the rest after the true arm, in a sub' );
round_trips( q{sub f { my ($v) = @_; my $r; if ($v->{a}) { $r = 7 } else { my $n = 3; while (1) { $n--; last if $n < 1 } $r = $n } $v->{m} = $r; return $r } my $h = {}; f($h); print $h->{m} // "undef", "\n";},
    'the rest after the loop arm, in a sub' );
round_trips( q{my $n = 0; my $h = {}; if ($n) { $h->{x} = 1 } else { for (;;) { $n += 2; last if $n > 5 } } $h->{y} = $n; print join(",", map { "$_=$h->{$_}" } sort keys %$h), "\n";},
    'a for (;;) in the else arm' );
round_trips( q{my $n = 1; my $h = {}; if ($n) { while (1) { $n *= 3; last if $n > 10 } } else { $h->{x} = 1 } $h->{y} = $n; print join(",", map { "$_=$h->{$_}" } sort keys %$h), "\n";},
    'the loop in the true arm' );

done_testing;
