# ABOUTME: A whole store into a package array or hash is spelled where its store is
# ABOUTME: on the chain: hoisted as a declaration, two stores swapped places.

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

# `our @a = (1); @a = (5)` emitted `@main::a = (5); @main::a = (1);`:
# "1" for perl's "5", a silent wrong answer.
for my $src (
    q{our @a = (1); @a = (5); print "@a\n";},
    q{our @a = (1); { @a = (5); print "@a " } print "@a\n";},
    q{our %h = (k => 1); %h = (k => 2); print $h{k}, "\n";},
    q{our @a = (1); sub g { @a = (5) } g(); print "@a\n";},
) {
    my $f    = write_src($src);
    my $want = run_perl($f);
    my $j    = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    my $d    = SoN::Deparse->new;
    my $out  = $d->render(JSON::PP->new->decode($j));
    ok defined $out, "renders: $src" or diag($d->gap), next;
    is run_perl(write_src($out)), $want, '... and runs as perl does'
        or diag "--- emitted ---\n$out";
}

done_testing;
