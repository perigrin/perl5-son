# ABOUTME: `defined &NAME` asks whether the sub exists, known when the program cannot
# ABOUTME: change it while it runs; it was Defined(the name string): always true.

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
    ok defined $out, "$name: renders" or diag($d->gap), return;
    is run_perl(write_src($out)), $want, "$name: runs as perl does"
        or diag "--- emitted ---\n$out";
}

# `defined &nope` printed y for perl's n.
round_trips(q{sub here { 1 } print defined &here ? "y" : "n"; print defined &nope ? "y" : "n"; print "\n";},
    'a sub with a body, and none');
round_trips(q{print defined &re::is_regexp ? "y\n" : "n\n";},
    'a sub perl itself defines (XS)');
# t/test.pl's: the old-perl fallback never runs, so its eval is never walked.
round_trips(q{my $l = 1; eval 'sub re::is_regexp { 1 }' if !defined &re::is_regexp; print "ok $l\n";},
    'an arm a known condition never runs');

# THE PROGRAM MAY CHANGE IT AS IT RUNS: the question is asked where the
# program runs (SubDefined), with where it may change; the backend answers it.
round_trips(q{*late = sub { 1 }; print defined &late ? "y\n" : "n\n";}, 'a sub assigned to a glob');
round_trips(q{sub here { 1 } undef &here; print defined &here ? "y\n" : "n\n";}, 'a sub undefined');

# A STRING EVAL OF KNOWN CODE changes only the subs that code defines or
# changes: Carp's `*_StrVal = eval 'sub { ... }'` defines none, so a
# `defined &other` is still known.
round_trips(q{sub here { 1 } $main::f = eval 'sub { 2 }'; print defined &nope ? "y" : "n", $main::f->(), "\n";},
    'an eval of an anonymous sub defines no named one');
round_trips(q{eval 'sub late { 1 }'; print defined &late ? "y\n" : "n\n";}, 'an eval that defines a named sub');
round_trips(q{sub here { 1 } eval 'undef &here'; print defined &here ? "y\n" : "n\n";}, 'an eval that undefines one');
round_trips(q{$main::c = "sub late { 1 }"; eval $main::c; print defined &late ? "y\n" : "n\n";}, 'an eval of code not known here');

# ON THE WIRE: the answer as compiled, and the graphs whose run may change it
# -- here f's eval of code not known, inside an anonymous sub (scanned too).
{
    my $f = write_src(q{sub f { my $c = sub { eval $main::x }; $c } print defined &nope ? "y" : "n", "\n";});
    my $d = JSON::PP->new->decode(scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null));
    my $n = $d->{methods}{'main::__PROGRAM__'}{nodes};
    my ($q) = grep { $_->{op} eq 'SubDefined' } ( ref $n eq 'HASH' ? values %$n : @$n );
    ok $q, 'a SubDefined on the wire' or last;
    is $q->{fields}{name}, 'main::nope', 'it names the sub';
    is $q->{fields}{answer} ? 1 : 0, 0, 'its answer as compiled';
    is $q->{fields}{unless}, ['main::f'], 'and the graph whose run may change it';
}

done_testing;
