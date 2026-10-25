# ABOUTME: An element read after an element store takes the stored type only when it
# ABOUTME: reads the slot the store wrote; any other element is floored to Scalar.

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

# `$h{d} = 4` then a read of each sorted key: the key and its value were
# stamped Int, the type of the store their memory version was -- a store to
# ANOTHER slot. Chalk read the strings as integers and printed "0=0,0=0,0=0".
my $data  = graph_of(q{my %h = (b => 2, c => 3); $h{d} = 4; print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";});
my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by_id = map { $_->{id} => $_ } @nodes;
my @reads = grep { $_->{op} eq 'Subscript' && $_->{inputs}->@* == 3 } @nodes;
ok scalar(@reads), 'the reads are there';
for my $r (@reads) {
    isnt $r->{stamp}, 'Int', "read $r->{id} of another slot is not the store's Int";
}

# THE SAME SLOT keeps the store's type.
$data  = graph_of(q{my @a = (1); $a[0] = "foo"; print $a[0], "\n";});
@nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my ($same) = grep { $_->{op} eq 'Subscript' && $_->{inputs}->@* == 3 } @nodes;
is $same->{stamp}, 'Str', 'a read of the slot stored is the stored Str';

done_testing;
