# ABOUTME: A LIST-context read of an array must observe a preceding mutation.
# ABOUTME: The flatten shortcut pushed the literal's original elements instead.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* : ();
    return ($said, \@n, $err);
}

# A LIST READ IS MEMORY-DEPENDENT TOO, and this is the same defect the scalar
# read had one path over. `Count` was fixed by giving it a memory input; the
# LIST-context read of the same array has its own path and was missed.
#
# The flatten shortcut in the padav handler pushes an ArrayLiteral's INPUTS
# directly onto the stack -- the original elements -- so anything consuming the
# array in list context reads the array as first constructed:
#
#     my @a=(1,2,3); shift @a; print "@a";
#       perl:  2 3
#       graph: join($", 1, 2, 3)     the ORIGINAL three constants
#
# The shortcut is right for `my @b = @a` with no mutation between, which is
# what it was written for, and wrong the moment anything mutates @a.
#
# ASSERTED ON THE GRAPH, NOT THE STRING. These read the aggregate, so a fix
# that merely refuses is also acceptable under refuse-or-lower -- but silently
# flattening stale elements is not, and that is what each subtest pins.

subtest 'array interpolation after a shift does not read the original elements'
=> sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=(1,2,3); shift @a; print "@a";', 'interp-shift');
    is $said, '2 3', 'perl drops the first element' or return;

    # Either it lowers correctly, or it refuses. What it must NOT do is emit a
    # join over the three original constants.
    if ($err =~ /GAP/) {
        pass 'refused rather than reading the pre-shift elements';
        return;
    }
    my %by = map { $_->{id} => $_ } $n->@*;
    my ($join) = grep { (($_->{fields} // {})->{name} // '') eq 'join' } $n->@*;
    ok $join, 'a join is built for the interpolation' or return;

    my @const = grep { ($by{$_}{op} // '') eq 'Constant' }
                ($join->{inputs} // [])->@*;
    my @vals  = grep { defined && /^[0-9]+$/ }
                map { ($by{$_}{fields} // {})->{value} } @const;
    isnt scalar(@vals), 3,
        'it does not join the three ORIGINAL elements of the pre-shift array';
};

subtest 'a copy made after a mutation is the mutated array' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=(1,2,3); shift @a; my @b=@a; print scalar(@b);', 'copy-shift');
    is $said, '2', 'perl copies the shortened array' or return;

    if ($err =~ /GAP/) { pass 'refused rather than copying stale elements'; return }

    my %by = map { $_->{id} => $_ } $n->@*;
    my ($count) = grep { $_->{op} eq 'Count' } $n->@*;
    ok $count, 'a Count is built for scalar(@b)' or return;

    # The counted aggregate must not be a literal holding the three ORIGINAL
    # elements -- that is @a as first constructed, not @a after the shift.
    my $agg = $by{ ($count->{inputs} // [])->[0] // '' };
    if ( ($agg->{op} // '') eq 'ArrayLiteral' ) {
        isnt scalar(($agg->{inputs} // [])->@*), 3,
            'the copied array is not the three pre-shift elements';
    }
    else {
        pass 'the copy is not a stale literal';
    }
};

subtest 'interpolation after a push does not miss the new element' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=(1,2,3); push @a,4; print "@a";', 'interp-push');
    is $said, '1 2 3 4', 'perl appends' or return;

    if ($err =~ /GAP/) { pass 'refused rather than reading the pre-push elements'; return }

    my %by = map { $_->{id} => $_ } $n->@*;
    my ($join) = grep { (($_->{fields} // {})->{name} // '') eq 'join' } $n->@*;
    ok $join, 'a join is built' or return;
    my @const = grep { ($by{$_}{op} // '') eq 'Constant' }
                ($join->{inputs} // [])->@*;
    my @vals  = grep { defined && /^[0-9]+$/ }
                map { ($by{$_}{fields} // {})->{value} } @const;
    isnt scalar(@vals), 3,
        'it does not join only the three PRE-push elements';
};

# THE SHORTCUT IS RIGHT WHEN NOTHING MUTATES, which is what it was written for
# (`my @b = @a` building @b from @a's elements rather than nesting a ref). That
# case must keep working -- a fix that refuses every list read would trade one
# defect for a coverage loss.
subtest 'an unmutated copy still flattens' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=(1,2,3); my @b=@a; print scalar(@b);', 'copy-clean');
    is $said, '3', 'perl copies all three' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it still lowers -- no refusal here';
    ok scalar(grep { $_->{op} eq 'Count' } $n->@*), 'and still builds a Count';
};

done_testing;
