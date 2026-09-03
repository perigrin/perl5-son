# ABOUTME: An interpolated pattern keeps ALL its parts, or refuses -- never the last one.
# ABOUTME: `/x${p}y/` was matching against "y" alone: a silent wrong answer.
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

# A SILENT WRONG ANSWER. `$s =~ /x${p}y/` compiles to pushmark, three parts on
# the stack ("x", $p, "y"), then a transparent regcomp. The match handler pops
# ONE value as the runtime pattern, so it got only the LAST fragment:
#
#     my $p="a"; my $s="ZZy"; $s =~ /x${p}y/
#     perl:  no match     -- ZZy does not contain xay
#     graph: Match("ZZy", "y")  -- which is TRUE
#
# Found while investigating the qr// GAP; this is worse, because qr// refuses
# and this one answers.
#
# EITHER outcome is acceptable to this test: assemble the parts, or refuse.
# What is NOT acceptable is matching against a fragment.
subtest 'an interpolated match does not match a fragment' => sub {
    my ($n, $err) = wire('my $p="a"; my $s="ZZy"; print(($s =~ /x${p}y/) ? "m" : "n");',
                         'interp_match');
    if ($err =~ /GAP/) {
        pass('refused loudly, which is acceptable');
        return;
    }
    my %byid = map { $_->{id} => $_ } $n->@*;
    my ($m) = grep { $_->{op} eq 'Match' || $_->{op} eq 'RegexMatch' } $n->@*;
    ok defined $m, 'a match node exists' or return;
    my @in = map { $byid{$_} } ($m->{inputs} // [])->@*;
    my $pat = $in[-1];
    isnt +($pat->{value} // ''), 'y',
        'the pattern is not the LAST FRAGMENT of x${p}y';
};

# A LITERAL pattern is unaffected -- it rides on the op via precomp and never
# reaches the stack, so it cannot be truncated this way.
subtest 'a literal pattern still matches' => sub {
    my ($n, $err) = wire('my $s="abc"; print(($s =~ /abc/) ? "m" : "n");', 'lit_match');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
    my ($m) = grep { $_->{op} =~ /^(Match|RegexMatch)$/ } $n->@*;
    ok defined $m, 'a match node exists';
};

# qr// WITH AN INTERPOLATED PATTERN is the same shape one construct over, and
# it now lowers rather than refusing. Its parts are on the stack behind a mark
# exactly as the match form's are, so they fold with Concat the same way; the
# refusal ("the pattern is not a compile-time literal") was true and was never
# a reason it could not be BUILT -- the same mistake the split refusal made
# about its fused target.
subtest 'an interpolated qr// assembles its whole pattern' => sub {
    my ($n, $err) = wire('my $p="a"; my $re = qr/x${p}y/; print ref($re);', 'interp_qr');
    unlike $err, qr/GAP|INTERNAL/, 'it lowers';
    my %byid = map { $_->{id} => $_ } $n->@*;
    my ($c) = grep { $_->{op} eq 'Coerce' && ($_->{to_repr} // '') eq 'Regex' } $n->@*;
    ok defined $c, 'a Coerce to Regex is built -- compile this string as a pattern'
        or return;
    my ($src) = map { $byid{$_} } ($c->{inputs} // [])->@*;
    is +($src->{op} // ''), 'Concat',
        'and it compiles a Concat of the parts, not a single fragment';
};

# A LITERAL qr// stays a compile-time regex constant -- it has a precomp and
# never reaches the stack, so the interpolation path must not claim it.
subtest 'a literal qr// is still a regex constant' => sub {
    my ($n, $err) = wire('my $re = qr/abc/; print ref($re);', 'lit_qr');
    unlike $err, qr/GAP|INTERNAL/, 'it translates';
    my ($c) = grep { ($_->{const_type} // '') eq 'regex' } $n->@*;
    ok defined $c, 'a regex Constant exists';
    is +($c->{value} // ''), 'abc', 'holding the whole literal pattern';
};

done_testing;
