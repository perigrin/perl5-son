# ABOUTME: A block eval's body begins with the store perl makes there, `$@ = ""`, so a
# ABOUTME: read of $@ inside the body is ordered after it rather than before the eval.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# PERL CLEARS $@ WHEN AN EVAL BEGINS, with no op for it: `$@ = "x"; eval {
# print $@ }` prints nothing. The read inside took the memory from before
# the eval, so a consumer ordering reads by memory took it before the clear.
my $src = <<'SRC';
$@ = "x";
eval { print "in[$@]\n"; 1 };
SRC

my $data  = graph_of($src);
my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by_id = map { $_->{id} => $_ } @nodes;
my ($region) = grep { $_->{op} eq 'Region' && defined $_->{fields}{eval_entry} } @nodes;
ok $region, 'the eval has its join';
my ($first) = grep { ($_->{control_in} // -1) == $region->{fields}{eval_entry} } @nodes;
is $first->{op}, 'EntryWrite', 'the body begins with a store';
is [ map { $by_id{$_}{fields}{symbol} // $by_id{$_}{fields}{value} } $first->{inputs}->@[0, 1] ],
    [ '@', '' ], 'of "" to $@';

my $d = SoN::Deparse->new;
my $out = $d->render($data);
# Deparse refused this program by name before the store (a dangling input);
# what it must never do is render it wrong.
if (defined $out) { is run_perl($out), run_perl($src), 'renders to the same output' }
else              { like $d->gap // '', qr/\S/, 'or refuses it by name' }

done_testing;
