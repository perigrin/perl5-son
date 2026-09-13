# ABOUTME: `exists &sub` tests a symbol-table CV slot, not a container element.
# ABOUTME: Runtime-decidable: a sub installed by a glob assign flips the answer.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/)
          ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* : ();
    return ($said, \@n, $err);
}

# `exists &sub` IS A DIFFERENT QUESTION from `exists $h{k}` -- it asks whether
# a CV slot exists in the symbol table, and OPpEXISTS_SUB marks it (measured
# private=65, i.e. 64|1, against 1 for the element forms). It was refused
# because the `Exists` node takes [container, key, memory] and a sub has no
# container. That is a fact about that NODE, not about the question.
#
# IT IS NOT A COMPILE-TIME CONSTANT, and folding it would be a miscompile.
# Measured on 5.42.0:
#
#     say exists &late;   0
#     *late = sub { 1 };
#     say exists &late;   1
#
# The symbol table is mutable at runtime -- glob assignment, AUTOLOAD, plugin
# loading -- so the answer must be read when the question is asked.
#
# NOTE what it does NOT ask: `exists` is TRUE for a merely DECLARED sub while
# `defined` is false. Measured: `sub declared_only;` gives exists=1 defined=0.
# So the test is "is there a CV slot", not "does it have a body".

subtest 'exists &sub lowers to a symbol-table read' => sub {
    my ($said, $n, $err) = run_and_wire(
        'sub f { 1 } print( (exists &f) ? "y" : "n" );', 'exists-sub');
    is $said, 'y', 'perl says the sub exists' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my ($ed) = grep { $_->{op} eq 'EntryDef' } $n->@*;
    ok $ed, 'a symbol-table entry is built' or return;
    is +($ed->{fields}{sigil} // ''), '&', '... with the code sigil';
    is +($ed->{fields}{symbol} // ''), 'f', '... naming the sub';
};

subtest 'a missing sub is the same shape, not a folded constant' => sub {
    my ($said, $n, $err) = run_and_wire(
        'print( (exists &nope) ? "y" : "n" );', 'exists-missing');
    is $said, 'n', 'perl says it does not exist' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    # NOT folded to a Constant: the symbol table is mutable at runtime, so the
    # answer has to be read rather than baked in.
    ok scalar(grep { $_->{op} eq 'EntryDef' } $n->@*),
        'still a symbol-table read, not a compile-time answer';
};

# THE ELEMENT FORM MUST BE UNAFFECTED. It is the same op with a different
# private flag, and a fix keyed on the op rather than the flag would take it.
subtest 'exists on a hash element still builds an Exists' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my %h=(a=>1); print( (exists $h{a}) ? "y" : "n" );', 'exists-elem');
    is $said, 'y', 'perl finds the key' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    ok scalar(grep { $_->{op} eq 'Exists' } $n->@*),
        'the element form is still an Exists node';
};

done_testing;
