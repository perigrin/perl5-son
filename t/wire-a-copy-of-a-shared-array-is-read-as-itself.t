# ABOUTME: `my @c = @a` of an array a sub also reaches: a read of @c is @c's literal, not the
# ABOUTME: source it was copied from at a version (final audit 2026-11-24, class A).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!;
    return ( (eval { decode_json($json) }), join '', <$e> );
}

# What the program's joins (`"@c"`) and counts read whole: `@name`, by the
# literal's symbol or the PadAccess's -- the copy's name, never its source's.
sub joined ($w, $graph = 'main::__PROGRAM__') {
    my $g = $w->{methods}{$graph} or return 'no graph';
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my %seen;
    for my $n (grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' } $g->{nodes}->@*) {
        for my $in ( $n->{inputs}->@[ 1 .. $#{ $n->{inputs} } ] ) {
            my $x = $by{$in} or next;
            $seen{ "$x->{op} \@" . ( $x->{fields}{symbol} // '?' ) } = 1 if ( $x->{fields}{sigil} // '' ) eq '@';
        }
    }
    return join ', ', sort keys %seen;
}

# Before: the join took the PadAccess of @a -- read after w() stored into it,
# so `"@c"` printed 9 2 for perl's 1 2.
for my $c (
    [ 'my @a=(1,2); sub w { $a[0]=9 } my @c=@a; w(); print "@c\n";' ],
    [ 'my @a=(1,2); sub w { push @a,3 } my @c=@a; w(); print "@c\n";' ],
    [ 'my @a=(1,2); my $w=sub { $a[0]=9 }; my @c=@a; $w->(); print "@c\n";' ],
    [ 'my @a=(1,2); sub w { $a[0]=9 } my @c=(@a); w(); print "@c\n";' ],
    [ 'my @a=(1,2); sub w { $a[0]=9 } my @c=@a; for (1..2) { w() } print "@c\n";' ],
    [ 'my @a=(1,2); sub w { $a[0]=9 } my @c=(0,@a); w(); print "@c\n";' ],
    [ 'my @a=(1,2); sub w { $a[0]=9 } my @c=@a; if (@c) { w() } print "@c\n";' ],
    # (in a sub, the shared @a is read with no version: a location still)
    [ 'my @a=(1,2); sub w { $a[0]=9 } sub f { my @c=@a; w(); "@c" } print f(),"\n";', 'main::f' ],
) {
    my ( $src, $graph ) = @$c;
    my ( $w, $err ) = translate($src);
    unlike joined( $w // {}, $graph // 'main::__PROGRAM__' ), qr/\@a\b/, "\"\@c\" does not read \@a: $src" or diag $err;
}

done_testing;
