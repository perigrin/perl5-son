#!/usr/bin/perl
# census.pl [-v] [dir] -- the "every write is on the chain" invariant, checked on B::SoN wires.
# For every effectful node of every graph: is it pinned (control_in) and control-reachable from Start?
# If not: has it consumers (it "rides in" on a value/memory edge) or none (a dead, floating effect)?
use strict; use warnings; use JSON::PP;
my $v = (@ARGV && $ARGV[0] eq '-v') ? shift : 0;
my $dir = shift // '/tmp/claude-0/audit/corpus';
my %MUT = map { $_ => 1 } qw(push pop shift unshift splice open close binmode print printf say syswrite sysread read readline eof
  seek truncate unlink mkdir rmdir rename chdir chmod chown utime link symlink require do eval exit die warn system exec fork wait waitpid kill sleep
  bless tie untie select srand delete each reset undef local chomp chop lock study pos vec substr4 sort_inplace reverse_inplace formline write opendir readdir closedir
  syscall alarm umask setpgrp sysopen flock socket connect bind listen accept send recv shutdown dbmopen dbmclose);
sub tclass {   # what kind of place an Assign target is
  my ($t, $by) = @_;
  return 'undef-skip' unless defined $t;
  my $op = $t->{op}; my $f = $t->{fields} || {};
  return 'element' if $op eq 'Subscript' || $op eq 'Slice';
  if ($op eq 'PadAccess') {
    my $sg = $f->{sigil} // '$';
    return "my-aggregate" if $sg ne '$';
    return 'my-scalar-in-memory' if @{$t->{inputs}||[]} || $f->{shared};
    return 'ssa-scalar';
  }
  return 'package-var' if $op eq 'EntryDef';
  return 'through-ref' if $op eq 'PostfixDeref';
  return 'field' if $op eq 'FieldAccess';
  return 'capture-cell' if $op =~ /^(MakeCell|CellRead|CellParam)$/;
  return 'named-aggregate' if $op =~ /^(ArrayLiteral|HashLiteral)$/;
  return 'const' if $op eq 'Constant';
  return "other:$op";
}
my (%sum, %detail, %perfile, $graphs, $files);
for my $file (sort glob "$dir/*.json") {
  next unless -s $file;
  my $j = eval { decode_json(do { local (@ARGV, $/) = $file; <> }) } or next; $files++;
  (my $case = $file) =~ s{.*/|\.json$}{}g;
  for my $m (sort keys %{$j->{methods}}) {
    my $g = $j->{methods}{$m}; $graphs++;
    my %by = map { $_->{id} => $_ } @{$g->{nodes}};
    my (%succ, %cons);
    for my $n (@{$g->{nodes}}) {
      my @in = map { ref $_ ? @$_ : $_ } @{$n->{inputs}||[]};
      $cons{$_}{$n->{id}} = 1 for grep { defined } @in;
      my $fl = $n->{fields} || {};
      push @{$succ{$n->{control_in}}}, $n->{id} if defined $n->{control_in};
      if ($n->{op} =~ /^(Region|Proj|Loop|If)$/) { push @{$succ{$_}}, $n->{id} for grep { defined } @in[0 .. ($n->{op} eq 'Region' ? $#in : 0)] }
    }
    my %reach; my @q = grep { $_->{op} eq 'Start' } @{$g->{nodes}}; @q = map { $_->{id} } @q;
    while (defined(my $x = shift @q)) { next if $reach{$x}++; push @q, @{$succ{$x}||[]} }
    for my $n (@{$g->{nodes}}) {
      my $op = $n->{op}; my $f = $n->{fields} || {}; my $kind;
      if ($op eq 'Assign') {
        my $nt = $f->{targets} // 1; my @t = map { $by{$_} } grep { defined } @{$n->{inputs}}[0 .. $nt-1];
        my %c = map { tclass($_, \%by) => 1 } @t;
        my @mem = grep { !/^(ssa-scalar|undef-skip|const)$/ } sort keys %c;
        $kind = @mem ? "Assign(" . join('+', @mem) . ")" : "Assign(ssa-only)";
        $kind .= "<-@_" if ($by{ $n->{inputs}[-1] // -1 }{op} // "") eq "ArgsSource";
      }
      elsif ($op eq 'Call') {
        my $dk = $f->{dispatch_kind} // '?';
        if ($dk eq 'builtin') { next unless $MUT{ $f->{name} // '' }; $kind = "Call:builtin:$f->{name}" }
        else { $kind = "Call:$dk" }
      }
      elsif ($op =~ /^(CompoundAssign|EntryWrite|CellWrite|Delete|ElemRestore|LocalAlias|RegexSubst|Transliterate|Chomp|Print|Unwind|BacktickExpr|ListAssign|TryCatch)$/) { $kind = $op }
      else { next }
      my $pinned = defined $n->{control_in};
      my $status = $pinned && $reach{$n->{id}} ? 'on-chain'
                 : $pinned ? 'pinned-unreachable'
                 : keys %{$cons{$n->{id}}||{}} ? 'off-chain-consumed' : 'off-chain-dead';
      $sum{$kind}{$status}++;
      if ($status ne 'on-chain') { push @{$detail{"$kind $status"}}, "$case:$m#$n->{id}"; $perfile{$case}{"$kind $status"}++ }
    }
  }
}
print "wires=$files graphs=$graphs\n";
printf "%-42s %9s %9s %9s %9s\n", 'effect kind', qw(on-chain unreach consumed DEAD);
for my $k (sort keys %sum) { printf "%-42s %9d %9d %9d %9d\n", $k, map { $sum{$k}{$_} // 0 } qw(on-chain pinned-unreachable off-chain-consumed off-chain-dead) }
if ($v) { for my $k (sort keys %detail) { print "\n$k (" . scalar(@{$detail{$k}}) . "):\n  " . join("\n  ", @{$detail{$k}}) . "\n" } }
