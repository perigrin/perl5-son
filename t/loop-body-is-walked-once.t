# ABOUTME: A loop body is walked once (wire v2 stage 9b, Braun; clause 3): no scout and no second
# ABOUTME: walk of the sub on a wrong guess -- a nest, each guess's case, the corpus and the probes.
use v5.42.0;
use Test2::V0;
use SoN::FromOptree;

# WHY. Before stage 9b each loop translator scouted its body (a throwaway walk
# to learn which variables it rebinds, and again until the stamps settled)
# and then walked it for real; an inner loop scouted again inside each outer
# walk, so a body at depth d was walked about 2^d times (audit 2.2). Braun's
# construction (docs/plans/2026-11-20-wire-v2.md, 5.2) makes the header's
# Phis from a scan of the ops and walks the body once.
#
# AND THE SUB ONCE (clause 3, "built Braun-style without the double walk").
# Until branch single-walk the header guessed four facts before the body --
# a Phi's stamp, whether the body writes the foreach iterator, a slot the
# scan missed, an aggregate written after a read flattened it -- and a wrong
# guess walked the whole sub again (%LOOP_HINTS): 8 of 1671 corpus walks and
# 117 probe files. A pre-scan of the ops decides each fact before the walk now.

my %walks;
{
    no warnings 'redefine';
    my $orig = \&SoN::FromOptree::_walk_loop_body;
    *SoN::FromOptree::_walk_loop_body = sub { $walks{ ${ $_[1] } }++; goto &$orig };
}

# walked_once($name, $src, $loops): each loop body of the sub $src makes is
# walked once.
my @held;    # (a freed op's address is a later one's)
sub walked_once ( $name, $src, $loops ) {
    %walks = ();
    my $cv = eval $src or die $@;
    push @held, $cv;
    eval { SoN::FromOptree->translate($cv); 1 } or diag "$name: $@";
    subtest $name => sub {
        is scalar( keys %walks ), $loops, "$loops loop bodies were walked";
        is [ sort { $a <=> $b } values %walks ], [ (1) x $loops ], 'each of them once';
    };
}

# a nest of loops of each translator: while, range foreach, array foreach.
walked_once( 'a nest of six loops',
    'sub { my @a = (1, 2); my $s = 0; my $t = ""; my $i = 0; '
  . 'for my $a1 (1..2) { for my $a2 (@a) { while ($i < 2) { $i++; '
  . 'for my $a4 (1..2) { for my $a5 (@a) { for my $a6 (1..2) { $s += $a6; $t .= $a5 } } } } } } "$s $t" }', 6 );

# A FACT THE PRE-SCAN MISSES IS REFUSED BY NAME, never built on: each scan
# made to miss here (as a scan that missed a form would), the walk refuses
# where it finds what the scan did not say.
sub refused_when_missed ( $name, $scan, $answer, $src, $why ) {
    no strict 'refs';
    no warnings 'redefine';
    my $glob = "SoN::FromOptree::$scan";
    local *$glob = sub { $answer->(@_) };
    my $cv = eval $src or die $@;
    push @held, $cv;
    my $ok = eval { SoN::FromOptree->translate($cv); 1 };
    like $ok ? '' : $@, $why, "$name: refused by name";
}
refused_when_missed( 'an iterator write the scan missed', '_body_writes', sub { 0 },
    'sub { my @a = (1, 2); for my $e (@a) { $e *= 2 } "@a" }',
    qr/^GAP: a loop body writes its iterator \(\d+\) where its ops do not show it/ );
