# ABOUTME: `@{$r}` and `%{$r}` dereference exactly as `@$r` and `%$r` do; the
# ABOUTME: braces add a `scope` op between rv2av and its operand, and nothing else.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
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

# THE BRACES ARE A `scope` OP. Measured with Concise:
#
#     @$r      rv2av -> padsv
#     @{$r}    rv2av -> scope -> padsv
#
# Every deref branch in the rv2av handler tests `$op->first->name`, so the
# braced form matched none of them and the REFERENCE flowed on as the value:
# `my @c = @{$r}` rendered as `my @c = (\@a)`, one element where perl has
# three. Silent -- it compiles and runs. Corpus cases 009, 090 and 093.
round_trips(<<'SRC', 'a braced array deref in list context');
my @a = (10, 20, 30);
my $r = \@a;
my @c = @{$r};
print scalar(@c), " @c\n";
SRC

round_trips(<<'SRC', 'a braced hash deref in list context');
my %h = (a => 1, b => 2);
my $r = \%h;
my %copy = %{$r};
print scalar(keys %copy), " $copy{a}\n";
SRC

round_trips(<<'SRC', 'a braced array deref in scalar context');
my @a = (10, 20, 30);
my $r = \@a;
print scalar(@{$r}), "\n";
SRC

# THE UNBRACED FORM IS THE CONTROL, and already round-trips.
round_trips(<<'SRC', 'an unbraced array deref');
my @a = (10, 20, 30);
my $r = \@a;
my @c = @$r;
print scalar(@c), " @c\n";
SRC

# A SCOPE WITH MORE THAN ONE KID IS A BLOCK, not a spelling of its operand:
# `@{ print "x"; $r }` runs the print. Looking through it would drop that.
round_trips(<<'SRC', 'a deref block with a statement in it');
my @a = (10, 20, 30);
my $r = \@a;
my @c = @{ print "side "; $r };
print scalar(@c), "\n";
SRC

done_testing;
