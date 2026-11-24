# ABOUTME: `my %c = %h` makes a new location (design A, docs/plans/2026-11-24-copy-and-local-unwind.md):
# ABOUTME: the wire has a HashLiteral of its own for the copy, read from the source's, in every shape.
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

# A HashLiteral whose one input is another HashLiteral: the copy, read from the
# source at the point it is made. Before design A a copy nothing wrote was the
# source's own node, and one that might be written was refused (re-audit
# 2026-11-23, class A: `my %opt = %defaults; $opt{color} = "blue"` changed
# %defaults).
sub copies ($w) {
    my @c;
    for my $m (values $w->{methods}->%*) {     # (node ids are per graph)
        my %by = map { $_->{id} => $_ } $m->{nodes}->@*;
        push @c, grep {
            $_->{op} eq 'HashLiteral' && $_->{inputs}->@* == 1
                && ($by{ $_->{inputs}[0] }{op} // '') eq 'HashLiteral'
        } $m->{nodes}->@*;
    }
    return @c;
}

my %cases = (
    'only read'                => 'my %h=(a=>1); my %c=%h; print "$c{a}\n"; print join(",", keys %c), "\n";',
    'the source written'       => 'my %h=(a=>1); my %c=%h; $h{a}=5; print "$c{a}\n";',
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
    'in a loop'                => 'my %h=(a=>1); for my $i (1..2) { my %c=%h; $c{a}+=$i; print "$c{a}\n" } print "$h{a}\n";',
);
for my $what (sort keys %cases) {
    my ($w, $err) = translate($cases{$what});
    unlike $err, qr/GAP:/, "$what: not refused";
    ok scalar(copies($w // { methods => {} })), "$what: the copy is a literal of its own";
}

# A `my` hash read among other pairs is read where the list is made, too:
# floating, `my %d=(%h,x=>1); $h{a}=2; print $d{a}` printed 2 for perl's 1
# (probe cpa21; ren27 the same through a copy).
{
    my ($w) = translate('my %h=(a=>1); my %d=(%h,x=>1); $h{a}=2; print "$d{a}\n";');
    my ($d) = grep { $_->{op} eq 'HashLiteral' && ($_->{fields}{symbol} // '') eq 'd' }
        $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    ok defined $d->{control_in}, 'a hash among other pairs: the literal is made where it stands';
}

# ... and an array made of a `my` hash is read as that array, not as the hash:
# the padav shortcut pushed the literal's inputs, so `"@l"` joined %h itself,
# after a later store (`my @l=(%h); $h{a}=2; print "@l"`: perl a 1, chalk a 2;
# probes cpa23, cpa30, cpa31).
{
    my ($w) = translate('my %h=(a=>1); my @l=(%h); $h{a}=2; print "@l\n";');
    my @n = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($join) = grep { $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'join' } @n;
    is [ map { $by{$_}{op} } $join->{inputs}->@* ], [ 'Coerce', 'ArrayLiteral' ],
        'an array of a hash: the join reads the array';
}

done_testing;
