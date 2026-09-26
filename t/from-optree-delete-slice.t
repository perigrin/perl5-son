# ABOUTME: `delete @h{...}` removes many keys and yields their values in order;
# ABOUTME: each removal is its own effect on the memory chain.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# THE OPERANDS ARRIVE AS A LIST BEHIND A MARK. Measured on
# `delete @h{qw(a b)}`:
#
#     c  pushmark
#     d  pushmark
#     e  const[PV "a"]
#     f  const[PV "b"]
#     g  padhv[%h]
#     h  delete lK/SLICE
#
# so the keys and the container share one mark and `SLICE` is a PRIVATE bit
# (private=0x40), not an OPf flag -- the refusal's own comment records that
# keying on OPf_STACKED matched nothing and let a slice pop ONE key off a list
# of them, building Delete(Constant, HashLiteral) with container and key
# swapped.
#
# EACH REMOVAL IS ITS OWN EFFECT, which is why this is N nodes and not one: a
# later read must observe every key gone, and the single-key handler's own
# comment says a Delete that does not advance memory leaves a later read seeing
# the key.

round_trips( <<'SRC', 'a two-key hash slice delete' );
my %h = (a => 1, b => 2, c => 3);
my @gone = delete @h{qw(a b)};
print "@gone | ", join(",", sort keys %h), "\n";
SRC

round_trips( <<'SRC', 'a slice delete in void context' );
my %h = (a => 1, b => 2, c => 3);
delete @h{qw(a b)};
print join(",", sort keys %h), "\n";
SRC

round_trips( <<'SRC', 'a later read observes every removal' );
my %h = (a => 1, b => 2, c => 3);
delete @h{qw(a b)};
print defined($h{a}) ? "y" : "n";
print defined($h{b}) ? "y" : "n";
print defined($h{c}) ? "y" : "n";
print "\n";
SRC

# A SINGLE-KEY DELETE MUST BE UNDISTURBED -- it takes the other path and is the
# regression guard.
round_trips( <<'SRC', 'a single-key delete is unchanged' );
my %h = (a => 1, b => 2);
my $g = delete $h{a};
print "$g | ", join(",", sort keys %h), "\n";
SRC

done_testing;
