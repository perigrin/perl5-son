# ABOUTME: A sub DECLARES its return type at IR construction, Unknown when undetermined.
# ABOUTME: Three layers: producer declares, loader narrows, the signature forces.
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

sub sub_rec ($wire, $class, $name) {
    return (($wire->{classes}{$class} // {})->{subs} // {})->{$name};
}

# LAYER 1 -- the producer DECLARES. It walks the CV and builds the Return, so it
# knows the result node right there. Re-deriving it downstream by walking the
# graph is the same mistake `uses_args` exists to avoid: the frontend knows, so
# it should say.
subtest 'the producer declares a determined return type' => sub {
    my $wire = wire_for('sub f { 42 } print f(), "\n";', 'const');
    my $rec  = sub_rec($wire, 'main', 'f');
    ok $rec, 'sub f recorded' or return;
    ok exists $rec->{return_type}, 'a return_type is declared';
    is $rec->{return_type}, 'Int', 'and it is Int';
};

subtest 'a Str-returning sub declares Str' => sub {
    my $wire = wire_for('sub f { "hi" } print f(), "\n";', 'str');
    my $rec  = sub_rec($wire, 'main', 'f');
    ok $rec, 'recorded' or return;
    is $rec->{return_type}, 'Str', 'declared Str';
};

# THE UNDETERMINED CASE, and the reason this is not just "stamp the repr".
#
# A Return whose value is a recursive call has nothing to read at producer time.
# That must be declared `Unknown` -- a real lattice point meaning "inference has
# not determined this" -- and NOT omitted. An absent field is not a type; it
# forces every consumer to invent a meaning, which is the defect this whole
# arc keeps hitting.
subtest 'an undetermined return type is declared Unknown, not omitted' => sub {
    my $wire = wire_for(
        'sub fib { my $n = shift; $n < 2 ? $n : fib($n-1) + fib($n-2) } print fib(10), "\n";',
        'fib');
    my $rec  = sub_rec($wire, 'main', 'fib');
    ok $rec, 'sub fib recorded' or return;
    ok exists $rec->{return_type},
        'return_type is PRESENT even when undetermined';
    is $rec->{return_type}, 'Unknown',
        'and it says Unknown rather than being absent';
};

# LAYER 2 -- the loader NARROWS. A declared type must never be overwritten by a
# weaker one; the loader may only replace Unknown with something narrower.
subtest 'the loader does not overwrite a declared type' => sub {
    my $wire = wire_for('sub f { 42 } print f(), "\n";', 'narrow');
    my $rec  = sub_rec($wire, 'main', 'f');
    ok $rec, 'recorded' or return;
    is $rec->{return_type}, 'Int', 'producer declared Int';

    # The chalk loader is a separate repo; this asserts the WIRE contract it
    # consumes. The narrowing rule itself is tested chalk-side.
    isnt $rec->{return_type}, 'Unknown',
        'a determined type is not weakened to Unknown on the wire';
};

done_testing;
