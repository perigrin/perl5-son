# ABOUTME: The syntactic may-write scan of a loop body (wire v2 plan 5.2, Q6) holds every
# ABOUTME: slot the scout finds rebound, including a flip-flop's state and slot 0 under a call.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# WHY. Stage 9b replaces the scout (a throwaway walk of the body) by a Braun
# header whose Phis are made for the slots a linear scan of the body's ops says
# may be written. A slot the scan misses gets no Phi. Stage 0 measured the scan
# against the scout over the corpus, the probes and chalk's lib: it missed two
# slot kinds, in four loops --
#   - the state slot of a scalar-context range (flip-flop): corpus 003, 373;
#   - "pad slot 0" in chalk's Bootstrap/Perl/Target/Perl.pm at 1691 and 1857,
#     first read as "slot 0 under a method call". It was no slot: a `split`
#     with no target array bound its result to scope key 0 (its targ, 0 for
#     none), so every targetless split rebound one shared key, and a loop
#     holding one after another split looked as if it wrote "slot 0". The
#     producer binds nothing for a split with no target now; the scan needs
#     no rule for it.
# t/lib/MayWriteCheck.pm compares the two on every loop the real walk makes.

my $dir = tempdir( CLEANUP => 1 );

sub misses ($name, $src) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx{$^X -Ilib -It/lib -MMayWriteCheck -MO=-q,SoN,json $file 2>&1 >/dev/null};
    return [ $err =~ /^(MISS .*)$/mg ], $err;
}

my %cases = (
    'flip-flop in grep' => <<'EOS',
my @on  = (0, 1, 0, 0);
my @off = (0, 0, 1, 0);
my @idx = (0 .. 3);
my @r = grep { $on[$_] .. $off[$_] } @idx;
print "@r\n";
EOS
    'flip-flop in a foreach' => <<'EOS',
my @r;
for my $i (1 .. 6) { push @r, $i if ($i == 2) .. ($i == 4) }
print "@r\n";
EOS
    'a method call in a foreach' => <<'EOS',
package E; sub new { bless {}, shift } sub emit { my ($s, $x) = @_; return "<$x>" }
package main;
my $e = E->new;
my @out;
for my $stmt (qw(a b c)) {
    my $code = $e->emit($stmt);
    next unless defined $code;
    push @out, $code;
}
print "@out\n";
EOS
    'a split with no target after another' => <<'EOS',
my @l = map { "<$_>" } split /,/, "x,y";
for my $s ("a,b", "c") {
    for my $p (split /,/, $s) { push @l, $p }
}
print "@l\n";
EOS
    'a sub call in a while' => <<'EOS',
sub f { return $_[0] * 2 }
my $i = 0; my $s = 0;
while ($i < 3) { my $v = f($i); $s += $v; $i++ }
print "$s\n";
EOS
);

for my $name ( sort keys %cases ) {
    my ( $m, $err ) = misses( $name =~ s/\W+/-/gr, $cases{$name} );
    is $m, [], "$name: the scan holds what the scout found" or diag $err;
}

# The two measured corpus loops themselves.
use lib 'tools/lib';
use PvmCorpus qw(read_cases);
my @corpus = read_cases('t/corpus/mdtest/pvm');
for my $n ( 3, 373 ) {
    my ( $m, $err ) = misses( "corpus$n", $corpus[ $n - 1 ]{src} );
    is $m, [], sprintf( 'corpus %03d: the scan holds what the scout found', $n ) or diag $err;
}

done_testing;
