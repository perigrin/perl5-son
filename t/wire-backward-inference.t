# ABOUTME: A value with no forward seed is typed by what its USES require.
# ABOUTME: `$x + 1` puts $x in numeric context, so $x is Num from the body alone.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name, %opt) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $filter = $opt{no_filter} ? '' : ',package=main';
    my $json = qx{$PERL -Ilib -MO=SoN,json$filter $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub node_in ($wire, $graph, $op, %match) {
    my $g = $wire->{methods}{$graph} or return undef;
    for my $n (($g->{nodes} // [])->@*) {
        next unless $n->{op} eq $op;
        my $ok = 1;
        for my $k (keys %match) {
            $ok = 0 unless ($n->{fields}{$k} // '') eq $match{$k};
        }
        return $n if $ok;
    }
    return undef;
}

# THE DEFECT. Every existing pass runs FORWARD, operands to result, and refuses
# when an operand is Unknown. But a use site CONSTRAINS its operands: `+` puts
# both in numeric context, so `$x` is Num -- from the body alone, no callsite.
# The declaration contributes `Scalar` (a scalar slot); meet(Scalar, Num) = Num.
subtest 'a parameter is typed by what its body does with it' => sub {
    my $wire = wire_for('sub add1 { my ($x) = @_; return $x + 1 } print add1(5), "\n";',
                        'param_num');
    my $pad = node_in($wire, 'main::add1', 'PadAccess', varname => '$x');
    ok defined $pad, 'the $x read exists' or return;
    is $pad->{stamp}, 'Num', '`$x + 1` types $x as Num';
};

# Num, NOT Int -- `add1(0.5)` is legal and nothing in the body excludes it.
# Narrowing to Int would need the callsite, which is a separate pass.
subtest 'numeric context gives Num, not Int' => sub {
    my $wire = wire_for('sub add1 { my ($x) = @_; return $x + 1 } print add1(5), "\n";',
                        'param_notint');
    my $pad = node_in($wire, 'main::add1', 'PadAccess', varname => '$x');
    ok defined $pad, 'the $x read exists' or return;
    isnt $pad->{stamp}, 'Int', 'not narrowed to Int -- add1(0.5) is legal';
};

# BILATERAL. String context must give Str, or a hardcoded Num would pass above.
subtest 'string context types the parameter Str' => sub {
    my $wire = wire_for('sub tag { my ($s) = @_; return $s . "!" } print tag("a"), "\n";',
                        'param_str');
    my $pad = node_in($wire, 'main::tag', 'PadAccess', varname => '$s');
    ok defined $pad, 'the $s read exists' or return;
    is $pad->{stamp}, 'Str', '`$s . "!"` types $s as Str';
};

# THE CASCADE. Once the parameter is typed, the arithmetic over it types, and so
# does the sub's return type -- which the existing forward pass then carries to
# every callsite.
subtest 'typing the parameter types the return and the callsite' => sub {
    my $wire = wire_for('sub add1 { my ($x) = @_; return $x + 1 } print add1(5), "\n";',
                        'cascade');
    is $wire->{classes}{main}{subs}{add1}{return_type}, 'Num',
        'the return type follows from the typed body';
    my $call = node_in($wire, 'main::__PROGRAM__', 'Call', name => 'main::add1');
    ok defined $call, 'the callsite exists' or return;
    is $call->{stamp}, 'Num', 'and the callsite carries it';
};

# A :param field is the same shape: no forward seed, typed by its body's use.
subtest 'a :param field is typed by its use' => sub {
    my $src = 'use feature "class"; no warnings "experimental::class";
class Adder { field $n :param; method inc { return $n + 1 } }
my $a = Adder->new(n => 1); print $a->inc, "\n";';
    my $wire = wire_for($src, 'param_field', no_filter => 1);
    my $fa = node_in($wire, 'Adder::inc', 'FieldAccess');
    ok defined $fa, 'the field read exists' or return;
    is $fa->{stamp}, 'Num', '`$n + 1` types the field as Num';
};

# ONLY PROPAGATES. A parameter with NO constraining use stays Unknown -- the
# pass reads requirements, it does not invent them.
subtest 'an unconstrained parameter stays Unknown' => sub {
    my $wire = wire_for('sub id { my ($x) = @_; return $x } print id(5), "\n";',
                        'unconstrained');
    my $pad = node_in($wire, 'main::id', 'PadAccess', varname => '$x');
    ok defined $pad, 'the $x read exists' or return;
    is $pad->{stamp}, 'Unknown',
        'a parameter nothing constrains is still Unknown';
};

# A CALL MUST NOT BE TYPED BY ITS CONSUMER. Its type comes from its CALLEE.
#
# Caught by chalk's gate (215 -> 199, with real miscompiles). The first version
# of this pass stamped ANY Value node carrying a use-site requirement, so
# `$p->left - $p->right` stamped both Call nodes Num from Subtract's
# requirement -- while the methods themselves were still Unknown and
# method_return_types was EMPTY. The wire then claimed a return type the callee
# did not have, disagreeing with the vtable ABI, and an Int was read as a
# double: lli printed 1.48e-323 where perl printed 3.
#
# Backward inference is only valid where a type is GENUINELY OPEN -- a slot read
# with no other source. A Call has an authoritative source (its callee) and so
# does a Subscript (its container). Those must never be back-filled.
subtest 'a Call is not typed by what its caller does with it' => sub {
    my $src = 'use feature "class"; no warnings "experimental::class";
class Pair { field $left :param :reader; field $right :param :reader; }
my $p = Pair->new(left => 10, right => 20); say($p->left - $p->right);';
    my $wire = wire_for( $src, 'call_not_backfilled', no_filter => 1 );
    my @calls = grep {
        $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'left'
    } ( $wire->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    ok scalar(@calls), 'the method callsite exists' or return;
    isnt $calls[0]{stamp}, 'Num',
        'the Call is NOT stamped from the Subtract above it';
    # IT TAKES ITS CALLEE'S ANSWER, WHICH IS THE POINT. `Pair::left` reads a
    # `:param` field, so its return type is `Scalar` and the Call carries the
    # same -- the wire agreeing with itself. The old assertion here was
    # `Unknown`, which was true only while the callee had NO answer to take;
    # its own comment says so ("its callee has no determined return type").
    # What must never happen is the Call taking `Num` from the Subtract ABOVE
    # it while the callee says something else, and that is the line above.
    is $calls[0]{stamp}, $wire->{classes}{Pair}{method_return_types}{left},
        'it takes its CALLEE return type, not its consumer requirement';
};


done_testing;
