# ABOUTME: `select FH` stays where it was written relative to the print it
# ABOUTME: redirects; four-argument select and wantarray have spellings.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
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

# `select FH` BOUND TO A VARIABLE WAS NEVER PINNED, so it floated to its one
# reader and landed after the print it was meant to redirect:
# `print ...; select(select($out))`. And the four-argument select is the op
# `sselect`, which had no spelling. Corpus 224.
round_trips(<<'SRC', 'select redirects the print that follows it');
open(my $out, ">", \my $buf);
my $prev = select($out);
print "captured\n";
select($prev);
close($out);
my $ready = select(undef, undef, undef, 0);
print "[$buf][$ready]\n";
SRC

# `wantarray` HAD NO RULE. At file scope it is undef. Corpus 083.
round_trips(<<'SRC', 'wantarray at file scope');
my $w = wantarray;
my @seen = ($w);
print scalar(@seen), " ", defined($w) ? "def" : "undef", "\n";
SRC

done_testing;
