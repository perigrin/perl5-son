# ABOUTME: An interpolated s/// PATTERN keeps all its parts, or refuses.
# ABOUTME: The parts are mark-delimited under regcomp, as the match side already handles.
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

# THE PATTERN IS MARK-DELIMITED, exactly as the interpolated MATCH pattern is
# (fixed in dd9d5ab). `s/$P b$/X/` compiles to
#
#     const[PV "X"]      <- the REPLACEMENT, pushed BEFORE the mark
#     pushmark
#     padsv[$P]          }  the pattern parts
#     const[PV " b$"]    }
#     regcomp
#     subst
#
# so `$op->precomp` is EMPTY and the top of stack is a PATTERN piece, not the
# replacement. Popping one Constant as the replacement takes ` b$` and leaves
# the pattern empty -- a silent wrong answer of the same shape dd9d5ab fixed
# for the match side, and the reason comp/redef.t emitted `s{}{[^\n]+\n}`.
subtest 'an interpolated pattern is whole or refused' => sub {
    my ($n, $err) = wire('my $P="a"; my $s="a b"; $s =~ s/$P b$/X/; print $s;',
                         'interp_pat');
    my ($sub) = grep { $_->{op} eq 'RegexSubst' } $n->@*;

    if ($err =~ /GAP/) {
        pass 'it refuses rather than dropping the pattern';
        ok !defined $sub, 'and emits no RegexSubst';
        return;
    }
    unlike $err, qr/INTERNAL/, 'no crash';
    ok defined $sub, 'a RegexSubst node exists' or return;

    isnt +($sub->{replacement} // ''), ' b$',
        'the replacement is not a PATTERN fragment';
    isnt +($sub->{pattern} // 'x'), '',
        'and the pattern is not empty';
};

# TWO PATTERNS DIFFERING ONLY IN INTERPOLATED TEXT MUST NOT HASH-CONS.
# A dropped pattern makes every interpolated s/// on the same subject
# identical -- the hazard the `split` and match fixes both name.
subtest 'interpolated patterns are distinguishable' => sub {
    my ($n, $err) = wire(
        'my $P="a"; my $Q="z"; my $s="abc";'
      . ' $s =~ s/${P}b/1/; $s =~ s/${Q}b/2/; print $s;', 'two_pats');
    return pass 'refused' if $err =~ /GAP/;
    unlike $err, qr/INTERNAL/, 'no crash';
    my @sub = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    is scalar(@sub), 2, 'two distinct RegexSubst nodes';
};

# ALL-CONSTANT PARTS ARE STILL A KNOWN PATTERN. `precomp` being empty means
# the pattern went through regcomp, NOT that it is unknown -- rpeep suppression
# is why the pieces arrive separate, and `\Q...\E` or an adjacent literal
# splits text perl would otherwise have folded. Both corpus files this reaches
# are this case: base/lex.t has one Constant, comp/parser.t two ("A", "\{").
subtest 'constant parts fold back into the pattern' => sub {
    my ($n, $err) = wire('my $s="A{b"; $s =~ s/A\Q{\E/X/; print $s;', 'const_parts');
    unlike $err, qr/GAP|INTERNAL/, 'it translates rather than refusing';
    my ($sub) = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    ok defined $sub, 'a RegexSubst node exists' or return;
    is +($sub->{pattern} // ''), 'A\{',
        'the parts concatenate back to the source pattern';
    is +($sub->{replacement} // ''), 'X', 'and the replacement is the replacement';
};

# A LITERAL pattern rides on the op and must keep working -- it is the path
# every non-interpolated s/// in the corpus takes.
subtest 'a literal pattern still substitutes' => sub {
    my ($n, $err) = wire('my $s="ab"; $s =~ s/a/X/; print $s;', 'lit_pat');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
    my ($sub) = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    ok defined $sub, 'a RegexSubst node exists' or return;
    is +($sub->{pattern} // ''), 'a', 'with the literal pattern';
    is +($sub->{replacement} // ''), 'X', 'and the literal replacement';
};

done_testing;
