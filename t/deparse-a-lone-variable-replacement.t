# ABOUTME: A replacement that is one variable -- `s/a/$y/`, `s/(b)/$1/` -- is read where the
# ABOUTME: substitution runs: a capture is its own match's, a lexical is its value.

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

# A LONE NON-CONSTANT REPLACEMENT WAS DROPPED: only a Constant was taken for
# the replacement string, so `s/a/$y/` deleted the match (`b` for `Zb`).
round_trips(q{sub f { my ($y) = @_; my $u = "ab"; $u =~ s/a/$y/; return $u } print f("Z"), "\n";},
    'a lone lexical replacement');
round_trips(q{our $g = "G"; sub f { my $u = "ab"; $u =~ s/a/$g/; return $u } print f(), "\n";},
    'a lone package scalar replacement');
round_trips(q{sub f { my ($y) = @_; my $u = "abab"; $u =~ s/a/$y/g; return $u } print f("Z"), "\n";},
    'a lone lexical replacement under /g');
# A LONE CAPTURE IS THE SUBSTITUTION'S OWN: an earlier match does not leak
# in (`ayb`, not `aQb`), and with no earlier match it refused (chalk's
# EmitHelpers::_emit_return_stmt, `s/^sv_2mortal\((.+)\)$/$1/`).
round_trips(q{sub f { my $v = "sv_2mortal(x)"; $v =~ s/^sv_2mortal\((.+)\)$/$1/; return $v } print f(), "\n";},
    'a lone capture replacement');
round_trips(q{sub f { my $t = "QQ"; $t =~ /(Q)/; my $u = "ayb"; $u =~ s/(y)/$1/; return "$u $1" } print f(), "\n";},
    'a lone capture replacement after an earlier match');
round_trips(q{sub f { my $u = "ab"; my $n = ($u =~ s/(c)/$1/); return "$u|$n" } print f(), "\n";},
    'a lone capture replacement that does not match');

# THE LOOP BODY'S WALK HAS ITS OWN s/// SITE, and the same two holes.
round_trips(q{sub f { my @r; for my $v ("sv_2mortal(a)", "b") { my $w = $v; $w =~ s/^sv_2mortal\((.+)\)$/$1/; push @r, $w } return "@r" } print f(), "\n";},
    'a lone capture replacement in a loop');
round_trips(q{sub f { my ($y) = @_; my @r; for my $i (1, 2) { my $u = "a$i"; $u =~ s/a/$y/; push @r, $u } return "@r" } print f("Z"), "\n";},
    'a lone lexical replacement in a loop');

done_testing;