refused_when_missed( 'a slot the scan missed', '_may_write_targs', sub { {} },
    'sub { my $i = 0; my $s = 0; while ($i < 3) { $s += $i; $i++ } $s }',
    qr/^GAP: a loop body rebinds a variable its header's scan missed/ );
refused_when_missed( 'an aggregate write the scan missed', '_loop_aggregates_written', sub { {} },
    'sub { my @a = (1, 2); my @r; for my $i (1 .. 2) { push @r, join(",", @a); for my $e (@a) { $e .= "x" } } "@r" }',
    qr/^GAP: a loop body writes an aggregate after a read that flattened it/ );
refused_when_missed( 'a stamp the scan kept and the back edge lost', '_loop_stamp_scan', sub { {} },
    'sub { my $s; for my $x (@_) { $s = $x } return $s }',
    qr/^GAP: loop-carried value loses its stamp/ );

# EACH GUESS THE HEADER ONCE MADE, in a program that walked a sub again for
# it (the corpus case or probe it is named for), compiled under
# t/lib/WalkCount.pm as the sweep below is. A walk that refused would be
# walked once too, so each program must also translate whole and, through
# the deparser, print what perl prints (as it did when it was walked twice).
use File::Temp qw(tempdir);
use JSON::PP ();
use SoN::Deparse;
my $tmp = tempdir( CLEANUP => 1 );
my $n = 0;
sub program_walked_once ( $name, $src, $loops, %o ) {
    my $f = "$tmp/p" . ++$n . '.pl';
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $json = qx{ulimit -v 4000000; /usr/bin/timeout 900 $^X -Ilib -It/lib -MWalkCount -MO=-q,SoN,json,not_package=SoN '$f' 2>'$f.err'};
    my $err = do { local ( @ARGV, $/ ) = "$f.err"; <> } // '';
    my ($got) = $err =~ /^LOOPS (\d+)/m;
    subtest $name => sub {
        is $got, $loops, "$loops loop bodies were walked";
        is [ $err =~ /^(REWALK .*)$/mg ], [], 'none of them twice';
        is [ $err =~ /^(B::SoN: .*)$/mg ], [], 'every sub translated';
        return if $o{refused};
        my $d = SoN::Deparse->new;
        my $out = eval { $d->render( JSON::PP->new->utf8->decode($json) ) };
        ok defined $out, 'the deparser renders it' or return diag $d->gap // $@;
        open my $g, '>', "$f.d.pl" or die $!;
        print $g $out;
        close $g;
        is scalar qx{$^X '$f.d.pl' 2>&1}, scalar qx{$^X '$f' 2>&1}, 'and it prints what perl prints';
    };
}

# THE ITERATOR WRITE, through each kind of op that writes it (a `$_` op is a
# gvsv under an ex-rv2sv that carries the lvalue flag; an op= is a binop
# flagged STACKED; s/// may name no operand at all).
program_walked_once( 'an assignment to $_ (corpus 190)', <<'EOS', 2 );
sub f { my @a; push @a, 1, 2; my $s = "";
  for my $x (@a) { $s .= $x; $_ = 0 for @a }
  return "$s|@a" }
print f(), "\n";
EOS
program_walked_once( 'an increment of $_ (aun115)', 'my @a=(1,2); $_++ for @a; print "@a\n";', 1 );
program_walked_once( 'an s/// of $_ (POSIX::import)', 'my @l = ("a_h", "b"); s/^(?=\w+_h$)/:/ for @l; print "@l\n";', 1 );
program_walked_once( 'an op= on a lexical alias (aun113)', 'my @a=(1,2); for my $e (@a) { $e *= 2 } print "@a\n";', 1 );

# A PHI'S STAMP the back edge does not keep: an element of @_, a method's value.
program_walked_once( 'a Phi whose init is undef (corpus 106)',
    'sub f { my $s; for my $x (@_) { $s = $x } return $s } print f(3, 4, 5), "\n";', 1 );
program_walked_once( 'a Phi a method call rebinds (corpus 208)', <<'EOS', 1 );
package C; sub new { bless {}, shift } sub g { "g$_[1]" }
sub f { my ($self, $to, @r) = @_; my $val = '';
  for my $i (0 .. $#r) { my $repr = $r[$i]; $val = $self->g($repr) if $repr ne $to }
  return $val }
package main; print C->new->f('Str', qw(Int Num Str)), "\n";
EOS

# A SLOT THE HEADER'S SCAN MUST HOLD: `$_`, the outer foreach's alias, written
# in an inner loop (r/o16).
program_walked_once( 'an inner loop writing the outer alias (o16)',
    'my @a=(1,2); for (@a) { for (my $i=0;$i<1;$i++) { $_.="z" } } print "@a\n";', 2 );

# AN AGGREGATE WRITTEN AFTER A READ FLATTENED IT, on the pass before (lw1, lw23).
program_walked_once( 'an alias write after a read flattened the array (lw1)',
    'my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); for (@a) { $_ .= "x" } } print "@r\n";', 2 );
program_walked_once( 'a slice write after a read flattened the array (lw23)',
    'my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); @a[0,1] = ("p$i","q$i") } print "@r\n";', 1,
    refused => 1 );    # (the deparser renders no slice store, here or at the base)

# A CLASS METHOD is translated for its return type and for its graph; once.
program_walked_once( 'a class method with a loop (corpus 164)', <<'EOS', 1 );
use v5.42; use experimental 'class';
class K { field $r = [3, 4, 5, 6]; method s { my @x = grep { $_ > 3 } $r->@[0 .. $#{ $r } - 1]; "@x" } }
print K->new->s, "\n";
EOS

# THE CORPUS AND THE PROBES: each compiled under t/lib/WalkCount.pm, which
# reports a loop body walked twice in one process (a sub walked twice walks
# its loops twice). SON_WALK_ONCE_QUICK=1 leaves this out.
#
# HELD BY NAME: B::SoN's settle pass (_translate_until_settled) translates
# the whole program again when a walk meets a writer of a package scalar it
# had not scanned -- a method of a class from a file it does not follow, the
# only writer of `$w1step::n`, here. Not a loop's guess, and not removed by
# branch single-walk: a pre-scan of the run set is a design of its own
# (baseline section 25).
my %HELD = map { $_ => 1 } qw(probes/p/w1lib4.pl);
use lib 'tools/lib';
use PvmCorpus qw(read_cases);
SKIP: {
    skip 'SON_WALK_ONCE_QUICK set', 3 if $ENV{SON_WALK_ONCE_QUICK};
    my $dir = tempdir( CLEANUP => 1 );
    my @files;
    my $i = 0;
    for my $c ( read_cases('t/corpus/mdtest/pvm') ) {
        my $f = sprintf '%s/%03d.pl', $dir, ++$i;
        open my $o, '>', $f or die $!;
        print $o $c->{src};
        close $o;
        push @files, $f;
    }
    push @files, sort glob 'docs/research/son-ir-audit-2026-11-19/probes/*/*.pl';
    my $jobs = $ENV{SON_WALK_ONCE_JOBS} // 4;
    my ( %kids, @rewalk, @held, $loops, $ran );
    my $reap = sub {
        my $pid = waitpid -1, 0;
        my $f = delete $kids{$pid} // return;
        open my $fh, '<', "$dir/out.$pid" or return;
        $ran++;
        while (<$fh>) {
            $loops += $1 if /^LOOPS (\d+)/;
            my $name = $f =~ s{\A\Q$dir\E/|\Adocs/research/son-ir-audit-2026-11-19/}{}r;
            push @{ $HELD{$name} ? \@held : \@rewalk }, "$name: $1" if /^(REWALK .*)/;
        }
    };
    for my $f (@files) {
        $reap->() while keys %kids >= $jobs;
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            exec "ulimit -v 4000000; /usr/bin/timeout 900 $^X -Ilib -It/lib -MWalkCount -MO=-q,SoN,json,not_package=SoN '$f' 2>&1 >/dev/null"
               . " | grep -E '^(REWALK|LOOPS)' > '$dir/out.$$'";
        }
        $kids{$pid} = $f;
    }
    $reap->() while %kids;
    is $ran, scalar @files, 'every corpus case and probe was compiled';
    cmp_ok $loops // 0, '>=', 1000, 'and their loops were counted (the instrument ran)';
    is \@rewalk, [], 'no loop body was walked twice (but in a program %HELD names)';
    diag "held by name: $_" for @held;
    my %seen = map { s/:.*//sr => 1 } @held;
    diag "held, and no longer walked twice (take it out of %HELD): $_" for grep { !$seen{$_} } sort keys %HELD;
}

done_testing;
