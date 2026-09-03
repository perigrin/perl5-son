# ABOUTME: An interpolated s/// replacement keeps all its parts, or refuses.
# ABOUTME: The parts live under pmreplroot as a subtree, not on the stack.
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

# THE REPLACEMENT IS A SUBTREE, NOT STACK VALUES -- which is what makes this
# different from the interpolated MATCH pattern fixed in dd9d5ab. Measured
# under suppress_peep:
#
#     s/a/x${p}y/   pmreplroot -> substcont -> multiconcat -> padsv
#
# so the parts are reached by WALKING pmreplroot, exactly as the /e path
# already walks it, rather than by popping a mark.
#
# The refusal exists because the handler below "pops ONE stack Constant and
# uses it as the whole replacement, silently dropping every other part" -- its
# own words. So a fix must produce the WHOLE replacement or keep refusing;
# what it must never do is substitute a fragment.
#
# perl: `my $p="Z"; my $s="ab"; $s =~ s/a/x${p}y/` gives "xZyb".
subtest 'an interpolated replacement is whole or refused' => sub {
    my ($n, $err) = wire('my $p="Z"; my $s="ab"; $s =~ s/a/x${p}y/; print $s;',
                         'interp_subst');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
    my ($sub) = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    ok defined $sub, 'a RegexSubst node exists' or return;
    isnt +($sub->{replacement} // ''), 'y',
        'the replacement is not the LAST FRAGMENT of x${p}y';
    isnt +($sub->{replacement} // ''), 'x',
        'nor the first';
};

# A LITERAL replacement is unaffected -- it folds to a compile-time constant
# with pmreplroot NULL and never takes the subtree path.
subtest 'a literal replacement still substitutes' => sub {
    my ($n, $err) = wire('my $s="ab"; $s =~ s/a/X/; print $s;', 'lit_subst');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
    my ($sub) = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    ok defined $sub, 'a RegexSubst node exists' or return;
    is +($sub->{replacement} // ''), 'X', 'with the literal replacement';
};

# A SINGLE interpolated variable folds to a Constant under rpeep suppression
# (pmreplroot NULL), so it takes the literal path and must keep working.
subtest 'a single interpolated variable still works' => sub {
    my (undef, $err) = wire('my $y="Q"; my $s="ab"; $s =~ s/a/$y/; print $s;', 'one_var');
    unlike $err, qr/INTERNAL/, 'no crash';
};

done_testing;
