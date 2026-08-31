# ABOUTME: `EXPR while COND` inside an if/else arm translates like one outside.
# ABOUTME: The `enter` handler lived in the main walk, unreachable from an arm.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT, and the same shape enteriter had. A postfix while compiles to
# enter/leave with a back-edge -- the and/or's body arm ends in an `unstack`
# that jumps back to the condition head -- and it is detected at `enter` in the
# MAIN walk loop. _walk_branch only calls _step, so the identical loop inside
# an if/else arm hit the back-edge with no handler and was refused as
# "statement-modifier loop or unhandled op inside an if/else arm".
#
# Measured both ways before the change: `1 while $n++ < 3` translates at
# statement level and refuses inside an arm.
# WHAT IS BUILT: the loop SHAPE is now recognised from inside an arm --
# _and_is_loop_back_edge asks whether the and/or's body arm ends in an unstack
# that jumps to something already on the walked path. That question could not
# be asked before; the arm handler saw an ordinary statement modifier.
#
# WHAT IS NOT: giving _translate_while_loop the entry state it needs. It
# expects the CONDITION HEAD (enter->next) plus the pre-loop bindings the main
# walk has established by then. Entered at the and/or from inside an arm it has
# neither, and the graph it builds is measurably wrong -- NumLt(Constant,
# Constant), the condition disconnected from $n's increment, a Loop with no
# loop-carried Phi. That is a silent miscompile, so the construct stays refused.
subtest 'a postfix while in an arm translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0;
if ($ARGV[0]) { 1 while $n++ < 3 } else { $n = 9 }
print $n;', 'while-in-then' );
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/statement-modifier loop|postfix-while/,
        'no loop-in-arm GAP';
};

# THE LOOP MUST BE CONNECTED TO ITS OWN INDUCTION VARIABLE. This is the case
# that made an earlier attempt a silent miscompile: entering the translator at
# the and/or (rather than the condition head) built a Loop whose test was
# NumLt(Constant, Constant) -- $n's increment never reached it, so the trip
# count was whatever the constants said. Asserting "a Loop exists" would have
# passed that graph.
subtest 'the arm loop condition reads the induction Phi' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0;
if (1) { 1 while $n++ < 3 } else { $n = 9 }
print $n;', 'while-connected' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my ($lt) = grep { ( $_->{op} // '' ) eq 'NumLt' } $ns->@*;
    ok $lt, 'the loop test is in the graph' or return;

    my @in = map { $by{$_} } ( $lt->{inputs} // [] )->@*;
    ok scalar( grep { ( $_->{op} // '' ) eq 'Phi' } @in ),
        'and one operand is the loop-carried Phi, not a pre-loop constant';
};

# THE SHAPE TEST ITSELF IS RIGHT, and is what the refusal above now keys on.
# Without this, a detector that answered "not a loop" would also pass the
# subtest above -- by taking the statement-modifier path and refusing there.
subtest 'the back-edge detector distinguishes a loop from a modifier' => sub {
    require B;
    require SoN::OptSuppress;
    require SoN::FromOptree;

    SoN::OptSuppress::suppress_peep();
    my %cv = (
        loop     => eval q{sub { my $n = 0; 1 while $n++ < 3; $n }},
        modifier => eval q{sub { my $n = 0; $n = 5 if $n < 3; $n }},
    );
    SoN::OptSuppress::restore_peep();

    my $and_of = sub ( $cv ) {
        my ($found, $walk);
        $walk = sub ( $o ) {
            return unless ref($o) && $$o && !$found;
            $found = $o if $o->name eq 'and' || $o->name eq 'or';
            return unless !$found && ( $o->flags & 4 );
            for ( my $k = $o->first; ref($k) && $$k; $k = $k->sibling ) {
                $walk->($k);
            }
        };
        $walk->( B::svref_2object($cv)->ROOT );
        return $found;
    };

    my $loop_and = $and_of->( $cv{loop} );
    my $mod_and  = $and_of->( $cv{modifier} );
    ok $loop_and && $mod_and, 'both shapes have an and/or' or return;

    ok SoN::FromOptree::_and_is_loop_back_edge(
           $loop_and, B::svref_2object( $cv{loop} )->START ),
        'a postfix while is seen as a back-edge';
    ok !SoN::FromOptree::_and_is_loop_back_edge(
           $mod_and, B::svref_2object( $cv{modifier} )->START ),
        'a plain statement modifier is not';
};

# UNCHANGED AT STATEMENT LEVEL -- the form that already worked, which a bad
# move would break invisibly to the arm tests above.
subtest 'a postfix while outside any arm still translates' => sub {
    my ( $w, $err ) = translate(
        'my $n = 0; 1 while $n++ < 3; print $n;', 'while-plain' );
    ok $w, 'it translates' or diag($err), return;
    my @ops = map { $_->{op} // '' } nodes($w)->@*;
    ok scalar( grep { $_ eq 'Loop' } @ops ), 'a Loop node exists';
};

done_testing;
