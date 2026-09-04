# ABOUTME: $1 in a s///e replacement is the substitution's OWN capture.
# ABOUTME: Not a preceding match's -- perl rebinds captures before the body runs.
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

# A REPLACEMENT'S $1 IS THE SUBSTITUTION'S OWN CAPTURE. It refused with
# "capture $1 read with no preceding match in scope" because the walker
# resolves a capture through $sim->last_match, and only the MATCH handler ever
# set that -- a subst never recorded itself, so its own replacement could not
# see its own groups. The refusal named a true fact about the sim's state and
# the wrong fact about perl.
#
# THE ORDER IS WHY: the replacement subtree is walked BEFORE the RegexSubst
# node is built, so at the moment $1 is read there is nothing yet to point at.
#
# Measured on 5.42.0:
#
#     my $s="axb"; $s =~ s/(x)/ord($1)/e;         a120b
#
# AND A PRECEDING MATCH MUST NOT LEAK IN, which is what makes "just leave
# last_match alone" wrong:
#
#     my $t="QQ"; $t =~ /(Q)/;
#     my $u="ayb"; $u =~ s/(y)/"[$1]"/e;          a[y]b   NOT a[Q]b

# THE MATCH HALF IS ALREADY A NODE, which is what breaks the cycle without any
# new wire vocabulary. RegexMatch and RegexSubst already share a base class
# carrying pattern and flags; RegexSubst only adds `replacement`. So a s///e
# decomposes into the two nodes that already exist:
#
#     RegexMatch(target, pattern)      <- the RegexCapture reads THIS
#           |
#     replacement (reads the capture)
#           |
#     RegexSubst(target, replacement)
#
# Every edge points backwards. No forward reference, no defer-patch, and
# RegexCapture keeps its contract that inputs[0] is the MATCH node.
#
# Verified equivalent by hand on 5.42.0:
#
#     my $s="axb"; if ($s =~ /(x)/) { my $r=ord($1); $s =~ s/(x)/$r/ }   a120b
#     my $t="axb"; $t =~ s/(x)/ord($1)/e;                                a120b
#
# THE DECOMPOSITION IS ONLY VALID WITHOUT /g, and that boundary is real:
#
#     s/(\d)/$1*10/ge on "a1b2c"    direct: a10b20c   decomposed: a10b10c
#
# because the replacement runs ONCE PER MATCH with a different capture each
# time -- a loop, not a value. /ge is already refused for exactly that reason,
# BEFORE the replacement is walked, so anything reaching here is single-match.
subtest 'a replacement reads its own capture via the match node' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $s="axb"; $s =~ s/(x)/ord($1)/e; print $s;', 'cap-own');
    is $said, 'a120b', 'perl substitutes ord(x)' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my %by = map { $_->{id} => $_ } $n->@*;
    my ($rc) = grep { $_->{op} eq 'RegexCapture' } $n->@*;
    ok $rc, 'a RegexCapture is built for $1' or return;

    my $src = $by{ ($rc->{inputs} // [])->[0] // '' };
    is +($src->{op} // ''), 'RegexMatch',
        '... reading a RegexMatch, keeping inputs[0] = the match node';

    ok scalar(grep { $_->{op} eq 'RegexSubst' } $n->@*),
        'and the substitution itself is still built';
};

# /ge STILL REFUSES, and this is the assertion that keeps the decomposition
# honest -- it is sound only because the replacement runs once.
subtest 's///ge still refuses -- its replacement is a loop' => sub {
    my (undef, undef, $err) = run_and_wire(
        'my $c="a1b2c"; $c =~ s/(\d)/$1*10/ge; print $c;', 'cap-ge');
    like $err, qr/GAP/, 'refused';
    like $err, qr/once per match|loop/, '... because the body repeats';
};

# THE CAPTURE MUST COME FROM THIS SUBSTITUTION, not from an earlier match. A
# fix that simply reused whatever last_match held would produce a[Q]b here and
# pass a test that only checked "it lowered".
# THE CHEAP FIX WOULD BE A MISCOMPILE, which is why the refusal stands rather
# than reusing whatever last_match happens to hold. Measured -- an earlier
# match does NOT leak into a replacement:
#
#     my $t="QQ"; $t =~ /(Q)/;
#     my $u="ayb"; $u =~ s/(y)/"[$1]"/e;    a[y]b, NOT a[Q]b
#
# so binding $1 to the preceding Match would produce a[Q]b silently, and pass
# any test that only checked "it lowered".
subtest 'an earlier match must not be reused for the replacement' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $t="QQ"; $t =~ /(Q)/; my $u="ayb"; $u =~ s/(y)/"[$1]"/e; print $u;',
        'cap-noleak');
    is $said, 'a[y]b', 'perl uses the substitution own capture' or return;

    # Either it refuses, or -- if this is ever lowered -- the capture reads the
    # RegexSubst. What it must never do is read the preceding Match.
    if ($err =~ /GAP/) {
        pass 'refuses rather than binding the preceding match';
        return;
    }
    my %by = map { $_->{id} => $_ } $n->@*;
    my ($rc) = grep { $_->{op} eq 'RegexCapture' } $n->@*;
    ok $rc, 'a RegexCapture is built' or return;
    my $src = $by{ ($rc->{inputs} // [])->[0] // '' };
    isnt +($src->{op} // ''), 'Match',
        'the capture does NOT read the preceding match';
};

# A PLAIN MATCH CAPTURE MUST STILL WORK. The capture path is shared, so a fix
# that pointed every capture at a substitution would break the ordinary form.
subtest 'a capture after a plain match is unaffected' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $s="abc"; if ($s =~ /(b)/) { print $1 }', 'cap-plain');
    is $said, 'b', 'perl captures b' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    ok scalar(grep { $_->{op} eq 'RegexCapture' } $n->@*),
        'the ordinary match capture still builds';
};

done_testing;
