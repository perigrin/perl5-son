#!/usr/bin/perl
# stats.pl -- per-op histogram over the corpus wires: total, pinned (control_in), no consumers, named as someone's last input
use strict; use warnings; use JSON::PP;
my (%tot, %pin, %nocons, %graphs);
my $files = 0; my $prog = 0;
for my $f (sort glob "/tmp/claude-0/audit/corpus/*.json") {
  next unless -s $f; $files++;
  my $j = eval { decode_json(do { local (@ARGV, $/) = $f; <> }) } or next;
  $prog++ if $j->{methods}{'main::__PROGRAM__'};
  for my $m (keys %{$j->{methods}}) {
    my $g = $j->{methods}{$m}; $graphs{n}++;
    my %cons;
    for my $n (@{$g->{nodes}}) {
      for my $i (map { ref $_ ? @$_ : $_ } @{$n->{inputs}||[]}) { $cons{$i}++ if defined $i }
      $cons{$n->{control_in}}++ if defined $n->{control_in};
      my $fl = $n->{fields} || {};
      for my $k (qw(region)) { $cons{$fl->{$k}}++ if defined $fl->{$k} && !ref $fl->{$k} }
    }
    for my $n (@{$g->{nodes}}) {
      my $op = $n->{op}; $op .= ":" . ($n->{fields}{dispatch_kind}//'') if $op eq 'Call';
      $tot{$op}++; $pin{$op}++ if defined $n->{control_in}; $nocons{$op}++ unless $cons{$n->{id}};
    }
  }
}
print "wires=$files with_program=$prog graphs=$graphs{n}\n";
printf "%-22s %7s %7s %7s\n", qw(op total pinned nocons);
printf "%-22s %7d %7d %7d\n", $_, $tot{$_}, $pin{$_}//0, $nocons{$_}//0 for sort keys %tot;
