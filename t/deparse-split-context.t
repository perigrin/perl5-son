# ABOUTME: split's reading is its want flag, not whether it has a target array.
# ABOUTME: `my ($a,$b) = split` has no target and is still list context.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub run_src ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $file 2>&1);
    unlink $file;
    return $out;
}

sub emit ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return SoN::Deparse->new->render($data);
}

sub round_trips ($name, $src) {
    my $emitted = emit($src);
    ok defined $emitted, "$name: it renders" or return;
    is run_src($emitted), run_src($src), "$name: it agrees with perl"
        or diag "emitted:\n$emitted";
}

# The handler asked whether split had a TARGET ARRAY and called every other
# case scalar. `my ($a,$b) = split(...)` has no target array and is still LIST
# context, so it pushed a Count -- and the list-assign bound $a to the NUMBER
# and $b to undef:
#
#     sub f { my ($a,$b) = split(/,/,"p,q"); print "$a$b" }
#       perl : pq
#       emit : 2
#
# The op's own want flag answers it: want=3 for the list-assign LHS, want=2
# for `my $n = split`, want=0 with a target for `my @l = split`.
subtest 'a list-assign LHS is list context' => sub {
    round_trips 'two targets',
        qq{sub f { my (\$a, \$b) = split(/,/, "p,q"); print "\$a\$b\\n" }\nf();\n};
    round_trips 'three targets',
        qq{sub f { my (\$a, \$b, \$c) = split(/,/, "p,q,r"); print "\$a\$b\$c\\n" }\nf();\n};
};

# The array form must not regress: it has a target and is the fields.
subtest 'an array target still gets the fields' => sub {
    round_trips 'to an array',
        qq{sub f { my \@l = split(/,/, "p,q,r"); print "\@l\\n" }\nf();\n};
};

# A SPLIT ASSIGNS ITS TARGET ITSELF -- no aassign -- and bound the array to
# the call, so `\@c` was a reference to the call's list (`\(split ...)`,
# "Not an ARRAY reference") and `push @c` pushed onto it, which perl will
# not compile. chalk's LLVM::Context passes `\@chars` so.
subtest 'a split array that is mutated or referenced is a container' => sub {
    round_trips 'a reference to it, passed',
        q{sub g { scalar @{$_[0]} } sub f { my @c = split //, $_[0]; my $n = g(\@c); "$n $c[0]" } print f("abc"), "\n";};
    round_trips 'pushed and popped',
        q{sub f { my @c = split /,/, $_[0]; push @c, "z"; my $l = pop @c; "$l @c" } print f("a,b"), "\n";};
};

# A SPLIT INTO A PACKAGE ARRAY was dropped -- the array stayed empty -- and is
# refused until it is stored as an aassign into one is.
subtest 'a split into a package array is refused' => sub {
    my $file = __FILE__ . ".pkg.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh q{our @c; sub f { @c = split /,/, $_[0]; "@c" } print f("a,b"), "\n";};
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,not_package=SoN $file 2>&1 >/dev/null);
    unlink $file;
    like $err, qr/GAP: a split into a package array is not yet lowered/, 'the producer refuses it';
};

done_testing;
