# ABOUTME: A `my` array or hash the graph writes, read whole, is read at a memory version (a
# ABOUTME: PadAccess with mem_in), not as its slot: a later write does not reach the copy.

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

# Wire v2 stage 7, the `my-aggregate` row of the read rule (V6). `my @x;`
# binds the slot itself, and a whole read of it was that one node: chalk made
# `my @c = @x` after the next push (1 2|1 2 for 1|1 2).
for my $case (
    [ 'a copy between two pushes', q{my @x; push @x, 1; my @c = @x; push @x, 2; print "@c|@x\n";} ],
    [ 'returned whole (corpus 249)', q{sub f { my @p; push @p, "a", "b"; return @p } my @r = f(); my $n = f(); print "@r $n\n";} ],
    [ 'a hash copied between two stores',
        q{sub f { my %h; $h{a} = 1; my %c = %h; $h{b} = 2; return join(",", sort keys %c) . "|" . join(",", sort keys %h) } print f(), "\n";} ],
) {
    my ( $what, $src ) = $case->@*;
    subtest $what => sub {
        my $data = graph_of($src) or return fail 'a wire';
        my @bad  = grep { $_->{rule} eq 'read-unversioned:my-aggregate' } SoN::Verify::verify($data)->{violations}->@*;
        is [ map { "$_->{graph} $_->{op}#$_->{node} $_->{detail}" } @bad ], [], 'every whole read of it names a version';
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
