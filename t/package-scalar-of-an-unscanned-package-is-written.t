# ABOUTME: A package scalar counts as written unless the first scan read every sub of its
# ABOUTME: package; a writer the walk meets later is refused by name, not walked again.
use v5.42.0;
use Test2::V0;
use B ();
use File::Temp ();    # (a module whose subs the scan does not read: not the program's)
use SoN::FromOptree;

# WHY. Which package scalars some sub writes decides how every graph reads
# them (_package_scalars_written): a written one is read through memory. The
# first scan reads the program's subs and its followed modules'; a body met
# later -- a method of a class from a file B::SoN does not follow (probe
# p/w1lib4) -- used to send B::SoN round the whole program again (the settle
# pass, _translate_until_settled): a second walk of every sub. Now a scalar
# of a package whose subs the first scan did not all read is taken as
# written, and a writer found later of any other is refused by name.

sub reads { $main::only_read }    # (read, written nowhere)

SoN::FromOptree::_package_scalars_written();
ok !SoN::FromOptree::_key_lives_in_memory('$main::only_read'),
    'a scalar of a package the scan read whole, which no sub writes, is a value';
ok SoN::FromOptree::_key_lives_in_memory('$File::Temp::KEEP_ALL'),
    'a scalar of a package whose subs the scan did not read is written';
ok !SoN::FromOptree::_key_lives_in_memory('$Nowhere::x'),
    'a package with no subs has no sub to write it';

# a writer the first scan did not read, of a scalar it took for a value
my $late = eval 'sub { $main::only_read = 2 }' or die $@;
my $ok = eval { SoN::FromOptree::_scan_run_set_cv( B::svref_2object($late) ); 1 };
like $ok ? '' : $@, qr/^GAP: .*\$main::only_read/, 'a writer found late is refused by name';

done_testing;
