# ABOUTME: __CLASS__ yields the enclosing class name -- a value known at translation.
# ABOUTME: It was mapped to Constant with no value, so the factory died.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name, @pkgs) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nuse feature 'class';\nno warnings 'experimental::class';\n$src\n";
    close $fh;
    my $pkgarg = join ',', map { "package=$_" } ('main', @pkgs);
    my $out = qx{$PERL -Ilib -MO=SoN,json,$pkgarg $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return ($w, $err);
}

# `__CLASS__` IS THE ENCLOSING CLASS, and perl gives it its own op -- a
# zero-child `classname` yielding the name:
#
#     method classname { return __CLASS__ }
#     T::classname:  <0> classname[t2]
#
# OpMap mapped it to `Constant` with NO value, so the factory died "Required
# parameter 'value' is missing" and the method vanished from the wire. The
# same shape wantarray had -- except this value IS known at translation time,
# because the CV's stash names it. Nothing needs deferring to a callsite.
subtest '__CLASS__ translates to its class name' => sub {
    my ($w, $err) = wire(
        'class T { method classname { return __CLASS__; } } print T->new->classname;',
        'classname', 'T');
    unlike $err, qr/INTERNAL ERROR/, 'no internal error';
    unlike $err, qr/GAP/, 'and it does not need to refuse -- the value is known';
    ok $w && $w->{methods}{'T::classname'},
        'the method reaches the wire' or return;
    my ($c) = grep { $_->{op} eq 'Constant' }
              ($w->{methods}{'T::classname'}{nodes} // [])->@*;
    ok defined $c, 'it builds a Constant' or return;
    is +($c->{fields}{value} // ''), 'T', 'whose value is the class name';
    is $c->{stamp}, 'Str', 'stamped Str -- a class name is a string';
};

# THE NAME MUST BE THE ENCLOSING CLASS, not a fixed guess. Two classes in one
# file, each reporting its own, so a hardcoded value cannot satisfy both.
#
# NAMED Alpha/Beta, NOT A/B. A class literally named `B` collides with perl's
# own B module -- which B::SoN itself loads -- and the collision made an
# earlier draft of this test report a phantom "the second class in a file is
# silently dropped" defect. There is no such defect: both classes translate.
# The lesson is about the test, not the producer: a single-letter class name
# is a namespace hazard in a program compiled BY a B:: backend.
subtest 'each class reports its own name' => sub {
    my ($w, $err) = wire(
        'class Alpha { method n { __CLASS__ } } class Beta { method n { __CLASS__ } }'
        . ' print Alpha->new->n, Beta->new->n;',
        'twoclasses', 'Alpha', 'Beta');
    unlike $err, qr/INTERNAL ERROR|GAP/, 'both translate';
    ok $w, 'a graph was emitted' or return;
    for my $cls (qw(Alpha Beta)) {
        my ($c) = grep { $_->{op} eq 'Constant' }
                  ($w->{methods}{"${cls}::n"}{nodes} // [])->@*;
        ok defined $c, "$cls\::n builds a Constant" or next;
        is +($c->{fields}{value} // ''), $cls, "and its value is $cls";
    }
};

done_testing;
