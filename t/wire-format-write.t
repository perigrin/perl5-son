# ABOUTME: `write` invokes a format CV from the glob's FORM slot.
# ABOUTME: The body is a walkable optree: formline(picture, values...).
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
          ? eval { JSON::PP->new->decode($out, ) } : undef;
    return ($said, $w, $err);
}

sub nodes_of ($w, $meth) {
    return [ ($w->{methods}{$meth} ? $w->{methods}{$meth}{nodes}->@* : ()) ];
}

# A FORMAT IS A CV IN THE GLOB'S FORM SLOT, and it is WALKABLE. The refusal
# said compiling it "needs that body walked and the formline accumulator,
# neither of which is built" -- but B::FM ISA B::CV, with ROOT and START, and
# the body is an ordinary optree:
#
#     leavewrite -> lineseq -> formline(picture_const, $n, $v)
#
# so the first half was already available. `formline` is likewise already
# mapped to a Call with mark-delimited args.
#
# THE PICTURE IS A COMPILE-TIME CONSTANT on the formline, readable from the
# format CV's pad -- measured, "@<<<<<<<<< @>>>>\n" for the format below.

subtest 'a format body becomes its own graph' => sub {
    my ($said, $w, $err) = run_and_wire(<<'SRC', 'fmt-body');
our ($n, $v) = ("widget", 42);
format STDOUT =
@<<<<<<<<< @>>>>
$n, $v
.
write;
SRC
    like $said, qr/widget/, 'perl writes the formatted line' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my ($fmt) = grep { /FORMAT|format/ } keys $w->{methods}->%*;
    ok $fmt, 'the format body is emitted as its own graph' or return;

    my $b = nodes_of($w, $fmt);
    my ($fl) = grep { (($_->{fields} // {})->{name} // '') eq 'formline' } $b->@*;
    ok $fl, '... containing the formline call' or return;

    # THE PICTURE MUST SURVIVE. It is what distinguishes one format from
    # another, and without it two different formats hash-cons to one node --
    # the defect `split` nearly shipped when its pattern was dropped.
    my %by = map { $_->{id} => $_ } $b->@*;
    my ($pic) = grep { defined }
                map { ($by{$_}{fields} // {})->{value} }
                ($fl->{inputs} // [])->@*;
    like $pic, qr/\@<+/, '... carrying the picture line as a constant';

    # And the VALUES: the body reads $n and $v, so both must be inputs.
    my @reads = grep { ($by{$_}{op} // '') eq 'EntryDef' }
                ($fl->{inputs} // [])->@*;
    is scalar(@reads), 2, '... and both interpolated variables';
};

# `write` MUST NAME THE BODY, or the body is emitted with nothing pointing at
# it -- the orphan-body defect the anon-sub work already had to fix once.
subtest 'write names the format it invokes' => sub {
    my ($said, $w, $err) = run_and_wire(<<'SRC', 'fmt-names');
our $v = 7;
format STDOUT =
Total: @###
$v
.
write;
SRC
    like $said, qr/7/, 'perl writes it' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my $prog = nodes_of($w, 'main::__PROGRAM__');
    my ($call) = grep { $_->{op} eq 'Call' } $prog->@*;
    ok $call, 'write builds a Call' or return;
    my $nm = ($call->{fields} // {})->{name} // '';
    ok $nm && exists $w->{methods}{$nm},
        "the call names a body that exists ($nm)";
};

# THE VALUES ARE READ WHERE write RUNS, not where the format was declared.
# `$v` is a package variable the body reads, so the body's graph must contain
# that read rather than a baked-in constant.
subtest 'the format body reads its variables' => sub {
    my ($said, $w, $err) = run_and_wire(<<'SRC', 'fmt-vars');
our $v = 1;
format STDOUT =
@###
$v
.
$v = 99;
write;
SRC
    like $said, qr/99/, 'perl writes the CURRENT value, not the declared one'
        or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    my ($fmt) = grep { /FORMAT|format/ } keys $w->{methods}->%*;
    ok $fmt, 'the body exists' or return;
    my $b = nodes_of($w, $fmt);
    ok scalar(grep { $_->{op} eq 'EntryDef' } $b->@*),
        'the body reads the package variable rather than folding it';
};

done_testing;
