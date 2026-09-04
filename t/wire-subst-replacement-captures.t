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

# IT REFUSES, AND THE REFUSAL IS THE POINT. The capture must read the
# RegexSubst while the RegexSubst reads the replacement the capture is part of
# -- a cycle. RegexCapture's contract is `inputs[0] is the match node`, and
# inputs are a construction :param that hash-consing depends on, so the edge
# cannot be patched in afterwards.
#
# THE IR SANCTIONS EXACTLY ONE FORWARD REFERENCE: a loop header Phi's backedge,
# which chalk's loader defer-patches via set_backedge (SoN::IR::Graph::nodes
# calls it "the sole, sanctioned forward reference in the order"). There is no
# second mechanism, so this needs a WIRE decision, not a producer-side fix.
subtest 'a replacement reading its own capture refuses as a cycle' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $s="axb"; $s =~ s/(x)/ord($1)/e; print $s;', 'cap-own');
    is $said, 'a120b', 'perl substitutes ord(x)' or return;

    like $err, qr/GAP/, 'it refuses rather than guessing an edge';
    like $err, qr/cycle/, '... naming the cycle as the blocker';
    unlike $err, qr/INTERNAL|Stack underflow/, '... and does not crash';
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
