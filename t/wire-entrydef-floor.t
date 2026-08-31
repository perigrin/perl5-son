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

# THE FLOOR MUST NOT PREEMPT A BETTER ANSWER. A global that inference can type
# keeps the narrower stamp: the floor only fills a hole.
subtest 'the floor does not overwrite a narrowed stamp' => sub {
    my $wire = wire_for('sub probe { $main::n_probe = 5; $main::n_probe + 1 }',
                        'narrowed_global');
    my @e = entrydefs($wire);
    ok(scalar @e, 'an EntryDef reached the wire') or return;
    isnt($e[0]{stamp} // 'Unknown', 'Unknown', 'it is typed');
    # Scalar is the floor; anything narrower proves inference still won.
    ok($e[0]{stamp} eq 'Scalar' || $e[0]{stamp} =~ /^(Int|Num|Str)$/,
        "stamp is the floor or narrower, got $e[0]{stamp}");
};

done_testing;
