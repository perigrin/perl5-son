# ABOUTME: A method call on `bless REF, "Class"` (directly or through the variable
# ABOUTME: it was assigned to) names that class, as `Class->m` does.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub method_classes ($src) {
    my $data = graph_of($src);
    return [ map { $_->{fields}{class_name} }
        grep { $_->{op} eq 'Call' && ($_->{fields}{dispatch_kind} // '') eq 'method' }
        $data->{methods}{'main::__PROGRAM__'}{nodes}->@* ];
}

# THE BLESS SAYS THE CLASS. `bless {}, "Foo"` with a literal class is as
# static as `Foo->new`; the call on it shipped no class_name and chalk
# refused it ("Call(method) 'hi' has no class_name").
is method_classes(<<'SRC'), ['Foo'], 'a variable holding a literal bless';
package Foo; sub hi { "hi" }
package main;
my $o = bless {}, "Foo";
print $o->hi, "\n";
SRC

# A class that is not a literal is not known here, so none is named.
is method_classes(<<'SRC'), [undef], 'a computed class names none';
package Foo; sub hi { "hi" }
package main;
my $c = $ENV{NO_SUCH_VAR} // "Foo";
my $o = bless {}, $c;
print $o->hi, "\n";
SRC

# A PACKAGE'S new IS A SUB, which reads its invocant from $_[0]: only a
# `class` constructor takes its args as field values with the invocant
# dropped. `Foo->new` (no args, an even count) had its "Foo" dropped too.
{
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh q{package Foo; sub new { bless {}, $_[0] } sub hi { 1 } package main; my $o = Foo->new; my $p = Foo->new(a => 1); print $o->hi;};
    close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null); unlink $f;
    my $nodes = JSON::PP->new->decode($j)->{methods}{'main::__PROGRAM__'}{nodes};
    my %by = map { $_->{id} => $_ } @$nodes;
    my @news = grep { $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq 'new' } @$nodes;
    is [ map { scalar @{ $_->{inputs} } } @news ], [1, 3], 'each keeps its invocant and its args';
    is [ map { $by{ $_->{inputs}[0] }{fields}{value} } @news ], ['Foo', 'Foo'], 'the invocant is the class name';
}

done_testing;
