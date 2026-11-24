# ABOUTME: `$$r += 10` and `${"name"} += 10` yield the location after the store: that read
# ABOUTME: names the store as its memory version (mem_in), not as a plain operand.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null);
}

sub wire_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return eval { JSON::PP->new->decode($j) };
}

# (probe aun6 is the first: the read was `PostfixDeref [name, Assign]`, no mem_in)
for my $case (
    [ 'a symbolic reference, the sub\'s value (probe aun6)', 'main::bump',
        q{our $g=0; sub bump { no strict 'refs'; ${"main::g"} += 10 } for (1..3){ $g=$g+1; bump() } print "$g\n";} ],
    [ 'a hard reference, the sub\'s value', 'main::bump',
        q{our $g=0; my $r=\$g; sub bump { $$r += 10 } for (1..3){ bump() } print bump(), " $g\n";} ],
    [ 'a hard reference, the value assigned', 'main::__PROGRAM__',
        q{my $v = 1; my $r = \$v; my $w = ($$r += 5); $v = 0; print "$w $v\n";} ],
) {
    my ( $what, $graph, $src ) = $case->@*;
    subtest $what => sub {
        my $w = wire_of($src) or return fail 'a wire';
        my @n = $w->{methods}{$graph}{nodes}->@*;
        my ($store) = grep { $_->{op} eq 'Assign' && grep { my $i = $_; grep { $_->{id} == $i && $_->{op} eq 'Add' } @n } $_->{inputs}->@* } @n;
        ok $store, 'the compound store' or return;
        my @after = grep { $_->{op} eq 'PostfixDeref' && ( $_->{mem_in} // -1 ) == $store->{id} } @n;
        is scalar(@after), 1, 'one read of the location at the store\'s version';
        is [ grep { $_->{op} eq 'PostfixDeref' && grep { $_ == $store->{id} } $_->{inputs}->@* } @n ], [],
            'no read takes the store as a plain operand';
        is [ grep { $_->{rule} =~ /\Aread-unversioned/ } SoN::Verify::verify($w)->{violations}->@* ], [],
            'the verifier finds no unversioned read';
        my $d   = SoN::Deparse->new;
        my $out = $d->render($w);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
