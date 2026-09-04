# ABOUTME: A plain s/// in a loop body must build a RegexSubst, not a bogus Call.
# ABOUTME: The loop walker's subst arm was gated on PMf_EVAL, so /e only.
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
    my $w = (length $out && $out =~ /^\{/)
          ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* : ();
    return ($said, \@n, $err);
}

# THE LOOP WALKER HAD NO HANDLER FOR A PLAIN s///. Its subst arm was gated on
# PMf_EVAL, so only the /e form was modelled; the plain form fell through to
# the generic OpMap dispatch, which turns an unrecognised op into a builtin
# Call. Measured on `foreach ($l) { s/x/y/ }`:
#
#     Call(builtin, name="subst") [16]      and node 16 is Constant 'y'
#
# so the node's single input was the REPLACEMENT STRING -- whatever happened to
# be on the stack -- while the pattern was absent entirely and the target
# (the element Subscript) was connected to nothing.
#
# `s/x/y/` and `s/q/y/` would therefore produce IDENTICAL graphs, which is the
# hash-consing hazard a dropped pattern always creates.

subtest 'a plain subst in a loop builds a RegexSubst' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=("axb"); for my $s (@a) { my $t=$s; $t =~ s/x/y/; print $t }',
        'plain-loop');
    is $said, 'ayb', 'perl substitutes' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    ok scalar(grep { $_->{op} eq 'RegexSubst' } $n->@*),
        'a RegexSubst is built';
    is scalar(grep {
        $_->{op} eq 'Call'
          && (($_->{fields} // {})->{name} // '') eq 'subst'
    } $n->@*), 0,
        'and NOT a builtin Call named "subst"';
};

# THE PATTERN MUST SURVIVE, or two different substitutions hash-cons to one
# node. This is the same defect `split` nearly shipped when its pattern was
# dropped, and the generic Call fallback loses it completely.
subtest 'the pattern reaches the node' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=("axb"); for my $s (@a) { my $t=$s; $t =~ s/x/y/; print $t }',
        'plain-pattern');
    is $said, 'ayb', 'perl substitutes' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my ($rs) = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    ok $rs, 'a RegexSubst exists' or return;
    is +(($rs->{fields} // {})->{pattern} // ''), 'x',
        'it carries its pattern';
    is +(($rs->{fields} // {})->{replacement} // ''), 'y',
        'and its replacement';
};

# THE /g FORM TAKES THE SAME PATH -- it is the same op with a flag, and the
# flag belongs on the node rather than deciding whether one is built.
subtest 'the /g form is modelled too' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=("axax"); for my $s (@a) { my $t=$s; $t =~ s/x/y/g; print $t }',
        'plain-g');
    is $said, 'ayay', 'perl substitutes globally' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my ($rs) = grep { $_->{op} eq 'RegexSubst' } $n->@*;
    ok $rs, 'a RegexSubst is built for /g' or return;
    like +(($rs->{fields} // {})->{flags} // ''), qr/g/,
        '... carrying the global flag';
};

# THE /e FORM MUST KEEP WORKING. It already had a handler, and widening the
# gate must not disturb it.
subtest 'the /e form is unaffected' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my @a=("axb"); for my $s (@a) { my $t=$s; $t =~ s/x/9/e; print $t }',
        'plain-e');
    is $said, 'a9b', 'perl evaluates the replacement' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    ok scalar(grep { $_->{op} eq 'RegexSubst' } $n->@*),
        'still a RegexSubst';
};

done_testing;
