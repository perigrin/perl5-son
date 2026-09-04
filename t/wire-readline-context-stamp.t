# ABOUTME: `<$fh>` is a Scalar in scalar context and a List in list context.
# ABOUTME: It was stamped List everywhere, which does not admit the EOF undef.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub readline_stamp ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return 'NO GRAPH' unless $w;
    my ($c) = grep { (($_->{fields} // {})->{name} // '') eq 'readline' }
              map  { $_->{nodes}->@* } values $w->{methods}->%*;
    return 'NO CALL' unless $c;
    return $c->{stamp} // 'NONE';
}

# readline IS CONTEXT-DEPENDENT, and it was stamped List in every context.
# Measured on 5.42.0 through the observer:
#
#     my $one = <$fh>;    Str        one line
#     my @all = <$fh>;    Str        each element
#     at EOF              Undef      <- this is what makes List WRONG
#
# So in SCALAR context the honest type is join(Str, Undef) = Scalar. List does
# not admit Undef, so stamping it there is a wrong answer rather than a wide
# one -- and `while (my $l = <$fh>)` relies on exactly that EOF undef to
# terminate.
#
# The list-context reading IS a List and stays one.

my $OPEN = 'open my $f, "<", "/etc/hostname" or die;';

subtest 'a scalar-context readline is Scalar' => sub {
    is readline_stamp("$OPEN my \$l = <\$f>; print \$l;", 'rl-scalar'),
       'Scalar', 'my $l = <$f> is Scalar, not List';
};

subtest 'the while-loop idiom is Scalar too' => sub {
    # This is the shape that DEPENDS on the EOF undef: the loop ends when
    # readline returns it. A List stamp cannot represent the terminator.
    is readline_stamp("$OPEN while (my \$l = <\$f>) { print \$l }", 'rl-while'),
       'Scalar', 'while (my $l = <$f>) is Scalar';
};

subtest 'a list-context readline is still a List' => sub {
    is readline_stamp("$OPEN my \@l = <\$f>; print scalar(\@l);", 'rl-list'),
       'List', 'my @l = <$f> stays List';
};

done_testing;
