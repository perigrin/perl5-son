# ABOUTME: A regex code block `(?{ ... })` is a body graph the match names, in
# ABOUTME: pattern order; a file lexical it writes is shared by name.
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
    print {$fh} "$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=-q,SoN,json $file 2>$dir/$name.err};
    return eval { JSON::PP->new->decode($out) };
}

sub nodes ($w, $m) { ( $w->{methods}{$m}{nodes} // [] )->@* }

# A block runs where the match reaches it: its code is a graph of its own,
# called by the match. Dropped (only the pattern text kept), $k stayed 0.
for my $case (
    [ 'literal', q{my $s = "abc"; my $k = 0; $s =~ /b(?{ $k = 5 })/; print "$k\n";}, 'RegexMatch' ],
    [ 'qr',      q{my $n = 0; my $r = qr/a(?{ $n = 7 })b/; my $s = "ab"; $s =~ $r; print "$n\n";}, 'Match' ],
) {
    my ($name, $src, $op) = @$case;
    my $w = wire($src, $name);
    ok($w, "$name: B::SoN gives a graph") or next;
    my ($m) = grep { $_->{op} eq $op } nodes($w, 'main::__PROGRAM__');
    ok($m, "$name: the program has its $op") or next;
    my $bodies = $m->{fields}{code_bodies} // [];
    is(scalar(@$bodies), 1, "$name: the match names one code body");
    my $body = $bodies->[0] // '';
    ok(exists $w->{methods}{$body}, "$name: the body is a graph ($body)");
    # The body writes the file lexical by name: a shared PadAccess, in both.
    my @w = grep { $_->{op} eq 'PadAccess' && $_->{fields}{shared} } nodes($w, $body);
    ok(@w, "$name: the body reaches the file lexical, shared by name");
    my @p = grep { $_->{op} eq 'PadAccess' && $_->{fields}{shared} } nodes($w, 'main::__PROGRAM__');
    ok(@p, "$name: the program keeps it shared too");
}

# Two blocks: two bodies, in the order they appear in the pattern.
{
    my $w = wire(q{my $s = "ab"; my $t = ""; $s =~ /a(?{ $t .= "x" })b(?{ $t .= "y" })/; print "$t\n";}, 'two');
    my ($m) = grep { $_->{op} eq 'RegexMatch' } nodes($w, 'main::__PROGRAM__');
    is(scalar(@{ $m->{fields}{code_bodies} // [] }), 2, 'two blocks: two bodies');
    # `$t .= "x"` writes $t through concat's targ, not a padsv.
    ok(( grep { exists $w->{methods}{$_} } @{ $m->{fields}{code_bodies} // [] } ) == 2, 'two blocks: both bodies are graphs (a .= writes its target)');
    my %u = map { $_ => 1 } @{ $m->{fields}{code_bodies} // [] };
    is(scalar(keys %u), 2, 'two blocks: two different bodies');
}

# A MATCH WITH A BLOCK THAT IS NOT PINNED (a loop body: not the main walk) has
# its effect float free of the loop -- refused by name, not dropped.
{
    my $file = "$dir/loop.pl";
    open my $fh, '>', $file or die; print {$fh} q{my $t = 0; for my $s ("ab", "xb") { $s =~ /a(?{ $t = $t + 1 })/ } print "$t\n";}; close $fh;
    my $err = qx{$PERL -Ilib -MO=-q,SoN,json $file 2>&1 >/dev/null};
    like($err, qr/GAP: a match with a regex code block off the main walk/, 'a block in a loop: refused by name');
}

done_testing;
