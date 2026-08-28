# ABOUTME: An aggregate signature parameter is stamped Array/Hash from its sigil.
# ABOUTME: A scalar parameter is NOT stamped: its type comes from the callsite.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

# `sub f($x, @rest)` gives @rest the type Array -- the CONTAINER, not the
# ArrayRef that would point at one. `%opt` is a Hash for the same reason. The
# sigil on the argelem op says which, and it is the only thing that can: a
# slurpy is not always an array.
#
# This did not used to be stamped. The handler carried a comment saying the
# lattice "has neither" Array nor Hash and that stamping one died "Unknown
# stamp type" -- both false by the time it was read: SoN::IR::Stamp carries
# `Array => [List]` and `Hash => [List]` and constructs either happily. The
# comment outlived its condition.
#
# It survived unnoticed because the failure it described was SILENT: the die
# was swallowed by a bare `eval` in B::SoN, dropping the whole sub from the
# wire with no diagnostic. Those sites now report (GAP or internal error,
# distinguished), which is what makes stamping here safe -- a mistake
# announces itself rather than deleting a sub.

sub params_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);

    my @params;
    for my $g ( values %{ $wire->{methods} // {} } ) {
        for my $node ( @{ $g->{nodes} // [] } ) {
            next unless ( $node->{op} // '' ) eq 'Parameter';
            # Node-specific data rides under `fields`; `stamp` is top-level.
            push @params, {
                sigil => ( $node->{fields} // {} )->{sigil},
                stamp => $node->{stamp},
            };
        }
    }
    return \@params;
}

subtest 'a slurpy array parameter is stamped Array' => sub {
    my $p = params_for( 'sub f($x, @rest) { return scalar(@rest) } f(1,2,3);',
                        'slurpy_array' );
    my ($ary) = grep { ( $_->{sigil} // '' ) eq '@' } @$p;
    ok $ary, 'the @rest parameter reached the wire';
    is $ary->{stamp}, 'Array',
        'stamped Array -- the container, not an ArrayRef to one';
};

subtest 'a slurpy hash parameter is stamped Hash' => sub {
    my $p = params_for( 'sub g($x, %opt) { return scalar(keys %opt) } g(1, a=>2);',
                        'slurpy_hash' );
    my ($h) = grep { ( $_->{sigil} // '' ) eq '%' } @$p;
    ok $h, 'the %opt parameter reached the wire';
    is $h->{stamp}, 'Hash',
        'stamped Hash -- a slurpy is NOT always an array';
};

# UPDATED. The original said: "this end cannot see the callsite, so guessing a
# type here would be inventing one. The loader binds it from the caller's
# argument." The first half is true and the CONCLUSION does not follow -- and
# the second half is the unsound direction.
#
# `sub h($x, $y) { return $x + $y }` constrains both parameters through the
# BODY: `+` is numeric, so $x and $y are Num. That is not a guess about callers,
# it is what the operator requires of whatever arrives. Ordinary type inference
# does exactly this -- HM emits T($x) == Num from the same expression, abstract
# interpretation narrows from the use site.
#
# And binding from the callsite is what WOULD be unsound: h(1,2) says Int, while
# h(1.5,2) is equally legal. The body's Num is correct for every caller; the
# callsite's Int is correct for one.
#
# A parameter NO operator constrains is still untyped -- see the last case.
subtest 'a scalar parameter takes the type its body requires' => sub {
    my $p = params_for( 'sub h($x, $y) { return $x + $y } h(1,2);',
                        'scalar_params' );
    my @scalars = grep { ( $_->{sigil} // '$' ) eq '$' } @$p;
    ok scalar(@scalars), 'the scalar parameters reached the wire';
    for my $s (@scalars) {
        is $s->{stamp}, 'Num',
            "$s->{name}: `+` puts it in numeric context, so it is Num";
    }
};

subtest 'an unconstrained scalar parameter stays unstamped' => sub {
    # The half of the original premise that survives: with no operator imposing
    # anything, this end genuinely has nothing to say, and does not invent it.
    my $p = params_for( 'sub id($x) { return $x } id(1);', 'unconstrained_param' );
    my @scalars = grep { ( $_->{sigil} // '$' ) eq '$' } @$p;
    ok scalar(@scalars), 'the scalar parameter reached the wire';
    for my $s (@scalars) {
        ok !defined $s->{stamp} || $s->{stamp} eq 'Unknown',
            'nothing constrains it, so nothing is claimed';
    }
};

done_testing;
