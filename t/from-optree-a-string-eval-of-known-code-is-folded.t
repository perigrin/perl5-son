# ABOUTME: A string eval whose code is one of a few known pure literals (t/test.pl's
# ABOUTME: escape table) is folded at compile time: its value chosen by its code.

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

sub producer_stderr ($src) {
    my $f = write_src($src);
    qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err >/dev/null);
    open my $e, '<', "$dir/err" or return ''; local $/; return <$e> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $f    = write_src($src);
    my $want = run_perl($f);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die; my $err = do { local $/; <$e> } =~ s/^\S+ syntax OK\n//mr;
    is $err, '', "$name: the producer says nothing" or return;
    my $d   = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->decode($j));
    unless (defined $out) { like $d->gap // '', qr/GAP: .* not yet rendered/, "$name: refused by name"; return }
    is run_perl(write_src($out)), $want, "$name: runs as perl does"
        or diag "--- emitted ---\n$out";
}

# t/test.pl's: the code is `"\e"`, `"\n"`, ... -- one per character of a constant.
round_trips(q{my %e; foreach my $x (split //, 'enrtfa\\\\\'"') { $e{ord eval "\"\\\\$x\""} = "\\\\$x"; }
print join(",", map { "$_=$e{$_}" } sort { $a <=> $b } keys %e), "\n";},
    'test.pl\'s escape table');
round_trips(q{my $v = eval q{"a\tb"}; print length($v), "\n";},
    'one constant code string');
# eval STRING CLEARS $@ as it succeeds.
round_trips(q{eval { die "no\n" }; my $v = eval q{"ok"}; print "$v [$@]\n";},
    'a folded eval clears $@');

# NOT KNOWN, OR NOT A PURE LITERAL: still refused by name.
like producer_stderr(q{my $c = $ENV{C} // 'x'; my $v = eval "\"$c\""; print "$v\n";}),
    qr/GAP: a string eval/, 'code from a value not known: refused';
like producer_stderr(q{my $y = 1; foreach my $x ('n', '$y') { print eval "\"$x\"" } print "\n";}),
    qr/GAP: a string eval/, 'code that would interpolate: refused';

done_testing;
