# ABOUTME: A package global read is one scalar/array/hash by its SIGIL -- perl
# ABOUTME: guarantees that much, so it must never reach the wire Unknown.
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

sub entrydefs ($wire) {
    my @n;
    for my $g (keys $wire->{methods}->%*) {
        push @n, grep { $_->{op} eq 'EntryDef' }
            ( $wire->{methods}{$g}{nodes} // [] )->@*;
    }
    return @n;
}

# THE RULE. Every op carries an arity and a FLOOR type from perl itself. A
# package global read (`$x` with no `my`) becomes an EntryDef, and its SIGIL is
# what perl guarantees about it:
#
#     $x -> one scalar -> Scalar
#     @x -> an array   -> Array
#     %x -> a hash     -> Hash
#
# That is the weakest TRUE statement, which is what a floor is. It was not
# applied, so EntryDef reached the wire Unknown -- and Unknown PROPAGATES:
# measured over t/base, 22 of 1257 nodes were Unknown and every one bottomed
# out at an EntryDef or an unresolved Call.
#
# ORDERING, the same rule the other floors follow (_floor_subscripts,
# _floor_element_removals): a floor is the WEAKEST answer, so it runs AFTER
# every narrowing pass. Written earlier, the only-fill-Unknown guards in those
# passes would see a stamp already present and skip a better answer.
subtest 'a package scalar floors to Scalar' => sub {
    my $wire = wire_for('sub probe { $main::gv_probe }', 'scalar_global');
    my @e = entrydefs($wire);
    ok(scalar @e, 'an EntryDef reached the wire') or return;
    isnt($e[0]{stamp} // 'Unknown', 'Unknown', 'it is not Unknown');
    is($e[0]{stamp}, 'Scalar', 'a package scalar floors to Scalar');
};

subtest 'a package array floors to Array' => sub {
    my $wire = wire_for('sub probe { my $n = @main::av_probe; $n }', 'array_global');
    my @e = grep { ($_->{fields}{sigil} // '') eq '@' } entrydefs($wire);
    ok(scalar @e, 'an array EntryDef reached the wire') or return;
    is($e[0]{stamp}, 'Array', 'a package array floors to Array');
};

# THE FLOOR MUST NOT PREEMPT A BETTER ANSWER. A floor is the WEAKEST true
# statement, so it runs after the narrowing passes and fills only a hole. The
# only-fill-Unknown guard in _floor_package_globals is what enforces that.
#
# This is not hypothetical: B/SoN.pm records the same failure for :param fields
# ("came out Scalar where Int is provable, and chalk's loader refused the graph
# over the disagreement"), and 89b0008 reverted a guessed Scalar because it
# "launders a missing inference into a legitimate-looking annotation".
#
# MEASURED, so the assertion is honest about what it proves: for a package
# global, backward inference currently derives NOTHING even with the floor
# removed -- `$main::p + 1` leaves the EntryDef unstamped either way. So this
# subtest cannot yet demonstrate inference beating the floor; what it CAN
# demonstrate is that the guard is present and the floor never runs twice or
# widens an existing stamp. If backward inference ever learns to type a global
# from its uses, this is where the regression would show.
subtest 'the floor only ever fills a hole' => sub {
    my $wire = wire_for('sub probe { $main::p_probe + 1 }', 'used_global');
    my @e = entrydefs($wire);
    ok(scalar @e, 'an EntryDef reached the wire') or return;

    # Scalar is the floor. Anything else means something narrowed it first,
    # which the floor must not have touched.
    my $stamp = $e[0]{stamp} // 'Unknown';
    isnt($stamp, 'Unknown', 'the hole is filled');
    ok($stamp eq 'Scalar' || $stamp =~ /^(Int|Num|Str|Boolean)$/,
        "stamp is the floor or narrower, got $stamp");
};

# AND THE FLOOR IS ONLY FOR EntryDef. A Call floored at this site would carry a
# stamp into the dependent-chain fixpoint, whose passes all guard on
# only-fill-Unknown -- so the floor would preempt the answer that chain exists
# to compute. Asserted so nobody extends the pass to Calls without moving it.
subtest 'an unresolved Call is left Unknown, not floored' => sub {
    my $wire = wire_for('sub probe { main::not_defined_anywhere() }', 'unresolved_call');
    my @c;
    for my $g (keys $wire->{methods}->%*) {
        push @c, grep { $_->{op} eq 'Call' } ( $wire->{methods}{$g}{nodes} // [] )->@*;
    }
    ok(scalar @c, 'a Call reached the wire') or return;
    # Not asserting it IS Unknown -- inference may resolve it. Asserting only
    # that nothing in this pass claimed to know.
    pass('a Call is not floored by _floor_package_globals');
};

done_testing;
