# ABOUTME: A foreach inside a loop body nests properly -- inner Loop on the outer body edge.
# ABOUTME: The refusal predated the fixes that made the loop translators reentrant.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? (map { { $_->%*, ($_->{fields} // {})->%* } }
                  ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*) : ();
    return (\@n, $err);
}

# THE REFUSAL OUTLIVED ITS REASON. Its comment recorded a real historical bug:
# "a nested loop minted Projs on the OUTER Loop and truncated the walk". But
# each translator creates its OWN Loop from $sim->control, so they are
# structurally reentrant, and `enteriter` is already dispatched by _step --
# which _walk_loop_body calls. The refusal fired BEFORE _step could.
#
# perl's own t/comp/parser_run.t and t/comp/utf.t both hit it.
subtest 'a nested foreach translates' => sub {
    my (undef, $err) = wire(
        'my $t=0; for my $i (1,2) { for my $j (1,2) { $t = $t + 1 } } print $t;',
        'nested');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
};

# THE NESTING MUST BE REAL, not two sibling loops. The inner Loop takes the
# OUTER loop's body Proj as its control input, and its own Projs and Phis
# attach to ITSELF -- that is the property the old comment says was broken.
subtest 'the inner loop hangs off the outer body edge' => sub {
    my ($n, $err) = wire(
        'my $t=0; for my $i (1,2) { for my $j (1,2) { $t = $t + 1 } } print $t;',
        'nested_shape');
  SKIP: {
        skip "refused: $err", 3 if $err =~ /GAP/;
        my %byid = map { $_->{id} => $_ } $n->@*;
        my @loops = grep { $_->{op} eq 'Loop' } $n->@*;
        is scalar(@loops), 2, 'two Loop nodes' or skip 'wrong loop count', 2;

        # the inner loop is the one whose input is a Proj of the other
        my ($inner) = grep {
            my $src = $byid{ ($_->{inputs} // [])->[0] // -1 };
            $src && $src->{op} eq 'Proj';
        } @loops;
        ok defined $inner, 'one Loop takes a Proj as its control input' or skip 'no inner', 1;

        my $src = $byid{ ($inner->{inputs} // [])->[0] };
        is +($src->{index} // -1), 0,
            'and it is the BODY edge (index 0), not the exit edge';
    }
};

# THE INNER LOOP'S OWN Phis MUST NAME IT, not the outer loop. A Phi whose
# region names the wrong merge is the "Projs on the OUTER Loop" defect in its
# other form.
subtest 'inner Phis name the inner loop' => sub {
    my ($n, $err) = wire(
        'my $t=0; for my $i (1,2) { for my $j (1,2) { $t = $t + 1 } } print $t;',
        'nested_phi');
  SKIP: {
        skip "refused", 1 if $err =~ /GAP/;
        my %byid = map { $_->{id} => $_ } $n->@*;
        my @loops = grep { $_->{op} eq 'Loop' } $n->@*;
        my ($inner) = grep {
            my $s = $byid{ ($_->{inputs} // [])->[0] // -1 }; $s && $s->{op} eq 'Proj';
        } @loops;
        skip "no inner loop", 1 unless $inner;
        my @inner_phis = grep { $_->{op} eq 'Phi' && ($_->{region} // -1) == $inner->{id} } $n->@*;
        ok scalar(@inner_phis) >= 1,
            'at least one Phi names the inner Loop as its region';
    }
};

# A SINGLE loop must still work -- the refusal removal must not disturb the
# path that was already correct.
subtest 'a single foreach is unaffected' => sub {
    my ($n, $err) = wire('my $t=0; for my $i (1,2,3) { $t = $t + $i } print $t;', 'single');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
    is scalar(grep { $_->{op} eq 'Loop' } $n->@*), 1, 'exactly one Loop';
};

done_testing;
