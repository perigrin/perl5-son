# ABOUTME: A list assign yields by its context: in a list the targets as they are after it, in a
# ABOUTME: scalar the count of its right side; its right side's mark is its own, not an enclosing list's.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# reads_at_versions($rule_re, [what, src], ...): each wire has no violation of
# the rules matched, and the deparser's rendering prints what perl prints.
sub reads_at_versions ( $rule, @cases ) {
    for my $case (@cases) {
        my ( $what, $src ) = $case->@*;
        subtest $what => sub {
            my $data = graph_of($src) or return fail 'a wire';
            my @bad  = grep { $_->{rule} =~ $rule } SoN::Verify::verify($data)->{violations}->@*;
            is [ map { "$_->{graph} $_->{op}#$_->{node} $_->{rule} $_->{detail}" } @bad ], [], 'every read names a version';
            my $d   = SoN::Deparse->new;
            my $out = $d->render($data);
            ok defined $out, 'the deparser renders it' or diag $d->gap;
            is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
        };
    }
}

# Found in stage 6 and left (docs/memory/a-call-s-stores-are-its-mod-set.md):
# `print $x, (($x, $y) = (5, 6))` printed 56 for perl's 556 -- the right
# side's mark was left on the stack, hiding $x from the print -- and
# `scalar(($x, $y) = ...)` came back from the deparser as the list.
reads_at_versions( qr/\A(?!)/,
    [ 'an operand before a list assign in a print', q{my ($x, $y) = (1, 2); print $x, (($x, $y) = (5, 6)), "\n";} ],
    [ 'a constant before it', q{my ($x, $y) = (1, 2); print 7, (($x, $y) = (5, 6)), "\n";} ],
    [ 'an array among the targets', q{my ($x, @r) = (1, 2); print $x, (($x, @r) = (5, 6)), "\n";} ],
    [ 'scalar() of it', q{my ($x, $y); print scalar(($x, $y) = (7, 8, 9)), "\n";} ],
    [ 'scalar() of it, an array among the targets', q{my ($x, @r); print scalar(($x, @r) = (7, 8, 9)), "\n";} ],
    [ 'scalar() of it from a call', q{sub f { return (4, 5, 6) } my ($x, $y); print scalar(($x, $y) = f()), "$x$y\n";} ],
    [ 'its list copied', q{my ($x, $y); my @l = (($x, $y) = (1, 2, 3)); print scalar(@l), "@l\n";} ],
);

done_testing;
