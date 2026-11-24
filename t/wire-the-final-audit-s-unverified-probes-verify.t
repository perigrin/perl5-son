# ABOUTME: The three programs of the final audit that broke verifier rules (probes/f/unverified:
# ABOUTME: a55, d61, o11) give wires SoN::Verify passes (final audit 2026-11-24, section 3.3).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);
my $n = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return eval { decode_json($json) };
}

for my $c (
    # a `my` array a list assign fills, read whole after: at that version
    [ a55 => 'my @a=(1,2,3); my ($x,@a2)=@a; @a=(@a2,$x); print "@a\n";' ],
    # a division that may fault among sprintf's arguments: on the chain
    [ d61 => 'our $g=1; sub f { local $g=2; sprintf("%d", 1/$_[0]) } my $r = eval { f(0) }; print defined $r ? "v" : "d", " $g\n";' ],
    # a field array pushed to in a method: the field read at its version
    [ o11 => 'use feature "class"; no warnings; class Pt { field $x :param; field @h; method mv($d) { push @h,$x; $x+=$d; $self } method x { $x } method hist { scalar @h } } my $p=Pt->new(x=>1); $p->mv(1)->mv(1); print $p->x, $p->hist, "\n";' ],
) {
    my ( $name, $src ) = @$c;
    my $w = wire($src) or do { fail "$name: no wire"; next };
    is [ map { "$_->{rule} $_->{graph}" } SoN::Verify::verify($w)->{violations}->@* ], [], "$name: no violation";
}

done_testing;
