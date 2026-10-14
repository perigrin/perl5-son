# ABOUTME: A qr// keeps its flags, and every pattern keeps the charset the source
# ABOUTME: compiled it under, whatever the emission's bundle would default to.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    # STDOUT ONLY: the emission runs under warnings the source may not.
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub round_trips ($src, $name) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $d = SoN::Deparse->new;
    my $out = $d->render(JSON::PP->new->utf8->decode($j));
    unless (defined $out) { fail "$name: renders"; diag $d->gap; return }
    is run_perl($out), run_perl($src), $name or diag $out;
}

# THE qr FLAGS WERE DROPPED: the Constant carried `precomp` alone, so
# `qr/a/i` came back as `qr{a}` -- it stopped matching "A", and stringified
# without its `i`.
round_trips(<<'SRC', 'a qr keeps its flags');
my $r = qr/a b/ix;
my $m = "AB" =~ $r ? "match" : "no";
print "$m $r\n";
SRC

# THE CHARSET IS THE SOURCE'S. The emission's bundle turns unicode_strings
# on, so an unmarked pattern compiles /u there and stringifies `(?^u:...)`,
# where the source -- no bundle -- compiled perl's default /d. Corpus 010,
# 191.
round_trips(<<'SRC', 'a default-charset qr stays /d');
print qr/abc/, "\n";
SRC

round_trips(<<'SRC', 'a /u source stays /u');
use v5.12;
print qr/abc/, "\n";
SRC

round_trips(<<'SRC', 'an explicit /a is kept');
my $r = qr/\d/a;
my $m = "\x{663}" =~ $r ? "y" : "n";
print "$r $m\n";
SRC

# /n MAKES EVERY GROUP NON-CAPTURING, so $1 reads nothing. The flag string
# had no `n`: `s/(\d)/<$1>/gn` on "a1b2" gave a<1>b<1> for perl's a<>b<>.
round_trips(q{my $s = "a1"; $s =~ /(\d)/n; print defined $1 ? "d\n" : "u\n";},
    'a match under /n captures nothing');
round_trips(q{my $s = "a1b2"; $s =~ s/(\d)/<$1>/gn; print "[$s]\n";},
    'a substitution under /n captures nothing');
round_trips(q{my $s = "a1b2"; $s =~ s/(\d)/$1*2/gen; print "[$s]\n";},
    'a /ge body under /n reads no capture');
round_trips(q{my $s = "a1b2"; $s =~ s/(\d)/"<$1>"/gen; print "[$s]\n";},
    'an interpolating /ge body under /n');
round_trips(q{my $s = "a1b2"; my $t = $s =~ s/(\d)/$1*2/genr; print "[$t][$s]\n";},
    'a /ger body under /n');
round_trips(q{my $s = "a1b2"; $s =~ s/(?:(\d))/<$1>/gn; print "[$s]\n";},
    '/n leaves an explicit non-capturing group alone');

done_testing;
