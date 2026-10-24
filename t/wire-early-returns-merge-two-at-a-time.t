# ABOUTME: A sub's early returns merge two at a time: each Region on the wire
# ABOUTME: joins the two arms of one If, nested, never three exits in one.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# Region input counts, and how many Regions have no head.
sub regions ($data, $graph) {
    my @n = $data->{methods}{$graph}{nodes}->@*;
    my @r = grep { $_->{op} eq 'Region' } @n;
    return [ map { scalar @{ $_->{inputs} // [] } } @r ],
           scalar grep { !defined $_->{head} } @r;
}

# THREE EXITS IN ONE REGION HAVE NO OWNER. `return A if C1; return B if C2;
# return D` made Region(then1, then2, else2): no one If owns all three, so the
# Region had no head, and chalk could not find the structure that defines its
# Phi (pvm subroutines.md, 17 corpus cases). The two arms of the inner If are
# one merge; that merge and the outer If's other arm are the next.
my $src = <<'SRC';
sub c { return "z" if $_[0] == 0; return "n" if $_[0] < 0; return "p"; }
print c(0), c(-5), c(7), "\n";
SRC

my $data = graph_of($src);
my ($sizes, $headless) = regions($data, 'main::c');
is $sizes, [2, 2], 'two Regions of two';
is $headless, 0, 'each owned by its If';

my $four = <<'SRC';
sub c { return 1 if $_[0] == 1; return 2 if $_[0] == 2; return 3 if $_[0] == 3; return 4 }
print c(1), c(2), c(3), c(9), "\n";
SRC
($sizes, $headless) = regions(graph_of($four), 'main::c');
is $sizes, [2, 2, 2], 'four exits are three Regions of two';
is $headless, 0, 'each owned by its If';

# The Perl it renders to still gives perl's answer.
for my $s ($src, $four) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($s));
    is run_perl($out // ''), run_perl($s), 'renders to the same output'
        or diag $out // $d->gap;
}

done_testing;
