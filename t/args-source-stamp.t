# ABOUTME: `@_` is stamped Array -- it is an array of scalars, structurally always.
# ABOUTME: Its READERS stay typed from the callsite; the container type adds nothing there.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

# ArgsSource is `@_`: the argument list the caller built. Its type is Array --
# an array of scalars -- and that is true structurally, for every sub, with no
# inference required. It has storage, you can shift it, index it, take
# scalar @_. (`List` would be one level too wide: List is the flattening
# notion, what a comma expression yields in list context, and the backend
# refuses it as "signature vocabulary, not a value type".)
#
# It went unstamped, which made it the largest single class of untyped Value
# node reaching the end of chalk's analysis pipeline -- 6 of 9 roots measured
# across the 218-case corpus.
#
# WHAT THIS DOES NOT CHANGE, and the reason stamping it is safe: nothing reads
# ArgsSource as a value. `shift` and `$_[0]` produce their own nodes, typed
# from the callsite by the loader, and they stay that way. The container type
# is for the container.
#
# What it also does not fix: `my @a = @_` binds the whole list and so needs the
# ELEMENT type, which is the Array[Scalar] wall -- no boxed value
# representation exists. That shape stays a GAP.

sub nodes_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);

    my @nodes;
    for my $gname ( keys %{ $wire->{methods} // {} } ) {
        next if $gname =~ /PROGRAM/;
        push @nodes, @{ $wire->{methods}{$gname}{nodes} // [] };
    }
    return \@nodes;
}

subtest '@_ is stamped Array' => sub {
    for my $case (
        [ 'implicit shift', 'sub f { my $x = shift; return $x + 1 } f(2);' ],
        [ 'explicit @_',    'sub f { my $x = shift @_; return $x + 1 } f(2);' ],
        [ 'positional',     'sub f { return $_[0] + 1 } f(2);' ],
    ) {
        my ( $label, $src ) = @$case;
        my ($args) = grep { ( $_->{op} // '' ) eq 'ArgsSource' }
            @{ nodes_for( $src, $label =~ s/\W+/_/gr ) };
        ok $args, "$label: the ArgsSource node reached the wire";
        is $args->{stamp}, 'Array', "$label: stamped Array";
    }
};

subtest 'the readers keep their callsite types' => sub {
    # The point of the container stamp is that it changes nothing here. A
    # `shift` result is Int because the CALLER passed an Int, and that must
    # not become Array (or Scalar) now that its operand carries a type.
    my $nodes = nodes_for( 'sub f { my $x = shift; return $x + 1 } f(2);',
                           'reader_types' );
    my ($shift) = grep {
        ( $_->{op} // '' ) eq 'Call'
            && ( ( $_->{fields} // {} )->{name} // '' ) eq 'shift'
    } @$nodes;
    ok $shift, 'the shift Call reached the wire';
    isnt $shift->{stamp}, 'Array',
        'the shift RESULT is not the container type';
};

subtest 'a signature sub has no ArgsSource at all' => sub {
    # Signatures mint Parameter nodes instead, so they never route a
    # parameter read through @_. Recorded here so the two paths stay visibly
    # distinct: this is the shape that does NOT need the container stamp.
    my $nodes = nodes_for( 'sub f($x) { return $x + 1 } f(2);', 'sig_sub' );
    my @args  = grep { ( $_->{op} // '' ) eq 'ArgsSource' } @$nodes;
    is scalar(@args), 0, 'no ArgsSource in a signature sub';
    ok scalar( grep { ( $_->{op} // '' ) eq 'Parameter' } @$nodes ),
        'it has a Parameter instead';
};

done_testing;
