# ABOUTME: What each perl builtin does to memory and the world, and so how the producer
# ABOUTME: places it: on the control chain, and (if it writes) as a memory version.

use v5.42.0;
use utf8;

package B::SoN::EffectTable;

# ONE TABLE, WHERE THERE WERE EIGHT. The audit of 2026-11-19 (REPORT.md 2.3):
# "Builtins are decided one at a time with no effect table in the producer."
# SoN::FromOptree held seven sets (%GLOBAL_STATE_BUILTIN, %HANDLE_MEMORY_BUILTIN,
# %HANDLE_READ_BUILTIN, %STACK_READ_BUILTIN, %HANDLE_SELECT_BUILTIN,
# %HANDLER_BUILTIN, %VARIABLE_STATE_READ_BUILTIN), each added the day one
# builtin was found off the chain, and SoN::Verify an eighth (%WRITES) saying
# what the seven should have said. A builtin in none of them was an effect
# only in void context: `my $ok = open(...)`, `return bless {}, $c`,
# `mkdir($d) or die` rode a value edge and ran at first use, or never.
#
# KEYED BY PERL OP NAME (`prtf` is printf, `dofile` is `do FILE`): it is what
# the walk has in hand, and it is the `name` a builtin Call carries on the wire.
#
# THREE FACTS PER BUILTIN, all about perl, none about a consumer:
#
#   writes   it changes memory or the world: a variable, an object's class,
#            a handle's position, the file system, a process. It runs where
#            it stands, once, whatever context its value is in.
#   reads    its VALUE is of state a write may change, named by where the
#            state lives: `handle`, `stack`, `variable`, `object-class`,
#            `external` (the file system, the time of day), `clock`.
#   version  it is a version of memory: the wire's builtin Call carries the
#            memory it follows as its last input (`memory_input`) and a later
#            read names it. Only for a write a read IN THIS GRAPH can see --
#            %INC and the subs a require compiles, a handle's buffer, a tie,
#            whatever a __WARN__ handler stores.
#
# AND WHAT FOLLOWS FROM THEM, in one place (the two subs the walk calls):
#
#   on_chain(name)    writes, or reads `handle` / `stack` / `variable` state:
#                     pinned to the control chain IN EVERY CONTEXT.
#   is_version(name)  the `version` column.
#
# WHAT IS NOT HERE, and why:
#   - push, pop, shift, unshift, splice, delete, each, keys, values, chomp,
#     chop, undef, local, s///, tr///, print, say, die, exit, the backtick
#     and every sub call: each has its own handler or node kind that places
#     it. Their rows are in %OWN_HANDLER so that `writes` answers for them
#     (SoN::Verify asks), and on_chain leaves them to their handlers.
#   - `external` reads (localtime, -e, stat): reads of changeable state that take
#     no memory input yet. They are listed, flagged by the verifier
#     (read-unversioned:external), and wait for wire v2's `mem_in`.
#
# AN `object-class` READ NAMES ITS VERSION (reads_at_version): `ref`,
# `blessed` and `reftype` take the memory they read as their last input, the
# way a Count or a Subscript does, and float. `bless` is the version after it.
# Without the pair, `bless $h, "K"; print ref($h)` and `my $r = ref($h); bless
# $h, "K"; print $r` were one wire (K and HASH).

my %ROW;

