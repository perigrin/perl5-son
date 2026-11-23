use v5.42.0; use lib '/home/user/repo/lib'; use JSON::PP; use SoN::Verify;
for my $f (@ARGV) { my $j = qx($^X -I/home/user/repo/lib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null); next unless $j =~ /\S/;
  my $res = SoN::Verify::verify(decode_json($j)); my $v = ref $res eq 'HASH' ? ($res->{violations} // $res) : $res;
  say "$f: ", JSON::PP->new->canonical->encode($v) =~ s/^(.{300}).*/$1/sr; }
