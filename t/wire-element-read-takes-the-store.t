# ABOUTME: An element read threaded to a store yields what that store put there
# ABOUTME: -- Scalar is the floor for a read that is threaded to nothing.
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

# The Subscript that READS -- three inputs (container, index, memory), where a
# store target has two.
sub threaded_read ($src, $name) {
    my $wire = wire_for($src, $name);
    for my $g (keys $wire->{methods}->%*) {
        for my $n (( $wire->{methods}{$g}{nodes} // [] )->@*) {
            next unless $n->{op} eq 'Subscript';
            next unless scalar( ( $n->{inputs} // [] )->@* ) >= 3;
            return $n->{stamp} // 'Unknown';
        }
    }
    return undef;
}

# MEMORY-SSA ALREADY THREADS THE READ TO ITS STORE. `$a[0] = "foo"; $a[0]`
# builds the read with the Assign as a third input:
#
#     Subscript  in=(EntryDef:Array, Constant:Int)          <- the store TARGET
#     Assign     in=(Subscript, Constant:Str)  stamp=Str    <- takes its RHS
#     Subscript  in=(EntryDef:Array, Constant:Int, Assign)  <- the READ
#
# The Assign already carries the stored type. The read was nonetheless floored
# to `Scalar` by _floor_subscripts, which fires on any 3-input Subscript and
# answers Scalar without looking at what it is threaded TO. The store's type is
# sitting on the input.
#
# `Scalar` was not wrong -- an element IS one scalar slot -- it was just the
# weakest true answer where a stronger one was already present.
subtest 'a read threaded to a store takes the stored type' => sub {
    is(threaded_read('sub probe { my @a; $a[0] = "foo"; return $a[0] }', 'store_str'),
        'Str', 'reading back a stored Str gives Str, not the Scalar floor');

    is(threaded_read('sub probe { my @a; $a[0] = 42; return $a[0] }', 'store_int'),
        'Int', 'reading back a stored Int gives Int');
};

# THE FLOOR STILL APPLIES WHERE NOTHING IS KNOWN. A read threaded to a store
# whose own type is undetermined has nothing better to take, and Scalar -- one
# element is one scalar slot -- remains the honest answer.
subtest 'the floor still answers when the store type is unknown' => sub {
    my $s = threaded_read(
        'sub probe { my @a; $a[0] = main::unknown_fn(); return $a[0] }',
        'store_unknown');
    ok(defined $s, 'a read was found') or return;
    isnt($s, 'Unknown', 'it is still typed rather than left Unknown');
};

done_testing;
