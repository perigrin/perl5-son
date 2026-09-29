# ABOUTME: A `(?{ ... })` block runs when its pattern matches and can write the
# ABOUTME: program's lexicals, so the match is an effect and they are shared.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE MATCH WAS DROPPED AND THE LEXICAL FOLDED. A void match looked pure, so
# the emission left it out, and `$k` -- written only by the code block --
# printed its initial 0. The block is a kid of the match op (a padsv lvalue
# inside it), and the pattern is emitted verbatim, so its `$k` must be the
# real variable. Corpus 096.
round_trips(<<'SRC', 'a code block in a literal pattern writes a lexical');
my $s = "abc";
my $k = 0;
$s =~ /b(?{ $k = 5 })/;
print "$k\n";
SRC

# THROUGH A qr//: the block rides in the compiled pattern, and the match is
# a runtime Match against it. Corpus 097.
round_trips(<<'SRC', 'a code block in a qr, matched later');
my $n = 0;
my $r = qr/a(?{ $n = 7 })b/;
my $s = "ab";
$s =~ $r;
print "$n\n";
SRC

# BRACES IN A BLOCK NEED NOT BALANCE -- `length("}}}")` -- and the pattern is
# emitted verbatim, inside `m...`, inside `qr...`, and inside the wrapper a
# runtime match puts around a qr. Each chose `{}` and closed early. Corpus 098.
round_trips(<<'SRC', 'code blocks whose text has unbalanced braces');
my $s = "abc";
my $n = 1;
my $k = 0;
$s =~ s{a}{ $n + length("))") }e;
$s =~ /b(?{ $k = length("}}}") })/;
my $r = qr/c(?{ $k = $k + length("}}") })/;
$s =~ $r;
print "$s $k\n";
SRC

# A BLOCK THAT DOES NOT RUN leaves the lexical alone: no match, no write.
round_trips(<<'SRC', 'a code block whose pattern does not match');
my $s = "xyz";
my $k = 1;
$s =~ /b(?{ $k = 5 })/;
print "$k\n";
SRC

done_testing;
