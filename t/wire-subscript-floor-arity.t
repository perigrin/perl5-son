# ABOUTME: A Subscript with no memory edge is still one scalar slot.
# ABOUTME: The floor keyed on 3 inputs, so aelemfast stores were left Unknown.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub nodes_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { ( $wire->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $wire->{methods} // {} )->%* ) ];
}

# THE DEFECT. `$x[0] = 'foo'` compiles to a single `aelemfast[*x] sM` -- no
# separate memory operand -- so its Subscript carries TWO inputs, the array and
# the index. _floor_subscripts began `next if @in < 3`, written for the
# value-read shape where the third input IS the memory edge, so it skipped this
# node entirely and it reached the wire as Unknown.
#
# The floor's own reasoning never depended on that arity: one element is one
# scalar slot, whatever the container holds and however the op was spelled.
subtest 'a two-input Subscript is floored to Scalar' => sub {
    my $nodes = nodes_for( q{$x[0] = 'foo'; $x[1] = 'bar';}, 'aelemfast' );
    my @subs  = grep { ( $_->{op} // '' ) eq 'Subscript' } $nodes->@*;

    ok scalar(@subs), 'the graph has Subscript nodes' or return;
    is scalar( grep { ( $_->{stamp} // '' ) eq 'Unknown' } @subs ), 0,
        'none of them reach the wire Unknown';
};

# THE STRONGER ANSWER STILL WINS where the memory edge is present. Without this
# the fix could regress the read case to a blanket Scalar.
subtest 'a threaded read still takes the stored type' => sub {
    my $nodes = nodes_for( q{my @a; $a[0] = "foo"; my $v = $a[0]; print $v;},
                           'threaded' );
    my @subs  = grep { ( $_->{op} // '' ) eq 'Subscript' } $nodes->@*;

    ok scalar(@subs), 'the graph has Subscript nodes' or return;
    ok scalar( grep { ( $_->{stamp} // '' ) eq 'Str' } @subs ),
        'a read threaded to a Str store is Str, not floored to Scalar';
};

done_testing;