sub _rows ( $fact, @names ) {
    for my $name (@names) {
        $ROW{$name} = { ( $ROW{$name} // {} )->%*, $fact->%* };
    }
    return;
}

# --- writes the world: files, directories, processes ------------------------
_rows { writes => 1 }, qw(
    open close binmode prtf read sysread syswrite sysopen sysseek seek getc truncate flock
    opendir readdir closedir rewinddir seekdir open_dir
    chdir chroot mkdir rmdir unlink rename link symlink chmod chown utime umask
    system exec fork wait waitpid kill sleep alarm setpgrp setpriority syscall
    socket connect bind listen accept shutdown send recv pipe_op sockpair ssockopt
    dbmopen dbmclose fcntl ioctl
);

# --- writes memory this graph's reads may see --------------------------------
# bless changes what `ref` and method dispatch answer for the object; srand
# what the next rand answers; formline the format accumulator; reset and study
# the variables they name; lock, weaken and unweaken the referent's flags;
# vec in lvalue form is a store handled as one, in rvalue form a pure read.
_rows { writes => 1 }, qw(srand formline reset study lock weaken unweaken);
# A rand ADVANCES THE RANDOM STREAM the next rand reads, and srand reseeds:
# floating, `srand(42); $a = rand; srand(42); $b = rand` named one version
# for both rands and nothing put them after their srands (final audit 4.10).
_rows { writes => 1 }, qw(rand);

# A BLESS IS A STORE TO THE REFERENT'S CLASS, and `ref`, `blessed` and
# `reftype` in this graph read it: a version, so a read after it names it.
_rows { writes => 1, version => 1 }, qw(bless);

# A GLOBAL-STATE OP ALSO ADVANCES MEMORY: `require X; X->import(...)` must not
# be reordered, and nothing but the memory chain says so. tie and untie change
# what every later read of the variable does.
_rows { writes => 1, version => 1 }, qw(require dofile tie untie);

# A HANDLE'S BUFFER AND POSITION are memory the next read of the handle sees.
_rows { writes => 1, version => 1 }, qw(open close);
_rows { writes => 1, version => 1, reads => 'handle' }, qw(readline eof);
_rows { reads => 'handle' }, qw(tell);

# `select FH` changes which handle a bare print writes to (the four-argument
# form is the op `sselect`, which waits and changes nothing here).
_rows { writes => 1 }, qw(select);

# A WARN IS OUTPUT, and its __WARN__ handler is code that may store.
_rows { writes => 1, version => 1 }, qw(warn);

# --- reads state that WHEN decides -------------------------------------------
_rows { reads => 'stack' },    qw(caller);
_rows { reads => 'variable' }, qw(pos);    # (its lvalue form is a store's target: see on_chain)
# (`reftype_of_ref` is the walk's name for `ref \$x`: the kind of thing $x holds)
_rows { reads => 'object-class' }, qw(ref reftype blessed reftype_of_ref);
# THE CLOCK a sleep moves: `time` is read where it stands, on the chain.
_rows { reads => 'clock' }, qw(time);
_rows { reads => 'external' }, qw(
    localtime gmtime glob tied tms getlogin
    stat lstat readlink fileno telldir
    ftis ftsize ftdir ftfile ftlink ftzero ftchr ftmtime fteread fteexec
);

_rows { reads => 'external' }, qw(
    ftatime ftbinary ftblk ftctime fteowned ftewrite ftpipe ftrexec ftrowned ftrread
    ftrwrite ftsgid ftsock ftsuid ftsvtx fttext fttty getsockname getpeername gsockopt
);
_rows { writes => 1, version => 1, reads => 'handle' }, qw(rcatline);
# the four-argument select waits: the world's clock moves
_rows { writes => 1 }, qw(sselect);

# --- dies on a value out of its domain ---------------------------------------
# `log(0)`, `sqrt(-1)`: perl dies ("Can't take log of 0"). On the chain in
# every context, as a division that may fault is: floating and unused it was
# dropped, and the program ran on (audit 2026-11-22).
_rows { faults => 1 }, qw(log sqrt);

# --- pure: the value is of the operands alone, and nothing is changed --------
# A ROW, NOT A DEFAULT: a builtin with no row at all is taken to write
# (writes) and refused by the walk (known), so a new one cannot float by
# omission (audit 2026-11-22: the table was an allow-list).
my %PURE = map { $_ => 1 } qw(
    substr index rindex uc ucfirst lc lcfirst fc quotemeta sprintf join pack unpack
    reverse refaddr is_weak is_bool is_tainted abs int sin cos atan2 exp ceil floor
    chr ord hex oct crypt prototype runcv anonconst
);

# --- placed by their own handlers (see WHAT IS NOT HERE) ---------------------
my %OWN_HANDLER = map { $_ => 1 } qw(
    push pop shift unshift splice delete each undef local chomp chop
    print say die exit eval set_arylen vec write
    subst preinc predec postinc postdec i_preinc i_predec i_postinc i_postdec
    lvref lvavref lvrefslice substr_left
);
# (a container op that is the memory version after it, as a bless is: its
# Call carries mem_out -- SoN::Verify asks)
my %OWN_VERSION = map { $_ => 1 } qw(push pop shift unshift splice);
# AND KNOWN, placed by their own handlers, writing nothing this table says:
# a read of a container or a list, a call, a block run per item.
my %ELSEWHERE = map { $_ => 1 } qw(
    keys values aeach akeys avalues sort split entersub arylen
    grepstart mapstart allstart anystart coreargs custom
);

# known($name) -> true when the table says what the builtin does: a row, pure,
# or placed by its own handler. The walk refuses a builtin Call that is not.
sub known ($name) { $name //= ''; return $ROW{$name} || $PURE{$name} || $OWN_HANDLER{$name} || $ELSEWHERE{$name} ? 1 : 0 }

# faults($name) -> true when the builtin may die on its operands' values.
sub faults ($name) { return ( $ROW{ $name // '' } // {} )->{faults} ? 1 : 0 }

# effect($name) -> the row, or undef for a builtin with no effect recorded.
sub effect ($name) { return $ROW{ $name // '' } }

# writes($name) -> true when the builtin changes memory or the world.
sub writes ($name) {
    $name //= '';
    return 1 if $OWN_HANDLER{$name};
    return 1 unless known($name);    # (no row: may write)
    return ( $ROW{$name} // {} )->{writes} ? 1 : 0;
}

# reads_state($name) -> where the state its value is of lives, or undef.
sub reads_state ($name) { return ( $ROW{ $name // '' } // {} )->{reads} }

# The state classes a read of which is ORDERED BY CONTROL on this wire: a
# handle's position, the call stack, a variable's pos(). An object-class read
# names its version instead (reads_at_version); an external one floats, and
# is the verifier's to count. The clock is ordered: sleep moves it.
my %ORDERED_READ = map { $_ => 1 } qw(handle stack variable clock);

# on_chain($name, lvalue => bool) -> true when the walk must pin this builtin
# to the control chain whatever context its value is in.
sub on_chain ( $name, %opt ) {
    my $row = $ROW{ $name // '' } or return 0;
    return 1 if $row->{writes} || $row->{faults};
    my $reads = $row->{reads} // return 0;
    return 0 unless $ORDERED_READ{$reads};
    # `pos($s) = 0` is the store's target, not a read of the position.
    return 0 if $reads eq 'variable' && $opt{lvalue};
    return 1;
}

# reads_at_version($name) -> true when the builtin's value is of state it
# reads at a memory version: its Call (or RefType, for `ref`) takes the
# current memory as its last input and is left to float.
sub reads_at_version ($name) { return ( ( $ROW{ $name // '' } // {} )->{reads} // '' ) eq 'object-class' ? 1 : 0 }

# is_version($name) -> true when the builtin's Call carries the memory it
# follows and is the memory after it.
sub is_version ($name) { return $OWN_VERSION{ $name // '' } || ( $ROW{ $name // '' } // {} )->{version} ? 1 : 0 }

# stores_operands($name) -> which operands the builtin STORES INTO, by alias:
# 'first', 'second' or 'all' (each element of an array among them), or undef.
# What a sub may store (SoN::FromOptree::ModSets) is built from these, with the
# assignment, op=, ++/--, s///, tr/// and container ops the walk names itself.
# (binmode is not here: it changes a handle's layers, not the variable.)
my %STORES_OPERANDS = (
    ( map { $_ => 'all' }    qw(chomp chop pipe_op sockpair) ),
    ( map { $_ => 'first' }  qw(schomp schop open opendir socket accept) ),
    ( map { $_ => 'second' } qw(read sysread recv) ),
);
sub stores_operands ($name) { return $STORES_OPERANDS{ $name // '' } }

# bound_target($op) -> the op a binding builtin (s///, tr///) STORES INTO when
# `=~` names its target, or undef: none named (it stores `$_`, or a lexical
# by its targ), or it stores nothing (s///r, tr///r, a counting tr///).
# THE TWO SPELL IT APART: s/// takes its target as its first kid; tr/// has
# no kids, and `$x =~ tr/a/z/` is null(STACKED)[target, trans], the target
# its elder sibling (audit 3, risk 2: every scan that took a stacked store's
# target from its first kid saw no store by tr///).
sub bound_target ($op) {
    require B;
    my $n = $op->name;
    return undef unless $n eq 'subst' || $n eq 'trans';
    return undef unless $op->flags & B::OPf_STACKED();
    return undef if $n eq 'subst' && ( ( eval { $op->pmflags } // 0 ) & B::PMf_NONDESTRUCT() );
    return undef if $n eq 'trans' && ( $op->private & B::OPpTRANS_IDENTICAL() );
    return $op->first if $n eq 'subst';
    my $up = eval { $op->parent } or return undef;
    return undef unless $$up && ( $up->flags & B::OPf_KIDS() ) && ${ $up->first } != $$op;
    return $up->first;
}

# pushes_new_value($op) -> true when what the op pushes is a value of its own
# -- its TARG, a new reference, an immortal yes/no/undef, a constant -- and
# not an SV of the program that a later operand could store (fifth final
# audit, Q2-Q5). THE DEFAULT IS "HANDS ON": an op with no row may push a
# variable, an element, a magical value (`$1`, an lvalue substr, `$#a`), or a
# list of them (`x`, `reverse`, a `do` block), read when its consumer runs.
my %NEW_VALUE = map { $_ => 1 } qw(
    const undef add subtract multiply divide modulo pow negate abs int sqrt sin cos exp log atan2 hex oct
    i_add i_subtract i_multiply i_divide i_modulo i_negate
    concat stringify length index rindex ord chr lc uc lcfirst ucfirst fc quotemeta sprintf join crypt
    lt gt le ge eq ne ncmp slt sgt sle sge seq sne scmp i_lt i_gt i_le i_ge i_eq i_ne i_ncmp not
    bit_and bit_or bit_xor nbit_and nbit_or nbit_xor sbit_and sbit_or sbit_xor complement ncomplement scomplement
    left_shift right_shift defined ref refaddr reftype blessed exists is_bool is_weak ceil floor
    srefgen refgen anonlist anonhash anoncode emptyavhv postinc postdec i_postinc i_postdec
    time localtime gmtime rand srand wantarray caller pack unpack match qr split readline
    schomp schop chomp chop trans transr range flop keys mapwhile push unshift subst gv rv2gv av2arylen
);
sub pushes_new_value ($op) {
    require B;
    my $n = $op->name;
    my $want = $op->flags & 3;
    # (in an lvalue's place substr, vec, pos and keys push a proxy of their operand)
    # (`keys %h = N` is one; in a list keys are new strings)
    return 0 if ( $n =~ /\A(?:substr|vec|pos|av2arylen)\z/ || $n eq q{keys} && $want != 3 ) && ( $op->flags & B::OPf_MOD() );
    return 1 if $NEW_VALUE{$n};
    # (a string `x` is a new string; a list `x` repeats the SVs: OPpREPEAT_DOLIST)
    return 1 if $n eq 'repeat' && !( $op->private & 64 );
    # (in scalar context: a new string, a count)
    return 1 if $want == 2 && $n =~ /\A(?:reverse|substr|values|vec|pos|pad[ah]v|rv2[ah]v)\z/;
    return 1 if $n eq 'multiconcat' && !( $op->flags & B::OPf_STACKED() ) && !( $op->private & 16 );
    return 0;
}

# names() -> every builtin with a row, sorted (for the tests).
sub names () { return sort keys %ROW }

1;
