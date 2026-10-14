# ABOUTME: An interpolated string stored into a lexical whose value lives in memory
# ABOUTME: (a s/// subject, a referenced one) is a store, not a binding nothing reads.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}




# `my $s = "a$y"` is multiconcat[$s] with TARGMY: no sassign. A destructive
# s/// on $s demotes it, so its reads go through memory -- and a scope rebind
# alone left the slot empty: perl Xb, the emission an uninitialized $s.
round_trips(q{my $y = "b"; my $s = "a$y"; $s =~ s/a/X/; print "$s\n";},
    'an interpolated initializer, then a substitution');
round_trips(q{my @x = (1, 2); my $s = "a@x"; $s =~ s/a/X/; print "$s\n";},
    'an interpolated array initializer, then a substitution');
round_trips(q{my $s = "a@1"; $s =~ s/\@(\d)/$1*2/ge; print "$s\n";},
    'an empty interpolated array, then a /ge substitution');
# A BARE `my $s;` on a demoted slot is a store of undef too, or the s///
# takes the Undef binding as its subject and the store between is lost.
round_trips(q{my $s; $s = "a"; $s =~ s/a/X/; print "$s\n";},
    'a bare declaration, a plain assignment, then a substitution');
round_trips(q{my $y = "b"; my $s; $s = "a$y"; $s =~ s/a/X/; print "$s\n";},
    'an interpolated assignment, then a substitution');
round_trips(q{my $y = "b"; my $s = "a"; $s .= "<$y>"; $s =~ s/a/X/; print "$s\n";},
    'an interpolated append, then a substitution');
round_trips(q{my $y = "b"; my $s = "a$y"; my $r = \$s; print "$$r $s\n";},
    'an interpolated initializer of a referenced lexical');

done_testing;
