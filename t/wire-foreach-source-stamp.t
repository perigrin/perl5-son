# ABOUTME: A foreach's synthetic list source is an Array -- its stamp must say so.
# ABOUTME: ArrayLiteral's op name means "container"; the STAMP carries ref-or-not.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub stamps_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $w = (length $out && $out =~ /^\{/)
          ? eval { JSON::PP->new->decode($out) } : undef;
    return [] unless $w;
    return [ map  { $_->{stamp} // 'NONE' }
             grep { $_->{op} eq 'ArrayLiteral' }
             map  { $_->{nodes}->@* } values $w->{methods}->%* ];
}

# ArrayLiteral IS NAMED FOR WHAT IT BUILDS, NOT FOR A REFERENCE, and the STAMP
# carries the distinction. Its own comment records why that matters: it was
# once called `ArrayRef`, chalk read the op name, assumed it agreed with the
# stamp, boxed unconditionally, and 37 corpus cases emitted nothing.
#
# So an ArrayLiteral whose stamp is Unknown is the same hazard one step on: the
# op name promises a container and the stamp confirms nothing. `foreach ($l)`
# wraps its scalar source in a synthetic one-element ArrayLiteral, and that
# wrapper was built with no stamp at all while every real literal was stamped:
#
#     my @a=(1,2,3)          Array
#     my $r=[1,2,3]          ArrayRef
#     foreach ($l) { ... }   Unknown     <- the synthetic wrapper
#
# It is a plain array, not a reference: the loop indexes it with Subscript and
# -- since the iterator write-back -- stores back into it.

subtest 'the synthetic foreach source is stamped Array' => sub {
    my $st = stamps_of('my $l="a"; foreach ($l) { print $_ }', 'fs-scalar');
    is scalar($st->@*), 1, 'one ArrayLiteral is built' or return;
    is $st->[0], 'Array', 'and it is stamped Array, not Unknown';
};

subtest 'a multi-element literal source is stamped too' => sub {
    my $st = stamps_of('my ($p,$q)=("a","b"); foreach ($p,$q) { print $_ }',
                       'fs-two');
    ok scalar($st->@*), 'an ArrayLiteral is built' or return;
    is $st->[0], 'Array', 'stamped Array';
};

# THE REAL LITERALS MUST BE UNDISTURBED. Array and ArrayRef are two different
# answers from one constructor, and stamping the synthetic case must not
# flatten that distinction.
subtest 'real literals keep their own stamps' => sub {
    my $arr = stamps_of('my @a=(1,2,3); print $a[0];', 'fs-arr');
    is $arr->[0], 'Array', 'my @a=(...) is Array';

    my $ref = stamps_of('my $r=[1,2,3]; print $$r[0];', 'fs-ref');
    is $ref->[0], 'ArrayRef', 'and [...] is still ArrayRef';
};

done_testing;
