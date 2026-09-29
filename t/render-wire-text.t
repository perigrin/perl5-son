# ABOUTME: SoN::Render::WireText lists the wire JSON one node per line -- the
# ABOUTME: same ids, inputs, control edges and stamps a consumer loads.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Render::WireText;

my $dir = tempdir(CLEANUP => 1);

sub wire_of ($src) {
    my $f = "$dir/w." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return JSON::PP->new->decode($j);
}

my $wire = wire_of(<<'SRC');
use strict;
my $x = $ENV{X} // 1;
if ($x > 1) { print "big\n" } else { print "small\n" }
sub f { return $_[0] + 1 }
print f($x), "\n";
SRC
my $text = SoN::Render::WireText::render($wire);

# THE LISTING IS THE WIRE, NOT A SECOND READING OF IT. A listing that
# renumbered, dropped the control edges or re-derived stamps would describe a
# graph no consumer loads -- which is what the producer's own text dump does.
subtest 'every wire node is one line, under its wire id' => sub {
    for my $m (sort keys $wire->{methods}->%*) {
        like $text, qr/^== \Q$m\E start=%\d+ returns=/m, "a header for $m";
        my ($section) = $text =~ /^== \Q$m\E [^\n]*\n(.*?)(?=^==|\z)/ms;
        my @lines = grep { /^%\d+ = / } split /\n/, $section // '';
        is scalar(@lines), scalar($wire->{methods}{$m}{nodes}->@*),
            "$m: one line per node";
        for my $n ($wire->{methods}{$m}{nodes}->@*) {
            my ($line) = grep { /^%\Q$n->{id}\E = / } @lines;
            ok $line, "$m: %$n->{id} is listed" or next;
            like $line, qr/^%\Q$n->{id}\E = \Q$n->{op}\E\b/, '... as its op';
            if (my @in = ($n->{inputs} // [])->@*) {
                my $want = '(' . join(', ', map { "%$_" } @in) . ')';
                like $line, qr/\Q$want\E/, '... with its inputs in order';
            }
            like $line, qr/ ctl=%\Q$n->{control_in}\E\b/, '... and its control edge'
                if defined $n->{control_in};
            like $line, qr/ : \Q$n->{stamp}\E$/, '... and its stamp'
                if defined $n->{stamp};
        }
    }
};

subtest 'a string value stays on one line' => sub {
    like $text, qr/^%\d+ = Constant const_type=string value="big\\n" : Str$/m,
        'the newline is escaped';
};

subtest 'a field naming a node is spelled as one' => sub {
    my ($phi) = grep { $_->{op} eq 'Phi' }
                map { $_->{nodes}->@* } values $wire->{methods}->%*;
    skip_all 'no Phi in this graph' unless $phi;
    like $text, qr/^%\Q$phi->{id}\E = Phi [^\n]*region=%\Q$phi->{fields}{region}\E/m,
        'region=%N';
};

subtest 'phase blocks are listed too' => sub {
    my $n = scalar(($wire->{phase_blocks} // [])->@*);
    ok $n, 'the program has a BEGIN block (use strict)' or return;
    my @h = $text =~ /^== BEGIN \d+ start=/mg;
    is scalar(@h), $n, 'one header per phase block';
};

is SoN::Render::WireText::render($wire), $text, 'rendering is deterministic';

done_testing;
