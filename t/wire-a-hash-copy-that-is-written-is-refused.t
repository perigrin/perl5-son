# ABOUTME: `my %c = %h` binds %c to %h's node on the wire, so a later write to the copy would change
# ABOUTME: the original: refused by name when the copy may be written; a copy only read still lowers.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# RE-AUDIT 2026-11-23, class A (probes/r k*, n*): the wire had no node for the
# copy -- a store to $c{a} was a Subscript of %h's HashLiteral. chalk printed
# `blue blue` for perl's `red blue`:
#   my %defaults=(color=>"red"); my %opt=%defaults; $opt{color}="blue";
# The copy wants its own node (a design the user holds); until then refused.
my $GAP = qr/GAP: a copy of a hash that may then be written is not yet lowered/;
my %refused = (
    'an element store'         => 'my %h=(a=>1); my %c=%h; $c{a}=2; print "$h{a}\n";',
    'a delete'                 => 'my %h=(a=>1); my %c=%h; delete $c{a}; print exists $h{a} ? "y":"n","\n";',
    'an increment'             => 'my %h=(a=>1); my %c=%h; $c{a}++; print "$h{a} $c{a}\n";',
    'an assign, not a my'      => 'my %h=(a=>1); my %c; %c=%h; $c{a}=2; print "$h{a}\n";',
    'a parenthesised source'   => 'my %h=(a=>1); my %c=(%h); $c{a}=2; print "$h{a}\n";',
    'a package hash target'    => 'my %h=(a=>1); our %c=%h; $c{a}=2; print "$h{a}\n";',
    'a slice store'            => 'my %h=(a=>1); my %c=%h; @c{qw(a b)}=(5,6); print join(",",sort keys %h),"\n";',
    'a store through a ref'    => 'my %h=(a=>1); my %c=%h; my $r=\%c; $r->{a}=2; print "$h{a}\n";',
    'a local element'          => 'my %h=(a=>1); my %c=%h; local $c{a}=2; print "$h{a}\n";',
    'a copy of a copy'         => 'my %h=(a=>1); my %c=%h; my %d=%c; $d{a}=3; print "$h{a}$c{a}$d{a}\n";',
    'in a sub'                 => 'sub f { my %o=(v=>1); my %c=%o; $c{v}=2; return $o{v} } print f(),"\n";',
    'a hash from @_'           => 'sub f { my %h=@_; my %c=%h; $c{a}=2; $h{a} } print f(a=>1),"\n";',
    'flattened as a call arg'  => 'my %h=(a=>1); my %c=%h; sub w { $_[1]=2 } w(%c); print "$h{a}\n";',
    'a foreach over its pairs' => 'my %h=(a=>1); my %c=%h; $_ = 2 for values %c; print "$h{a}\n";',
);
for my $what (sort keys %refused) {
    like warnings_of($refused{$what}), $GAP, "refused: $what";
}

# A copy nothing writes reads the same as the original: still lowered.
unlike warnings_of('my %h=(a=>1); my %c=%h; print "$c{a}\n"; print join(",", keys %c), "\n";'),
    qr/GAP:/, 'a copy only read is not refused';
# A copy whose SOURCE is written is made where it stands (the literal copy).
unlike warnings_of('my %h=(a=>1); my %c=%h; $h{a}=5; print "$c{a}\n";'),
    qr/GAP:/, 'a copy whose source is written is not refused';

done_testing;
