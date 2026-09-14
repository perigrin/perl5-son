# ABOUTME: A nested `for (LIST)` must not store the inner element into the outer one.
# ABOUTME: The alias write-back must fire only for a body that writes its alias.

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
    my $src = 'my @v; for (1,2) { for (7,8) { push @v, $_ } } print "@v\n";';
    is run_perl($src), "7 8 7 8\n", 'perl iterates both' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    is [anon_element_stores($g)], [],
        'no element store into an anonymous container';
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

# THREE LEVELS, because the leak is per-nesting and a two-level test cannot
# tell "restored once" from "restored at every depth". Measured, this refused
# identically before the fix -- the middle loop saw the innermost alias.
subtest 'three nested literal-list foreaches store nothing' => sub {
    my $src = 'my @v; for (1,2) { for (3,4) { for (5,6) { push @v, $_ } } }'
            . ' print "@v\n";';
    is run_perl($src), "5 6 5 6 5 6 5 6\n", 'perl iterates all three' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    is [anon_element_stores($g)], [],
        'no element store into an anonymous container';
};

# THE WRITE-BACK MUST STILL FIRE when the body DOES write its alias -- the fix
# suppresses a write the source never made, not the write-back itself.
# Measured: `my @a=(1,2); for (@a) { $_ = $_ + 100 }` gives `101 102`, and the
# emitted program agrees.
subtest 'a foreach whose body writes its alias still stores back' => sub {
    my $src = 'my @a=(1,2); for (@a) { $_ = $_ + 100 } print "@a\n";';
    is run_perl($src), "101 102\n", 'perl mutates in place' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;

    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
    my @stores = grep {
        my $t = $by{ ($_->{inputs} // [])->[0] // -1 };
        ($_->{op} // '') eq 'Assign'
            && $t && ($t->{op} // '') eq 'Subscript';
    } $g->{nodes}->@*;
    ok scalar(@stores), 'the element store-back is present';
};

done_testing;
