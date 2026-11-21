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
#            `external` (the clock, the file system, the random stream).
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
#   - `external` reads (time, rand, -e): reads of changeable state that take
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
_rows { reads => 'external' }, qw(
    time rand localtime gmtime glob tied tms getlogin
    stat lstat readlink fileno telldir
    ftis ftsize ftdir ftfile ftlink ftzero ftchr ftmtime fteread fteexec
);

# --- placed by their own handlers (see WHAT IS NOT HERE) ---------------------
my %OWN_HANDLER = map { $_ => 1 } qw(
    push pop shift unshift splice delete each undef local chomp chop
    print say die exit eval set_arylen vec write
);

# effect($name) -> the row, or undef for a builtin with no effect recorded.
sub effect ($name) { return $ROW{ $name // '' } }

# writes($name) -> true when the builtin changes memory or the world.
sub writes ($name) {
    $name //= '';
    return 1 if $OWN_HANDLER{$name};
    return ( $ROW{$name} // {} )->{writes} ? 1 : 0;
}

# reads_state($name) -> where the state its value is of lives, or undef.
sub reads_state ($name) { return ( $ROW{ $name // '' } // {} )->{reads} }

# The state classes a read of which is ORDERED BY CONTROL on this wire: a
# handle's position, the call stack, a variable's pos(). An object-class read
# names its version instead (reads_at_version); an external one floats, and
# is the verifier's to count.
my %ORDERED_READ = map { $_ => 1 } qw(handle stack variable);

# on_chain($name, lvalue => bool) -> true when the walk must pin this builtin
# to the control chain whatever context its value is in.
sub on_chain ( $name, %opt ) {
    my $row = $ROW{ $name // '' } or return 0;
    return 1 if $row->{writes};
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
sub is_version ($name) { return ( $ROW{ $name // '' } // {} )->{version} ? 1 : 0 }

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

# names() -> every builtin with a row, sorted (for the tests).
sub names () { return sort keys %ROW }

1;
