# ABOUTME: a package scalar written in a followed module's sub is known written, so a read
# ABOUTME: of it is versioned, not forwarded to a binding (Test::Chalk's subtest save/restore).
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir( CLEANUP => 1 );
mkdir "$dir/lib";
open my $pm, '>', "$dir/lib/SvMod.pm" or die $!;
print $pm "package SvMod;\nour \$G;\nsub f { 1 }\nsub sv { my \$x = \$G; \$G = 1; f(); \$G = ( defined \$x ? \$x : q{} ) . q{ab}; return 1 }\n1;\n";
close $pm;
open my $fh, '>', "$dir/p.pl" or die $!;
print $fh "use lib '$dir/lib';\nuse SvMod;\nSvMod::sv();\nprint \"\$SvMod::G\\n\";\n";
close $fh;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $dir/p.pl 2>/dev/null) );
my @n = @{ $w->{methods}{'SvMod::sv'}{nodes} // [] };
my %consumers;
for my $n (@n) { push @{ $consumers{$_} }, $n for grep { defined } @{ $n->{inputs} // [] } }
my @target_reads = grep {
    my $id = $_->{id};
    $_->{op} eq 'EntryDef' && !@{ $_->{inputs} // [] }
        && grep { $_->{op} ne 'EntryWrite' } @{ $consumers{$id} // [] }
} @n;
ok @n, 'the module sub is on the wire';
is scalar @target_reads, 0, 'no read of $G is the write target itself (each read has its version)';
done_testing;
