# ABOUTME: `exit N` as a sub's last statement is on the control chain: it runs in
# ABOUTME: the caller's context, not void, and was dropped there.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# `sub f { print "e\n"; exit 4 } f(); print "after\n"` printed "after" and
# exited 0 through chalk: the exit (want=scalar, the sub's value) was neither
# pinned nor kept. An END block's trailing exit was dropped the same way.
for my $case (
    [ q{sub f { print "e\n"; exit 4 } f(); print "after\n";}, 'main::f' ],
    [ q{sub f { print "e\n"; exit(4); } f();}, 'main::f' ],
) {
    my ($src, $g) = @$case;
    my $nodes = graph_of($src)->{methods}{$g}{nodes} // [];
    my ($exit) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'exit' } @$nodes;
    ok $exit && defined( $exit->{control_in} // $exit->{control} ), "the exit is on the chain: $src";
}

done_testing;
