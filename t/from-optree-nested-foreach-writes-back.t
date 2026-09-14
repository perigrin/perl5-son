# ABOUTME: A nested `for (LIST)` must not store the inner element into the outer one.
# ABOUTME: The alias write-back fires even when the body never writes its alias.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# THE SOURCE CONTAINS NO STORE. Measured on
# `for (1,2) { for (7,8) { push @v, $_ } }` -- perl prints `7 8 7 8`, and
# neither body assigns its alias:
#
#      4 ArrayLiteral in=[2,3]      the OUTER list
#      8 Subscript    in=[4,7]      the outer element
#     11 ArrayLiteral in=[10]       the INNER list
#     16 Subscript    in=[11,14,15] the inner element
#     19 Assign       in=[8,16] ci=18
#
# Assign(19) stores the INNER element into the OUTER one, pinned on the inner
# loop's exit Region. Nothing in the source asks for that.
#
# A SINGLE `for (LIST)` BUILDS NO ASSIGN -- measured, the same program with
# one loop has none -- so this is the write-back firing for a nesting it
# should not, not foreach writing back in general.
#
# The deparse refuses it ("an element store into an anonymous container"),
# correctly: `(1,2)[0] = ...` is not assignable, and inventing a temporary
# would store into a DIFFERENT container from the one every read names.
sub anon_element_stores ($g) {
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my @out;
    for my $a (grep { ($_->{op} // '') eq 'Assign' } $g->{nodes}->@*) {
        my $t = $by{ ($a->{inputs} // [])->[0] // -1 } or next;
        next unless ($t->{op} // '') eq 'Subscript';
        my $c = $by{ ($t->{inputs} // [])->[0] // -1 } or next;
        next unless ($c->{op} // '') =~ /Literal\z/
                 && !defined(($c->{fields} // {})->{symbol});
        push @out, $a->{id};
    }
    return @out;
}

subtest 'a nested literal-list foreach stores nothing' => sub {
    todo 'the alias write-back fires for a body that never writes it' => sub {
    my $src = 'my @v; for (1,2) { for (7,8) { push @v, $_ } } print "@v\n";';
    is run_perl($src), "7 8 7 8\n", 'perl iterates both' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    is [anon_element_stores($g)], [],
        'no element store into an anonymous container';
    };
};

# A SINGLE LOOP MUST STAY CLEAN -- it is the shape that already works, and
# what shows the defect is the nesting rather than foreach itself.
subtest 'a single literal-list foreach stores nothing' => sub {
    my $src = 'my @v; for (1,2) { push @v, $_ } print "@v\n";';
    is run_perl($src), "1 2\n", 'perl iterates' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    is [anon_element_stores($g)], [],
        'no element store into an anonymous container';
};

done_testing;
