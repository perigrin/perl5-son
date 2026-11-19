#!/usr/bin/perl
# memcheck.pl [-v] [dir] -- structural checks of the memory encoding on B::SoN wires:
#  K: which node kinds stand as memory versions (named by a read's memory input, or merged by a memory Phi)
#  A: Phi arity against its Region (inputs must pair with the Region's ways in); Loop Phis must have 2
#  D: the two encodings of memory order agree: a pinned node's explicit memory input is the nearest
#     memory version back along its control chain
use strict; use warnings; use JSON::PP;
my $v = (@ARGV && $ARGV[0] eq '-v') ? shift : 0;
my $dir = shift // '/tmp/claude-0/audit/corpus';
sub memidx {  # index of a node's memory input, or undef (chalk's memory_operand rules + the writes')
  my ($n) = @_; my $op = $n->{op}; my $in = $n->{inputs} || []; my $f = $n->{fields} || {};
  return 2 if $op =~ /^(Subscript|Exists|Delete|EntryWrite|CellWrite)$/ && @$in > 2;
  return 1 if $op =~ /^(Count|PostfixDeref|CellRead|MakeCell)$/ && @$in > 1;
  return 1 if $op eq 'Ref' && @$in > 1;
  return 0 if $op =~ /^(FieldAccess|PadAccess|EntryDef)$/ && @$in > 0;
  return 4 if $op eq 'ElemRestore' && @$in > 4;
  return $#$in if $op =~ /^(Call|Unwind)$/ && $f->{memory_input} && @$in;
  return undef;
}
my (%K, %A, %D, @Dex, @Aex, $phis, $mphis, $checked);
for my $file (sort glob "$dir/*.json") {
  next unless -s $file;
  my $j = eval { decode_json(do { local (@ARGV, $/) = $file; <> }) } or next;
  (my $case = $file) =~ s{.*/|\.json$}{}g;
  for my $m (sort keys %{$j->{methods}}) {
    my $g = $j->{methods}{$m};
    my %by = map { $_->{id} => $_ } @{$g->{nodes}};
    my %memphi;   # region id -> memory phi
    my %isver;    # ids used as memory versions
    for my $n (@{$g->{nodes}}) {
      my $f = $n->{fields} || {};
      if ($n->{op} eq 'Phi') {
        $phis++;
        my $r = $by{ $f->{region} // -1 };
        my $nin = scalar @{$n->{inputs}};
        if ($r) {
          my $want = $r->{op} eq 'Loop' ? 2 : scalar grep { defined } @{$r->{inputs}};
          if ($nin != $want) { $A{"$r->{op} phi with $nin inputs for $want ways in" . ($f->{memory} ? ' (memory)' : '')}++; push @Aex, "$case:$m#$n->{id}" }
          else { $A{ok}++ }
        } else { $A{'phi with no region'}++ }
        if ($f->{memory}) { $mphis++; $memphi{ $f->{region} } //= $n; $K{"phi-input:" . ($by{$_}{op} . ($by{$_}{op} eq 'Call' ? ":" . $by{$_}{fields}{dispatch_kind} . (defined $by{$_}{control_in} ? '' : ':UNPINNED') : (defined $by{$_}{control_in} || $by{$_}{op} =~ /^(Phi|MemStart|MakeCell)$/ ? '' : ':UNPINNED')))}++ for grep { defined && $by{$_} } @{$n->{inputs}} }
      }
      my $mi = memidx($n);
      if (defined $mi && defined(my $mid = $n->{inputs}[$mi])) {
        my $mn = $by{$mid} or next; $isver{$mid} = 1;
        my $k = $mn->{op}; $k .= ":" . ($mn->{fields}{dispatch_kind} // '') if $k eq 'Call';
        $k .= ':UNPINNED' unless defined $mn->{control_in} || $k =~ /^(Phi|MemStart|MakeCell)$/;
        $k .= ':valuephi' if $mn->{op} eq 'Phi' && !$mn->{fields}{memory};
        $K{"mem-input:$k"}++;
      }
    }
    # D: dual-encoding agreement
    my $isverkind = sub { my ($p) = @_; my $op = $p->{op};
      return 1 if $op =~ /^(Assign|EntryWrite|CellWrite|Delete|ElemRestore|Call|RegexSubst|LocalAlias|Transliterate)$/;
      return 1 if $isver{ $p->{id} };   # a pinned read that something reads memory at
      return 0 };
    my $back; $back = sub { my ($p, $depth) = @_;   # nearest memory version at or before control node $p
      return undef if !defined $p || $depth > 5000; my $pn = $by{$p} or return undef; my $op = $pn->{op};
      return 'MemStart' if $op eq 'Start';
      if ($op eq 'Region' || $op eq 'Loop') { return $memphi{$p}{id} if $memphi{$p}; return $back->($pn->{inputs}[0], $depth+1) }
      return $back->($pn->{inputs}[0], $depth+1) if $op eq 'Proj';
      return $back->($pn->{control_in} // $pn->{inputs}[0], $depth+1) if $op eq 'If';
      return $p if $isverkind->($pn);
      return $back->($pn->{control_in}, $depth+1) };
    for my $n (@{$g->{nodes}}) {
      next unless defined $n->{control_in};
      my $mi = memidx($n); next unless defined $mi; my $mid = $n->{inputs}[$mi]; next unless defined $mid && $by{$mid};
      my $exp = $back->($n->{control_in}, 0);
      next unless defined $exp; $checked++;
      my $got = $by{$mid}{op} eq 'MemStart' ? 'MemStart' : $mid;
      # a MakeCell (unpinned) standing between: compare through it
      my $g2 = $got; $g2 = do { my $x = $by{$g2}{inputs}[1]; defined $x && $by{$x}{op} eq 'MemStart' ? 'MemStart' : $x } while $g2 ne 'MemStart' && $by{$g2} && $by{$g2}{op} eq 'MakeCell' && defined $by{$g2}{inputs}[1];
      if ($got eq $exp || (defined $g2 && $g2 eq $exp)) { $D{agree}++ }
      else { my $k = "$n->{op} reads memory at " . ($got eq 'MemStart' ? 'MemStart' : $by{$got}{op}) . ", chain says " . ($exp eq 'MemStart' ? 'MemStart' : $by{$exp}{op}); $D{$k}++; push @Dex, "$case:$m#$n->{id} ($k)" }
    }
  }
}
print "phis=$phis memory_phis=$mphis\n\nK: node kinds standing as memory versions\n"; printf "  %-48s %6d\n", $_, $K{$_} for sort keys %K;
print "\nA: phi arity\n"; printf "  %-60s %6d\n", $_, $A{$_} for sort keys %A;
print "\nD: explicit memory input vs nearest version on the control chain (checked $checked pinned nodes)\n"; printf "  %-70s %6d\n", $_, $D{$_} for sort { $D{$b} <=> $D{$a} } keys %D;
if ($v) { print "\nA examples:\n  ", join("\n  ", @Aex[0 .. ($#Aex < 40 ? $#Aex : 40)]), "\nD examples:\n  ", join("\n  ", @Dex[0 .. ($#Dex < 80 ? $#Dex : 80)]), "\n" }
