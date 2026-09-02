# ABOUTME: A slice is stamped List -- it is not a scalar and has no type of its own.
# ABOUTME: @a[1..3] and (qw(b c))[0] are the same node kind: a plural read.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub slice_stamps ($src, $name) {
    my $wire = wire_for($src, $name);
    return [ map { $_->{stamp} }
             grep { $_->{op} eq 'Slice' }
             ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ];
}

# SLICE IS NOT A TYPE, IT IS A PLURAL READ. The lattice has no Slice member and
# should not gain one: `@a[1..3]` yields as many values as it has indices, which
# is what List means. Measured on 5.42.0, a slice behaves as a list in every
# context that distinguishes them:
#
#     my @s = @a[1..3];   scalar(@s) == 3   -- plural in list context
#     my $x = @a[1..3];   $x == 4           -- LAST element, the comma operator
#     my ($p) = @a[1..3]; $p == 2           -- first, like any list
#
# That last-element rule is the giveaway: a scalar-typed node would yield its
# own single value. Only a list collapses to its final element.
subtest 'an array slice is a List' => sub {
    my $s = slice_stamps('my @a = (1,2,3,4,5); my @s = @a[1..3]; print "@s";', 'aslice');
    ok scalar($s->@*) >= 1, 'the slice node exists' or return;
    is $s->[0], 'List', 'an array slice is plural, so it is a List';
};

# THE LIST-LITERAL SLICE, which lowers through a different op (lslice, a fixed
# 2-pop) than the aggregate slices ('mark'). Both are Slice nodes and both are
# lists; if only one path is stamped the other silently keeps Unknown.
subtest 'a list-literal slice is a List' => sub {
    my $s = slice_stamps(q{my $r = (qw(b c))[0]; print $r;}, 'lslice');
    ok scalar($s->@*) >= 1, 'the slice node exists' or return;
    is $s->[0], 'List', 'a slice of a literal list is still a List';
};

# THE HASH SLICE. @h{...} is plural for the same reason, and shares the 'mark'
# path with aslice -- asserted so a fix keyed on the array ops alone is caught.
subtest 'a hash slice is a List' => sub {
    my $s = slice_stamps('my %h = (a=>1, b=>2); my @v = @h{qw(a b)}; print "@v";', 'hslice');
    ok scalar($s->@*) >= 1, 'the slice node exists' or return;
    is $s->[0], 'List', 'a hash slice is plural, so it is a List';
};

# NEVER UNKNOWN. This is the property that actually matters downstream: chalk
# compiles ahead of time, so Unknown is a hole in the emitted program rather
# than a missing annotation. Every slice, on every path, must say something.
subtest 'no slice reaches the wire Unknown' => sub {
    for my $case (
        ['my @a=(1,2,3); my @s=@a[0,1]; print "@s";',            'nu_aslice'],
        [q{my $r = (qw(b c))[0]; print $r;},                      'nu_lslice'],
        ['my %h=(a=>1); my @v=@h{"a"}; print "@v";',              'nu_hslice'],
        ['my @a=(1,2,3); my %kv=%a[0,1]; print scalar(keys %kv);','nu_kvaslice'],
    ) {
        my ($src, $name) = $case->@*;
        my $s = slice_stamps($src, $name);
        next unless scalar($s->@*);
        for my $stamp ($s->@*) {
            isnt $stamp, 'Unknown', "$name: the slice is not a hole";
        }
    }
};

done_testing;
