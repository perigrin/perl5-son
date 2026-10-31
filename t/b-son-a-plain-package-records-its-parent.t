# ABOUTME: A plain package that inherits -- `use parent` at compile time, or a
# ABOUTME: constant `our @ISA = ("Base")` on the main line -- has a class record and its parent.
use v5.42.0;
use Test2::V0;
use JSON::PP ();
use File::Temp ();

sub son_json ($source) {
    my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $source;
    close $fh;
    return JSON::PP->new->decode(scalar `$^X -Ilib -MO=-q,SoN,json $tmp 2>/dev/null`);
}

# pvm 056: Derived has no subs of its own, so it had no record at all, and
# a plain package's parent was never recorded.
for my $case (
    [ q{package Base; sub hi { "base" }
        package Derived; our @ISA = ("Base");
        package main; my $o = bless {}, "Derived"; print $o->SUPER::hi(), "\n";}, 'a constant @ISA on the main line' ],
    [ q{package Base; sub hi { "base" }
        package Derived; use parent -norequire, "Base";
        package main; my $o = bless {}, "Derived"; print $o->hi(), "\n";}, 'use parent' ],
) {
    my ($src, $name) = @$case;
    my $d = son_json($src);
    ok(exists $d->{classes}{Derived}, "$name: Derived has a class record");
    is($d->{classes}{Derived}{parent}, 'Base', "$name: its parent is Base");
}

# A parent nothing calls a method on directly is recorded too (Mid).
{
    my $d = son_json(q{package Base; sub hi { "b" } package Mid; our @ISA = ("Base"); package Leaf; our @ISA = ("Mid");
        package main; my $o = bless {}, "Leaf"; print $o->hi(), "\n";});
    is($d->{classes}{Leaf}{parent}, 'Mid', 'two levels: Leaf inherits from Mid');
    is(($d->{classes}{Mid} // {})->{parent}, 'Base', 'two levels: Mid has a record, inheriting from Base');
}

# Set at run time after a method call, or under a branch: perl's answer
# depends on when, so no parent is claimed.
for my $case (
    [ q{package Base; sub hi { "b" } package main; my $o = bless {}, "Derived"; print $o->hi;
        @Derived::ISA = ("Base"); print $o->hi, "\n";}, 'after a method call' ],
    [ q{package Base; sub hi { "b" } package main; if (@ARGV) { @Derived::ISA = ("Base") }
        my $o = bless {}, "Derived"; print $o->hi, "\n";}, 'under a branch' ],
) {
    my ($src, $name) = @$case;
    my $d = son_json($src);
    ok(exists $d->{classes}{Base}, "$name: the program was translated");
    ok(!defined(($d->{classes}{Derived} // {})->{parent}), "$name: no parent claimed");
}

# A parent from another file (Exporter) is not the program's: not claimed,
# or a consumer would need its declaration.
{
    my $d = son_json(q{package B2; use Exporter; our @ISA = ('Exporter'); sub new { bless {}, shift } sub m { "m" }
        package main; print B2->new->m, "\n";});
    ok(exists $d->{classes}{B2}, 'Exporter parent: the program was translated');
    ok(!defined(($d->{classes}{B2} // {})->{parent}), 'Exporter parent: not claimed');
}

# Not one constant parent: no parent is claimed.
{
    my $d = son_json(q{package Base; sub hi { "b" } package Other; sub hi { "o" }
        package Derived; our @ISA = ("Base", "Other");
        package main; my $o = bless {}, "Derived"; print $o->hi(), "\n";});
    ok(!defined(($d->{classes}{Derived} // {})->{parent}), 'two parents: none claimed');
}

done_testing;
