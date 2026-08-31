# ABOUTME: open/readline/ftchr are typed from what perl's pp_* actually returns.
# ABOUTME: Each answers to its own NAME, and the join with Undef is read, not guessed.
use 5.42.0;
use utf8;
use Test::More;
use B::SoN::TypeLibrary;
use SoN::IR::Stamp;

my $r = \&B::SoN::TypeLibrary::result_for;

# `open` returns PUSHi((I32)PL_forkprocess) on success -- an INTEGER, the child
# pid for a pipe-open and 1 otherwise -- and RETPUSHUNDEF on failure
# (pp_sys.c, PP_wrapped(pp_open)). is_bool() is false on BOTH paths, so it is
# not a Boolean however boolean its use looks.
#
# The honest result is join(Int, Undef). The LATTICE says what that is; we do
# not decide it here. Undef and Num sit on different branches under Scalar, so
# their least upper bound is Scalar -- asserted below against Stamp itself so
# this row cannot drift from the lattice it was derived from.
subtest 'open is Scalar: an Int pid or undef' => sub {
    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Int' ),
        SoN::IR::Stamp->new( type => 'Undef' ),
    )->type;
    is $lub, 'Scalar', 'the lattice puts join(Int,Undef) at Scalar';
    is $r->( [ 'Call', 'open' ] ), $lub, 'and open is typed to exactly that';
};

# `readline` yields a line or undef at EOF in scalar context, and the whole
# file in list context. CONTEXT-SENSITIVE ops get the JOIN of their results --
# sound, and vaguer than reading OPf_WANT would be, but never wrong. Scalar <:
# List, so the join of a scalar line and a list of them is List.
subtest 'readline is List: it spans both contexts' => sub {
    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Scalar' ),
        SoN::IR::Stamp->new( type => 'List' ),
    )->type;
    is $lub, 'List', 'the lattice puts join(Scalar,List) at List';
    is $r->( [ 'Call', 'readline' ] ), $lub, 'and readline is typed to that';
};

# The filetests are NOT uniform, which is why the family was never blanket-typed.
# `-c` is a true Boolean (is_bool says so); `-s` is an Int byte count and `-M` a
# Num of days. Each earns its own row or none.
subtest 'ftchr is Boolean, and its siblings are not typed with it' => sub {
    is $r->( [ 'Call', 'ftchr' ] ), 'Boolean', '-c is a Boolean';
    is $r->( [ 'Call', 'ftsize' ]  ), undef, '-s is not typed as one';
    is $r->( [ 'Call', 'ftmtime' ] ), undef, '-M is not typed as one';
};

done_testing;
