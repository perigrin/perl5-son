# ABOUTME: `local $g;` gives $g a new scalar, undef: the wire stores undef there, and a read after
# ABOUTME: it names that store; `local $g = 5` stores only its value.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (third final audit, N8, y/yj37): `our $g=1; sub t { local $g;
# defined $g ? "d" : "u" }` printed `d` for perl's `u`. The walk saved $g for
# the restore and stored nothing, so the read after the local read $g's own
# value. perlsub: "local ... the variable is undefined" when no value is
# assigned.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub graphs ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
    return decode_json($json)->{methods};
}

# undef_stores($graph) -> how many EntryWrites store a Constant undef, and
# whether a read of $g names one of them.
sub undef_stores ($g) {
    my %by = map { ( $_->{id} => $_ ) } $g->{nodes}->@*;
    my %undef_w = map { ( $_->{id} => 1 ) } grep {
        $_->{op} eq 'EntryWrite' && do { my $v = $by{ $_->{inputs}[1] }; $v->{op} eq 'Constant' && $v->{fields}{const_type} eq 'undef' }
    } $g->{nodes}->@*;
    my $read = grep { $_->{op} eq 'EntryDef' && defined $_->{mem_in} && $undef_w{ $_->{mem_in} } } $g->{nodes}->@*;
    return ( scalar keys %undef_w, $read );
}

for my $src (
    'our $g=1; sub t { local $g; defined $g ? "d" : "u" } print t(), $g, "\n";',
    'our $g=1; sub t { local ($g); defined $g ? "d" : "u" } print t(), $g, "\n";',
    'our ($g,$h)=(1,2); sub t { local ($g, $h); defined $g ? "d" : "u" } print t(), $g, "\n";',
) {
    my ( $w, $read ) = undef_stores( graphs($src)->{'main::t'} );
    ok $w,    "a store of undef: $src";
    ok $read, "the read after it names it: $src";
}

# (the undef store's target is the variable at its version, not the node
# the restore stores into: a consumer reads a target two stores share as no
# one version -- chalk refused `eval { local $@; ... }`, z/un19, gates5)
{
    my $g = graphs('our $g=1; sub t { local $g; defined $g ? "d" : "u" } print t(), $g, "\n";')->{'main::t'};
    my %by = map { ( $_->{id} => $_ ) } $g->{nodes}->@*;
    my %writes;
    $writes{ $_->{inputs}[0] }++ for grep { $_->{op} eq 'EntryWrite' } $g->{nodes}->@*;
    is [ grep { $writes{$_} > 1 } sort keys %writes ], [], 'no two stores share a target';
}

my ($w) = undef_stores( graphs('our $g=1; sub t { local $g = 5; $g } print t(), $g, "\n";')->{'main::t'} );
is $w, 0, '`local $g = 5` stores no undef first';

done_testing;
