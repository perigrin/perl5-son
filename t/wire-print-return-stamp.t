# ABOUTME: `print` yields 1 or undef, so a sub whose body ends in print has a
# ABOUTME: derivable return type -- and an anon callee's type must reach its call.

use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::IR::Stamp;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err" or return ''; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub sub_return_type ( $w, $name ) {
    return ( ( ( $w // {} )->{classes}{main}{subs} // {} )->{$name} // {} )->{return_type};
}

sub call_stamps ( $w ) {
    my %s;
    for my $m ( keys( ( ( $w // {} )->{methods} // {} )->%* ) ) {
        for my $n ( ( $w->{methods}{$m}{nodes} // [] )->@* ) {
            next unless ( $n->{op} // '' ) eq 'Call';
            $s{ $n->{fields}{name} // '?' } = $n->{stamp} // 'Unknown';
        }
    }
    return %s;
}

# PROPAGATION ALREADY WORKS, and this is the control. A sub whose Return value
# is stamped gets a record, and the record reaches the callsite. Without this
# the two failures below could be misread as one broken pipeline.
subtest 'a typed callee reaches its callsite' => sub {
    my ( $w, $err ) = translate( 'sub f { 42 } my $x = f(); print $x;', 'typed' );
    ok $w, 'it translates' or do { diag($err); return };
    is sub_return_type( $w, 'f' ), 'Int', 'the sub record is Int';
    my %c = call_stamps($w);
    is $c{'main::f'}, 'Int', 'and the Call carries it';
};

# GAP 1 -- COMPUTE. `print` returns 1 on success and undef on failure
# (measured: `print ""` is 1; printing to a read-only handle is undef). The
# Print node carried no stamp at all, so a sub whose body ends in print had
# nothing to derive a return type FROM.
#
# The honest type is the lattice's join(Boolean,Undef), the same derivation
# `open` and `binmode` already use -- Boolean alone is WRONG rather than
# narrow, because Boolean does not admit undef.
#
# The producer already knew this in prose: Print.pm's ABOUTME says "yielding
# print's boolean 1" and FromOptree says "print returns 1; push it so a value
# context reads the return" -- and then pushed it unstamped.
subtest 'print is typed, so a print-bodied sub has a return type' => sub {
    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Boolean' ),
        SoN::IR::Stamp->new( type => 'Undef' ),
    )->type;
    is $lub, 'Scalar', 'the lattice puts join(Boolean,Undef) at Scalar';

    my ( $w, $err ) = translate( 'sub g { print "" } my $y = g(); print $y;', 'print-body' );
    ok $w, 'it translates' or do { diag($err); return };

    is sub_return_type( $w, 'g' ), $lub,
        "a sub whose body ends in print returns $lub";
    my %c = call_stamps($w);
    is $c{'main::g'}, $lub, '... and the callsite carries it';
};

# GAP 2 -- PROPAGATE. An anon callee's type IS computable (its Return value is
# a stamped Constant) and never reached the callsite, for two independent
# reasons: no sub record is created for an anon body, and the pkg/bare name
# split cannot parse `main::__PROGRAM__::__ANON__:1:2` -- its `[^:]+` tail
# cannot match `1:2`, so the whole match fails and the fallback looks up a
# key that never exists.
subtest 'an anon callee type reaches its callsite' => sub {
    my ( $w, $err ) = translate( 'my $c = sub { "a" }; my $v = $c->(); print $v;', 'anon' );
    ok $w, 'it translates' or do { diag($err); return };

    my %c = call_stamps($w);
    my ($anon) = grep { /__ANON__/ } keys %c;
    ok $anon, 'the program calls an anon body' or return;
    isnt $c{$anon}, 'Unknown',
        'the call is typed from the anon body it names';
};

done_testing;
