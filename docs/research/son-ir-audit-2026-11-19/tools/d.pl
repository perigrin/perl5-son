#!/usr/bin/perl
# d.pl prog.pl [graphre] -- dump the B::SoN wire of a program compactly (id op [inputs] ^control stamp fields)
use strict; use warnings; use JSON::PP;
my ($p, $re) = @ARGV; $re //= '.';
my $json = `perl -I/home/user/repo/lib -MO=-q,SoN,json,not_package=SoN $p 2>/tmp/claude-0/audit/_d.err`;
if (!length $json) { print "NO WIRE: ", `head -c 400 /tmp/claude-0/audit/_d.err`, "\n"; exit 1 }
my $j = decode_json($json);
for my $m (sort keys %{$j->{methods}}) {
  next unless $m =~ /$re/;
  my $g = $j->{methods}{$m};
  print "== $m  returns=[@{$g->{returns}||[]}]", (map { " $_=" . JSON::PP->new->canonical->allow_nonref->encode($g->{$_}) } grep { !/^(nodes|returns|start)$/ } sort keys %$g), "\n";
  for my $n (@{$g->{nodes}}) {
    my $f = $n->{fields} || {};
    my %x = %$n; delete @x{qw(id op inputs stamp fields control_in)};
    printf "%3d %-13s [%s]%s %s %s%s\n", $n->{id}, $n->{op},
      join(",", map { ref $_ ? "[".join(",",map{$_//"-"}@$_)."]" : $_ // "-" } @{$n->{inputs}}),
      (defined $n->{control_in} ? " ^$n->{control_in}" : ""), $n->{stamp} // "-",
      join(" ", map { "$_=" . (ref $f->{$_} ? JSON::PP->new->canonical->encode($f->{$_}) : defined $f->{$_} ? do { (my $v=$f->{$_}) =~ s/\n/\\n/g; $v } : "undef") } sort keys %$f),
      (%x ? " +" . JSON::PP->new->canonical->encode(\%x) : "");
  }
}
