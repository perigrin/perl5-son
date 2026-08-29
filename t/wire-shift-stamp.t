# ABOUTME: shift/pop of @_ reaches the wire as Scalar, never Unknown.
# ABOUTME: One element of an aggregate is a scalar, whatever the caller passed.
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

sub shift_stamp ($src, $name, $graph) {
    my $wire = wire_for($src, $name);
    my ($call) = grep {
        $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) =~ /^(shift|pop)$/
    } ( $wire->{methods}{$graph}{nodes} // [] )->@*;
    return undef unless $call;
    return $call->{stamp};
}

# THE DEFECT. `my $n = shift` is `shift @_`, and @_ is right there in the graph
# as an ArgsSource stamped Array. shift returns ONE element of it, so the result
# is a scalar -- yet it reached the wire Unknown, and that Unknown propagated:
# the sub's return_type became Unknown and so did every call to it. Measured
# over chalk's corpus, shift was 5 roots with most of the 21 callee-return
# cascades behind it.
#
# `shift @a` over a literal array ALREADY stamped its element type, so the rule
# existed; it simply never reached @_.
subtest 'bare shift is a Scalar, not a hole' => sub {
    my $s = shift_stamp('sub f { my $n = shift; return $n } say(f(7));',
                        'bare', 'main::f');
    isnt $s, 'Unknown', 'shift of @_ is not left unanswered';
    is $s, 'Scalar', 'one element of @_ is a scalar';
};

# `shift` and `shift @_` are the same operation and must agree.
subtest 'explicit shift @_ agrees with the bare form' => sub {
    my $s = shift_stamp('sub f { my $n = shift @_; return $n } say(f(7));',
                        'expl', 'main::f');
    is $s, 'Scalar', 'shift @_ is a scalar';
};

subtest 'pop of @_ is likewise a Scalar' => sub {
    my $s = shift_stamp('sub f { my $n = pop @_; return $n } say(f(7));',
                        'popargs', 'main::f');
    is $s, 'Scalar', 'one element of @_ is a scalar';
};

# THE FLOOR IS A FLOOR. Where the element type IS derivable, it must still win:
# Scalar where Int is provable is also a T1 failure, just a less obvious one.
subtest 'a literal array still narrows past the floor' => sub {
    my $s = shift_stamp('sub f { my @q = (1,2,3); my $x = shift @q; return $x } say(f());',
                        'literal', 'main::f');
    is $s, 'Int', 'shift of an all-Int array still reads Int, not the floor';
};

subtest 'a mixed literal array joins, and still beats the floor' => sub {
    my $s = shift_stamp('sub f { my @q = (1,"x"); my $x = shift @q; return $x } say(f());',
                        'mixed', 'main::f');
    is $s, 'Str', 'join(Int,Str) is Str -- narrower than Scalar';
};

# THE CASCADE IS THE POINT. A typed shift makes the sub's return type typed,
# which makes every call to it typed. That chain was the whole cost of the hole.
subtest 'the sub return type and its callsite follow' => sub {
    my $wire = wire_for('sub f { my $n = shift; return $n } say(f(7));', 'chain');
    is $wire->{classes}{main}{subs}{f}{return_type}, 'Scalar',
        'the sub return type carries the floor';

    my ($call) = grep {
        $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::f'
    } ( $wire->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    ok $call, 'the call to f exists' or return;
    isnt $call->{stamp}, 'Unknown', 'and the callsite is no longer a hole';
};

done_testing;
