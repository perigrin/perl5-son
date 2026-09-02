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

# The filetests are NOT uniform, which is why the family was never
# blanket-typed: `-s` is an Int byte count and `-M` a Num of days. Each earns
# its own row or none.
#
# `-c` WAS typed Boolean on the strength of is_bool, but only two of its three
# paths had been measured. The third is the one that matters:
#
#     -c /dev/null      1      is_bool   (true)
#     -c /etc/hostname  ""     is_bool   (false)
#     -c missing        undef  NOT a bool
#
# Boolean does not admit undef in this lattice, so Boolean was WRONG for it
# rather than narrow -- the same rule the table applies to every other
# undef-on-failure op. Corrected to the join, alongside its -d/-f/-l siblings
# which behave identically.
subtest 'the file tests that can miss are join(Boolean,Undef)' => sub {
    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Boolean' ),
        SoN::IR::Stamp->new( type => 'Undef' ),
    )->type;
    for my $ft (qw( ftchr ftdir ftfile ftlink )) {
        is $r->( [ 'Call', $ft ] ), $lub,
            "$ft is $lub -- undef when the path is absent";
    }
    is $r->( [ 'Call', 'ftsize' ]  ), undef, '-s is still not typed with them';
    is $r->( [ 'Call', 'ftmtime' ] ), undef, '-M is still not typed with them';
};

# THE FILESYSTEM FOUR, measured rather than assumed -- and they are NOT
# uniform, which is why one row cannot cover them. Observed on 5.42.0:
#
#     close   ok=1  fail=""      defined, length 0   -- perl's true/false pair
#     rmdir   ok=1  fail=0       defined, numeric 0
#     unlink  two=2 none=0       a COUNT of files removed
#     binmode ok=1  fail=undef   UNDEF on failure
#
# `close` is the one the table's own comment deferred: "typed once someone
# measures pp_close the way pp_open was measured, rather than assuming a
# Boolean." Measured, it IS perl's canonical Boolean -- 1 and "" -- so the
# assumption was right and now has evidence behind it.
subtest 'close and rmdir are Boolean -- 1 or false, never undef' => sub {
    for my $op (qw( close rmdir )) {
        is $r->( [ 'Call', $op ] ), 'Boolean',
            "$op yields perl's true/false pair";
    }
};

# `unlink` COUNTS what it removed. `unlink @files` returning 2 is not a
# boolean that happens to be true; typing it Boolean would lose the count.
subtest 'unlink is an Int count, not a Boolean' => sub {
    is $r->( [ 'Call', 'unlink' ] ), 'Int',
        'unlink yields the number of files removed';
};

# `binmode` returns undef on failure, so its honest type is the JOIN -- read
# from the lattice, not decided here, exactly as `open` is.
subtest 'binmode is join(Boolean, Undef)' => sub {
    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Boolean' ),
        SoN::IR::Stamp->new( type => 'Undef' ),
    )->type;
    is $r->( [ 'Call', 'binmode' ] ), $lub,
        "binmode is typed to the lattice's join(Boolean,Undef) = $lub";
};

# WHY Boolean <: Str IS THE RIGHT PLACE FOR IT, verified against perl rather
# than assumed -- the close/rmdir rows above depend on it.
#
# `!!1`/`!!0` and `builtin::true`/`builtin::false` are the SAME values: all
# four are is_bool, always defined, and stringify to "1" and "". So does any
# comparison result (`1==1`).
#
# And they behave as strings with no coercion anywhere:
#
#     "x" . true . "y" . false . "z"  ->  "x1yz"
#     length(true), length(false)     ->  1, 0
#     uc(true)                        ->  "1"
#     true eq "1",  false eq ""       ->  both true
#     substr(true,0,1)                ->  "1"
#     true =~ /^1$/                   ->  matches
#
# Which is what `Boolean <: Str` claims. Note they are NOT <: Num even though
# they numify to 1 and 0 -- numification is a coercion Str also has, so it
# argues for nothing narrower.
subtest 'Boolean is a subtype of Str, and not of Num' => sub {
    my $bool = SoN::IR::Stamp->new( type => 'Boolean' );

    ok $bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Str' ) ),
        'Boolean <: Str -- every string operation works on it uncoerced';
    ok !$bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Num' ) ),
        'Boolean is NOT <: Num -- numifying is a coercion, not membership';

    # The consequence the close/rmdir rows rest on: a Boolean is not an Undef,
    # so an op that CAN return undef must not be typed Boolean.
    ok !$bool->is_subtype_of( SoN::IR::Stamp->new( type => 'Undef' ) ),
        'and not <: Undef, which is why binmode is Scalar rather than Boolean';
};

# chdir IS a true Boolean: is_bool on BOTH paths, 1 and "", never undef. The
# distinction from the file tests is measured, not assumed -- they look alike
# and are not.
subtest 'chdir is a true Boolean' => sub {
    is $r->( [ 'Call', 'chdir' ] ), 'Boolean',
        'chdir yields 1 or "", and never undef';
};

# STRING AND NUMERIC BUILTINS with a fixed result and no failure mode.
subtest 'substr, quotemeta and pack are Str; int is Int' => sub {
    is $r->( [ 'Call', 'substr'    ] ), 'Str', 'substr slices a string';
    is $r->( [ 'Call', 'quotemeta' ] ), 'Str', 'quotemeta escapes one';
    is $r->( [ 'Call', 'pack'      ] ), 'Str', 'pack builds one';

    # `int` TRUNCATES TOWARD ZERO -- int(3.7) is 3 and int(-3.7) is -3, an
    # integer either way, never the Num it was given.
    is $r->( [ 'Call', 'int' ] ), 'Int', 'int truncates to an Int';
};

done_testing;
