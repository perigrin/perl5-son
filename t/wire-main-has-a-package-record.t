# ABOUTME: main is a package like any other: it has a class record, always, and the record lists
# ABOUTME: its symbols at CHECK -- the program's (imports and all), apart from the toolchain's own.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub wire_of ($src) {
    my $f = "$dir/m.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return eval { JSON::PP->new->decode($j) } // {};
}

# perigrin (2026-11-15): "Create a Class/Package for main." pvm 316 317 013:
# `$main::{floor}` after `use POSIX` -- main had no record, so chalk could not
# say what its stash holds.
{
    my $w = wire_of(qq{use POSIX;\nour \$answer = 1;\nour \@list = (1);\nprint floor(2.5), "\\n";\n});
    my $m = $w->{classes}{main};
    ok($m, 'main has a record with no sub of its own');
    is($m->{name}, 'main', 'named main');
    my $s = $m->{symbols} // {};
    is($s->{floor}{code}, 1, 'an imported sub is one of its symbols');
    is($s->{floor}{code_from}, 'POSIX', '... from the package that defines it');
    is($s->{answer}{scalar}, 1, 'an our scalar is one');
    is($s->{list}{array}, 1, 'an our array is one');
    ok(!exists $s->{nosuch}, 'what nothing made is not');
    ok(!exists $s->{SIG}, 'a key the toolchain made is not the program\'s');
    ok(( grep { $_ eq 'SIG' } ( $m->{symbols_unknown} // [] )->@* ), '... it is listed as unknown (plain perl may or may not have it)');
}

# `use POSIX ()` imports nothing: floor is not main's.
{
    my $w = wire_of(qq{use POSIX ();\nprint POSIX::floor(2.5), "\\n";\n});
    ok(!exists +( $w->{classes}{main}{symbols} // {} )->{floor}, 'use POSIX () imports no floor');
}

# A sub of main's own: its record keeps its subs and adds its symbols.
{
    my $w = wire_of(qq{sub f { 1 }\nprint f(), "\\n";\n});
    is($w->{classes}{main}{subs}{f}{name}, 'f', 'its own sub stays in subs');
    is($w->{classes}{main}{symbols}{f}{code}, 1, 'and is one of its symbols');
    ok(!exists $w->{classes}{main}{symbols}{f}{code_from}, 'its own, not imported');
}

done_testing;
