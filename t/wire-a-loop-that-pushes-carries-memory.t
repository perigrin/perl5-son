# ABOUTME: a loop whose body pushes onto an array carries memory through its header, so a
# ABOUTME: read after the loop is ordered after every pass -- not at a push inside the body.

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

# PUSH CHANGES MEMORY, like shift and pop. _body_stores_memory knew those and
# element stores, so `sub f { my @o; for (...) { push @o, $_ } join ",", @o }`
# had no header memory-Phi: the join read the memory of the push INSIDE the
# body (and with zero passes, memory no pass made).
for my $case (
    [ 'push',    q{sub f { my @o; for my $i (0 .. 2) { push @o, $i } return join ",", @o } print f(), "\n";} ],
    [ 'unshift', q{sub f { my @o; for my $i (0 .. 2) { unshift @o, $i } return join ",", @o } print f(), "\n";} ],
    [ 'splice',  q{sub f { my @o = (1, 2, 3); for my $i (0 .. 1) { splice @o, 0, 1 } return join ",", @o } print f(), "\n";} ],
) {
    my ($what, $src) = @$case;
    my $data  = graph_of($src);
    my @nodes = $data->{methods}{'main::f'}{nodes}->@*;
    my %by_id = map { $_->{id} => $_ } @nodes;
    my ($loop) = grep { $_->{op} eq 'Loop' } @nodes;
    ok( ( grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && ( $_->{fields}{region} // -1 ) == $loop->{id} } @nodes ),
        "$what: the loop carries a memory Phi" );
    my ($join) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' } @nodes;
    my $mem = $by_id{ $join->{inputs}[-1] };
    isnt $mem->{op}, 'Call', "$what: the join after the loop does not read a push inside it";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    if (defined $out) { is run_perl($out), run_perl($src), "$what: renders to the same output" }
    else              { like $d->gap // '', qr/\S/, "$what: or refuses it by name" }
}

done_testing;
