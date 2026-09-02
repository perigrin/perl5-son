# ABOUTME: \*STDOUT is a glob reference, not the string "STDOUT".
# ABOUTME: The gv handler pushed the NAME as a Str Constant, so Ref called it a ScalarRef.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub nodes_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { { $_->%*, ($_->{fields} // {})->%* } }
             ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ];
}

# THE SAME CLASS OF DEFECT AS `\2`: a fabricated value with a confident type.
# `\*STDOUT` is a GLOB reference -- perl prints GLOB(0x...) -- and the producer
# emitted Constant(value="STDOUT") stamped Str, then Ref over it stamped
# ScalarRef. Every part of that is wrong: the value is a NAME rather than the
# glob, and the reference kind follows from the wrong operand kind.
subtest 'a glob reference is not a reference to a string' => sub {
    my $nodes = nodes_of('my $g = \*STDOUT; print $g;', 'globref');
    my ($ref) = grep { $_->{op} eq 'Ref' } $nodes->@*;
    ok defined $ref, 'the Ref node exists' or return;
    isnt $ref->{stamp}, 'ScalarRef',
        'a reference to a glob is not a ScalarRef';
    is $ref->{stamp}, 'GlobRef',
        'a reference to a glob is a GlobRef';
};

# THE OPERAND is where the fabrication starts. The gv handler pushes the glob's
# NAME as a Str Constant, which is right where a name is wanted (naming a
# callee, keying an EntryDef) and wrong where the GLOB ITSELF is the value.
subtest 'the referenced glob is not stamped Str' => sub {
    my $nodes = nodes_of('my $g = \*STDOUT; print $g;', 'globopnd');
    my %byid = map { $_->{id} => $_ } $nodes->@*;
    my ($ref) = grep { $_->{op} eq 'Ref' } $nodes->@*;
    ok defined $ref, 'the Ref node exists' or return;
    my $operand = $byid{ ($ref->{inputs} // [])->[0] // -1 };
    ok defined $operand, 'the Ref has an operand' or return;
    isnt $operand->{stamp}, 'Str',
        'the thing being referenced is a glob, not a string';
};

# A BAREWORD GLOB WITHOUT THE REF (`*STDOUT`) is the same value one indirection
# down, and must not be a Str either. Asserted separately so a fix that only
# patches the srefgen path is caught.
subtest 'a bare glob is not a string' => sub {
    my $nodes = nodes_of('my $g = *STDOUT; print $g;', 'bareglob');
    my @strs = grep { $_->{op} eq 'Constant'
                      && ($_->{value} // '') eq 'STDOUT'
                      && ($_->{stamp} // '') eq 'Str' } $nodes->@*;
    is scalar(@strs), 0,
        'the glob is not represented as the Str "STDOUT"'
        or diag explain [ map { { op => $_->{op}, v => $_->{value}, s => $_->{stamp} } } $nodes->@* ];
};

# THE NAME PATH MUST SURVIVE. The gv handler's Str Constant is CORRECT for a
# callee name and for %ENV -- this is the guard that a fix does not break
# those by stamping every gv as a Glob.
subtest 'a direct call still names its callee' => sub {
    my $nodes = nodes_of('sub foo { 1 } print foo();', 'callee');
    my ($call) = grep { $_->{op} eq 'Call' } $nodes->@*;
    ok defined $call, 'the call exists' or return;
    like +($call->{name} // ''), qr/foo/, 'the callee is still named';
};

done_testing;
