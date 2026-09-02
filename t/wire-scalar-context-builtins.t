# ABOUTME: reverse in scalar context is a Str and sort is undef -- neither is a count.
# ABOUTME: All four shared one rule that only keys/values actually satisfy.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub call_stamp ($src, $name, $builtin) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    my ($c) = grep { $_->{op} eq 'Call'
                     && (($_->{fields} // {})->{name} // '') eq $builtin }
              ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    return $c && $c->{stamp};
}

# ONE RULE FOR FOUR BUILTINS, and only two of them obey it. keys/values/reverse/
# sort shared "List in list context, Int in scalar context" -- true of a COUNT
# and false of the other two. Measured on 5.42.0:
#
#     scalar keys %h        2       a count       Int is right
#     scalar values %h      2       a count       Int is right
#     scalar reverse @a     "321"   a STRING      Int is a miscompile
#     scalar reverse "abc"  "cba"   a STRING
#     scalar reverse(10,20) "0201"  string-reversed "1020", not 2010
#     scalar sort @a        undef   NOT a count at all
#
# reverse in scalar context CONCATENATES its arguments and reverses the
# characters, which is a Str whatever went in. sort in scalar context is
# documented as returning undef and does.
subtest 'scalar reverse is a Str, not a count' => sub {
    is call_stamp('my $s = reverse "abc"; print $s;', 'rev_str', 'reverse'),
        'Str', 'reverse of a string yields a Str';
    is call_stamp('my @a=(1,2,3); my $s = reverse @a; print $s;', 'rev_list', 'reverse'),
        'Str', 'reverse of a list still yields a Str -- it concatenates first';
};

# SORT IS NOT REACHABLE IN SCALAR CONTEXT, so there is nothing to stamp. perl
# warns "Useless use of sort in scalar context" and OPTIMISES THE OP AWAY, so
# no Call is built at all.
#
# ASSERTED AS ABSENCE, not as "the stamp is not Int". Written the second way
# this subtest passed VACUOUSLY -- call_stamp returns undef when it finds no
# node, and `isnt undef, 'Int'` is true for the wrong reason. The rule below
# still drops sort from the count list, because a rule that is unreachable
# today is still a wrong rule to leave written down.
subtest 'scalar sort builds no node to mistype' => sub {
    my $s = call_stamp('my @a=(3,1,2); my $s = sort @a; print "x";', 'sort_scalar', 'sort');
    is $s, undef, 'perl folds scalar sort away, so no Call reaches the wire';
};

# THE TWO THAT ARE COUNTS must keep their Int, or the fix is indistinguishable
# from deleting the scalar-context rule.
subtest 'keys and values are still counts' => sub {
    is call_stamp('my %h=(a=>1,b=>2); my $n = keys %h; print $n;', 'keys_scalar', 'keys'),
        'Int', 'scalar keys is a count';
    is call_stamp('my %h=(a=>1,b=>2); my $n = values %h; print $n;', 'values_scalar', 'values'),
        'Int', 'scalar values is a count';
};

# LIST CONTEXT IS UNCHANGED for all four -- the rule was only wrong on the
# scalar arm, and a fix must not disturb the arm that was right.
subtest 'list context still yields List' => sub {
    is call_stamp('my %h=(a=>1); my @k = keys %h; print "@k";', 'keys_list', 'keys'),
        'List', 'list keys is a List';
    is call_stamp('my @a=(1,2,3); my @r = reverse @a; print "@r";', 'rev_listctx', 'reverse'),
        'List', 'list reverse is a List';
};

done_testing;
