# ABOUTME: A bare block holding `redo` is a loop that runs once: redo goes back to
# ABOUTME: its top, next and last and its end leave it (Carp's short_error_loc).

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub write_src ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return $f;
}

sub run_perl ($f) { return scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null) }

sub round_trips ($src, $name) {
    my $f    = write_src($src);
    my $want = run_perl($f);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die; my $err = do { local $/; <$e> } =~ s/^\S+ syntax OK\n//mr;
    is $err, '', "$name: the producer says nothing" or return;
    my $d   = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->decode($j));
    # THE GRAPH IS THE CHECK HERE (T2 runs it): a deparse is perl's answer, or
    # refused by name -- never a wrong one.
    unless (defined $out) { like $d->gap // '', qr/GAP: .* not yet rendered/, "$name: refused by name"; return }
    is run_perl(write_src($out)), $want, "$name: runs as perl does"
        or diag "--- emitted ---\n$out";
}

round_trips(q{my $i = 0; { $i++; redo if $i < 3; } print "$i\n";},
    'a redo under a modifier');
round_trips(q{my $i = 0; { $i++; if ($i > 4) { last } redo; } print "$i\n";},
    'a last in an arm, then a bare redo');
round_trips(q{my ($i, $n) = (1, 0); { my $c = $i; $i++; $n++; redo if $c < 3; } print "$i $n\n";},
    'a lexical made each pass');
round_trips(q{sub f { my $i = 0; { $i++; return $i * 10 if $i > 2; last if $i > 99; redo; } return -1 } print f(), "\n";},
    'a return out of it');
round_trips(q{my $i = 0; while (1) { $i++; next if $i < 3; last } print "$i\n";},
    'a while (1) going round on a `next if`');
# Carp's short_error_loc, its shape: redo on each condition, last, return.
round_trips(q{our %I = (b => 1); my @c = ("a", "b", "b", "c", "d");
sub loc { my $i = 0; my $lvl = 1; { my $x = $c[$i]; $i++; return 0 unless defined $x; redo if $I{$x}; redo unless 0 > --$lvl; } return $i - 1 } print loc(), "\n";},
    'Carp\'s shape');

done_testing;
