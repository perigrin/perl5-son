# ABOUTME: Mapping table from perl5 opcodes to SoN node types and stack effects.
# ABOUTME: Defines pop count, push count, node type, and flags for each opcode.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';

class SoN::FromOptree::OpMap 0.01 {
    # Each entry: [pop_count, node_type, push_count, flags]
    # pop_count: integer or 'mark' (pop to last mark)
    # node_type: SoN node operation name, or undef for skip/special
    # push_count: 0 or 1
    # flags: bitmask - 1=skip, 2=cfg(branch), 4=cfg(loop), 8=pure

    use constant SKIP   => 1;
    use constant BRANCH => 2;
    use constant LOOP   => 4;
    # PURE marks a Call-producing builtin whose result depends only on its
    # inputs and which mutates nothing observable. Effect-by-default pins every
    # other Call in void position to the control chain; a PURE call is exempt so
    # it stays a floatable data node (CSE/hash-consing preserved).
    use constant PURE   => 8;

    my %MAP = (
        # === Bookkeeping - skip these ===
        null      => [0, undef,     0, SKIP],
        stub      => [0, undef,     0, SKIP],
        enter     => [0, undef,     0, SKIP],
        leave     => [0, undef,     0, SKIP],
        nextstate => [0, undef,     0, SKIP],
        pushmark  => [0, undef,     0, SKIP],  # handled specially
        unstack   => [0, undef,     0, SKIP],
        scope     => [0, undef,     0, SKIP],
        lineseq   => [0, undef,     0, SKIP],
        dbstate   => [0, undef,     0, SKIP],
        methstart => [0, undef,     0, SKIP],
        argcheck  => [0, undef,     0, SKIP],
        scalar    => [0, undef,     0, SKIP],  # context hint
        list      => [0, undef,     0, SKIP],  # context hint
        padrange  => [0, undef,     0, SKIP],  # optimized pad intro
        padany    => [0, undef,     0, SKIP],  # pad placeholder

        # === Constants ===
        const     => [0, 'Constant', 1, 0],

        # === Pad (lexical) variable access ===
        padsv       => [0, 'PadAccess', 1, 0],
        padsv_store => [1, 'Assign',    1, 0],
        # padav/padhv handled directly in FromOptree.pm (need targ/varname extraction)
        # argelem handled directly in FromOptree.pm (need targ/varname extraction)

        # === Global variable access ===
        # gv, gvsv, and rv2sv are handled directly in FromOptree.pm (they
        # need GV name extraction; $N capture reads become RegexCapture).
        rv2av     => [1, undef,         1, SKIP],
        rv2hv     => [1, undef,         1, SKIP],
        rv2cv     => [1, undef,         1, SKIP],
        rv2gv     => [1, undef,         1, SKIP],

        # === Arithmetic ===
        add        => [2, 'Add',      1, 0],
        subtract   => [2, 'Subtract', 1, 0],
        multiply   => [2, 'Multiply', 1, 0],
        divide     => [2, 'Divide',   1, 0],
        negate     => [1, 'Negate',   1, 0],
        i_add      => [2, 'Add',      1, 0],
        i_subtract => [2, 'Subtract', 1, 0],
        i_multiply => [2, 'Multiply', 1, 0],
        i_divide   => [2, 'Divide',   1, 0],
        i_negate   => [1, 'Negate',   1, 0],
        modulo     => [2, 'Modulo',   1, 0],
        i_modulo   => [2, 'Modulo',   1, 0],
        pow        => [2, 'Power',    1, 0],
        preinc     => [1, 'Call',     1, 0],  # ++$x
        predec     => [1, 'Call',     1, 0],  # --$x
        postinc    => [1, 'Call',     1, 0],  # $x++
        postdec    => [1, 'Call',     1, 0],  # $x--
        i_preinc   => [1, 'Call',     1, 0],
        i_predec   => [1, 'Call',     1, 0],
        i_postinc  => [1, 'Call',     1, 0],
        i_postdec  => [1, 'Call',     1, 0],

        # === Bitwise ===
        bit_and      => [2, 'BitAnd',     1, 0],
        bit_or       => [2, 'BitOr',      1, 0],
        bit_xor      => [2, 'BitXor',     1, 0],
        nbit_and     => [2, 'BitAnd',     1, 0],
        nbit_or      => [2, 'BitOr',      1, 0],
        nbit_xor     => [2, 'BitXor',     1, 0],
        sbit_and     => [2, 'BitAnd',     1, 0],
        sbit_or      => [2, 'BitOr',      1, 0],
        sbit_xor     => [2, 'BitXor',     1, 0],
        complement   => [1, 'Complement', 1, 0],
        ncomplement  => [1, 'Complement', 1, 0],
        scomplement  => [1, 'Complement', 1, 0],
        left_shift   => [2, 'LeftShift',  1, 0],
        right_shift  => [2, 'RightShift', 1, 0],

        # === String operations ===
        concat      => [2, 'Concat',    1, 0],
        length      => [1, 'Length',    1, 0],
        # `stringify` ("$x" on its own) is handled in FromOptree, which builds a
        # Coerce(X -> Str). It cannot be mapped here: the generic path has no
        # way to supply Coerce's from_repr/to_repr.
        multiconcat => ['mark', 'Concat', 1, 0],
        # substr is PURE as an rvalue but MUTATES as an lvalue (substr(...)=x);
        # the same op name cannot distinguish them statically, so FromOptree
        # overrides this PURE flag to effectful when the op is the fused
        # store form (OPf_STACKED) in void position.
        substr      => [2, 'Call',      1, PURE], # 2-3 args
        index       => [2, 'Call',      1, PURE],
        rindex      => [2, 'Call',      1, PURE],
        repeat      => [2, 'Repeat',    1, 0],   # x operator
        uc          => [1, 'Call',      1, PURE],
        ucfirst     => [1, 'Call',      1, PURE],
        lc          => [1, 'Call',      1, PURE],
        lcfirst     => [1, 'Call',      1, PURE],
        fc          => [1, 'Call',      1, PURE], # foldcase
        quotemeta   => [1, 'Call',      1, PURE],
        chomp       => [1, 'Call',      1, 0],
        chop        => [1, 'Call',      1, 0],
        schomp      => [1, 'Call',      1, 0],   # scalar chomp
        schop       => [1, 'Call',      1, 0],   # scalar chop
        sprintf     => ['mark', 'Call', 1, PURE],
        join        => ['mark', 'Call', 1, PURE],
        split       => ['mark', 'Call', 1, 0],
        pack        => ['mark', 'Call', 1, PURE],
        unpack      => ['mark', 'Call', 1, PURE],

        # === Numeric comparison ===
        eq          => [2, 'NumEq',    1, 0],
        lt          => [2, 'NumLt',    1, 0],
        gt          => [2, 'NumGt',    1, 0],
        le          => [2, 'NumLe',    1, 0],
        ge          => [2, 'NumGe',    1, 0],
        ne          => [2, 'NumNe',    1, 0],
        ncmp        => [2, 'NumCmp',   1, 0],
        i_eq        => [2, 'NumEq',    1, 0],
        i_lt        => [2, 'NumLt',    1, 0],
        i_gt        => [2, 'NumGt',    1, 0],
        i_le        => [2, 'NumLe',    1, 0],
        i_ge        => [2, 'NumGe',    1, 0],
        i_ne        => [2, 'NumNe',    1, 0],
        i_ncmp      => [2, 'NumCmp',   1, 0],

        # === String comparison ===
        seq         => [2, 'StrEq',    1, 0],
        slt         => [2, 'StrLt',    1, 0],
        sgt         => [2, 'StrGt',    1, 0],
        sle         => [2, 'StrLe',    1, 0],
        sge         => [2, 'StrGe',    1, 0],
        sne         => [2, 'StrNe',    1, 0],
        scmp        => [2, 'StrCmp',   1, 0],

        # === Logical / control flow ===
        and         => [1, undef,      1, BRANCH],
        or          => [1, undef,      1, BRANCH],
        dor         => [1, undef,      1, BRANCH],  # //
        not         => [1, 'Not',      1, 0],
        xor         => [2, 'Xor',      1, 0],
        cond_expr   => [1, undef,      1, BRANCH],
        defined     => [1, 'Defined',  1, 0],
        andassign   => [1, undef,      1, BRANCH],  # &&=
        orassign    => [1, undef,      1, BRANCH],  # ||=
        dorassign   => [1, undef,      1, BRANCH],  # //=

        # === Assignment ===
        sassign     => [2, 'Assign',   1, 0],
        aassign     => ['mark', 'Assign', 1, 0],  # list assign

        # === Subroutine calls ===
        entersub     => ['mark', 'Call', 1, 0],
        method_named => [1, undef,      1, 0],  # handled specially
        method       => [1, undef,      1, 0],
        method_super => [1, undef,      1, 0],
        method_redir => [1, undef,      1, 0],
        method_redir_super => [1, undef, 1, 0],

        # === Return ===
        return      => ['mark', undef,  0, 0],
        leavesub    => [1, undef,       1, 0],
        leavesublv  => [1, undef,       1, 0],

        # === Loops ===
        enterloop   => [0, undef,      0, LOOP],
        leaveloop   => [2, undef,      0, 0],
        iter        => [0, undef,      1, BRANCH],
        enteriter   => [0, undef,      0, LOOP],
        last        => [0, undef,      0, 0],
        next        => [0, undef,      0, 0],
        redo        => [0, undef,      0, 0],

        # === Try/catch ===
        entertry      => [0, undef,    0, BRANCH],
        leavetry      => [1, undef,    1, 0],
        catch         => [0, undef,    0, BRANCH],
        entertrycatch => [0, undef,    0, BRANCH],
        leavetrycatch => [0, undef,    0, 0],
        poptry        => [0, undef,    0, 0],

        # === Array operations ===
        aelem          => [2, 'Subscript', 1, 0],
        aelemfast      => [0, 'Subscript', 1, 0],  # optimized constant index
        aelemfast_lex  => [0, 'Subscript', 1, 0],
        aelemfastlex_store => [1, 'Assign', 1, 0],
        aslice         => ['mark', 'Slice', 1, 0],
        kvaslice       => ['mark', 'Slice', 1, 0],
        lslice         => [2, 'Slice',      1, 0],
        anonlist       => ['mark', 'ArrayRef', 1, 0],
        anonhash       => ['mark', 'HashRef',  1, 0],
        emptyavhv      => [0, 'ArrayRef',  1, 0],  # fused empty []/{}; FromOptree picks Array/Hash via OPpEMPTYAVHV_IS_HV
        av2arylen      => [1, 'Length',     1, 0],  # $#array
        push           => ['mark', 'Call',  1, 0],
        pop            => [1, 'Call',       1, 0],
        shift          => [1, 'Call',       1, 0],
        unshift        => ['mark', 'Call',  1, 0],
        splice         => ['mark', 'Call',  1, 0],
        reverse        => ['mark', 'Call',  1, PURE],
        sort           => ['mark', 'Call',  1, 0],

        # === Hash operations ===
        helem          => [2, 'Subscript', 1, 0],
        hslice         => ['mark', 'Slice', 1, 0],
        kvhslice       => ['mark', 'Slice', 1, 0],
        keys           => [1, 'Call',       1, 0],
        values         => [1, 'Call',       1, 0],
        each           => [1, 'Call',       1, 0],
        aeach          => [1, 'Call',       1, 0],
        akeys          => [1, 'Call',       1, 0],
        avalues        => [1, 'Call',       1, 0],
        exists         => [1, 'Defined',    1, 0],
        delete         => [1, 'Call',       1, 0],
        helemexistsor  => [2, undef,        1, BRANCH],

        # === Multideref (optimized chained access) ===
        multideref     => [1, 'Subscript',  1, 0],

        # === Reference operations ===
        refgen      => [1, 'Ref',      1, 0],  # \expr
        srefgen     => [1, 'Ref',      1, 0],  # \scalar
        ref         => [1, 'RefType',  1, 0],  # ref($x): reference -> type/class name Str (distinct from \x = Ref)
        reftype     => [1, 'Call',     1, 0],
        refaddr     => [1, 'Call',     1, 0],
        bless       => [2, 'Call',     1, 0],
        blessed     => [1, 'Call',     1, 0],
        weaken      => [1, 'Call',     1, 0],
        unweaken    => [1, 'Call',     1, 0],
        is_weak     => [1, 'Call',     1, 0],
        is_bool     => [1, 'Call',     1, 0],
        is_tainted  => [1, 'Call',     1, 0],
        isa         => [2, 'IsaOp',    1, 0],
        tie         => ['mark', 'Call', 1, 0],
        untie       => [1, 'Call',     1, 0],
        tied        => [1, 'Call',     1, 0],

        # === Regex operations ===
        # match and qr are handled directly in FromOptree.pm (PMOP pattern
        # extraction); regcomp is transparent -- it leaves the runtime
        # pattern value on the stack for the following match op.
        subst       => [1, 'Call',     1, 0],
        substcont   => [0, undef,      0, BRANCH],
        trans       => [1, 'Call',     1, 0],
        transr      => [1, 'Call',     1, 0],
        regcomp     => [1, undef,      1, SKIP],
        regcmaybe   => [1, undef,      1, SKIP],
        regcreset   => [1, undef,      1, SKIP],

        # === I/O operations ===
        print       => ['mark', 'Call', 1, 0],
        say         => ['mark', 'Call', 1, 0],
        prtf        => ['mark', 'Call', 1, 0],  # printf
        readline    => [1, 'Call',      1, 0],
        rcatline    => [1, 'Call',      1, 0],
        getc        => [1, 'Call',      1, 0],
        open        => ['mark', 'Call', 1, 0],
        close       => [1, 'Call',      1, 0],
        binmode     => [2, 'Call',      1, 0],
        eof         => [1, 'Call',      1, 0],
        seek        => [3, 'Call',      1, 0],
        tell        => [1, 'Call',      1, 0],
        read        => ['mark', 'Call', 1, 0],
        truncate    => [2, 'Call',      1, 0],
        fileno      => [1, 'Call',      1, 0],
        flock       => [2, 'Call',      1, 0],
        select      => [1, 'Call',      1, 0],
        sselect     => [4, 'Call',      1, 0],
        backtick    => [1, 'BacktickExpr', 1, 0],

        # === File tests ===
        (map { $_ => [1, 'Call', 1, 0] }
            qw(ftatime ftbinary ftblk ftchr ftctime ftdir
               fteexec fteowned fteread ftewrite ftfile ftis
               ftlink ftmtime ftpipe ftrexec ftrowned ftrread
               ftrwrite ftsgid ftsize ftsock ftsuid ftsvtx
               fttext fttty ftzero)),

        # === Filesystem operations ===
        stat        => [1, 'Call',      1, 0],
        lstat       => [1, 'Call',      1, 0],
        rename      => [2, 'Call',      1, 0],
        link        => [2, 'Call',      1, 0],
        symlink     => [2, 'Call',      1, 0],
        readlink    => [1, 'Call',      1, 0],
        unlink      => ['mark', 'Call', 1, 0],
        mkdir       => [2, 'Call',      1, 0],
        rmdir       => [1, 'Call',      1, 0],
        chmod       => ['mark', 'Call', 1, 0],
        chown       => ['mark', 'Call', 1, 0],
        chdir       => [1, 'Call',      1, 0],
        chroot      => [1, 'Call',      1, 0],
        glob        => [1, 'Call',      1, 0],
        opendir     => [2, 'Call',      1, 0],
        readdir     => [1, 'Call',      1, 0],
        closedir    => [1, 'Call',      1, 0],
        rewinddir   => [1, 'Call',      1, 0],
        seekdir     => [2, 'Call',      1, 0],
        telldir     => [1, 'Call',      1, 0],
        open_dir    => [2, 'Call',      1, 0],
        umask       => [1, 'Call',      1, 0],
        utime       => ['mark', 'Call', 1, 0],

        # === Process operations ===
        fork        => [0, 'Call',      1, 0],
        wait        => [0, 'Call',      1, 0],
        waitpid     => [2, 'Call',      1, 0],
        exec        => ['mark', 'Call', 1, 0],
        system      => ['mark', 'Call', 1, 0],
        kill        => ['mark', 'Call', 1, 0],
        alarm       => [1, 'Call',      1, 0],
        sleep       => [1, 'Call',      1, 0],
        exit        => [1, 'Call',      0, 0],

        # === Time operations ===
        time        => [0, 'Call',      1, 0],
        gmtime      => [1, 'Call',      1, 0],
        localtime   => [1, 'Call',      1, 0],
        tms         => [0, 'Call',      1, 0],

        # === Math builtins ===
        abs         => [1, 'Call',      1, PURE],
        sqrt        => [1, 'Call',      1, PURE],
        int         => [1, 'Call',      1, PURE],
        sin         => [1, 'Call',      1, 0],
        cos         => [1, 'Call',      1, 0],
        atan2       => [2, 'Call',      1, 0],
        exp         => [1, 'Call',      1, 0],
        log         => [1, 'Call',      1, 0],
        rand        => [1, 'Call',      1, 0],
        srand       => [1, 'Call',      1, 0],
        ceil        => [1, 'Call',      1, 0],
        floor       => [1, 'Call',      1, 0],

        # === Conversion builtins ===
        chr         => [1, 'Call',      1, 0],
        ord         => [1, 'Call',      1, 0],
        hex         => [1, 'Call',      1, 0],
        oct         => [1, 'Call',      1, 0],
        vec         => [3, 'Call',      1, 0],
        pos         => [1, 'Call',      1, 0],

        # === Misc builtins ===
        undef       => [0, 'Constant',  1, 0],
        wantarray   => [0, 'Constant',  1, 0],
        caller      => [0, 'Call',       1, 0],
        die         => ['mark', undef,   0, 0],  # handled specially in FromOptree.pm
        warn        => ['mark', 'Call',  1, 0],
        require     => [1, 'Call',       1, 0],
        dofile      => [1, 'Call',       1, 0],
        prototype   => [1, 'Call',       1, 0],
        lock        => [1, 'Call',       1, 0],
        reset       => [0, 'Call',       1, 0],
        getlogin    => [0, 'Call',       1, 0],

        # === Grep/map ===
        grepstart   => ['mark', 'Call',  1, 0],
        grepwhile   => [1, undef,        1, BRANCH],
        mapstart    => ['mark', 'Call',  1, 0],
        mapwhile    => [1, undef,        1, BRANCH],

        # === Eval ===
        entereval   => [1, undef,        1, BRANCH],
        leaveeval   => [1, undef,        1, 0],

        # === Control flow ===
        goto        => [1, undef,        0, 0],
        last        => [0, undef,        0, 0],
        next        => [0, undef,        0, 0],
        redo        => [0, undef,        0, 0],
        continue    => [0, undef,        0, SKIP],
        break       => [0, undef,        0, 0],
        dump        => [0, undef,        0, 0],

        # === Smartmatch/given/when (legacy) ===
        smartmatch  => [2, 'Match',      1, 0],
        entergiven  => [1, undef,        0, BRANCH],
        leavegiven  => [1, undef,        1, 0],
        enterwhen   => [1, undef,        0, BRANCH],
        leavewhen   => [1, undef,        1, 0],

        # === Range / flip-flop ===
        range       => [0, undef,        1, BRANCH],
        flip        => [1, undef,        1, BRANCH],
        flop        => [1, undef,        1, BRANCH],

        # === Class operations ===
        initfield   => [0, undef,        0, SKIP],  # field initialization
        classname   => [0, 'Constant',   1, 0],

        # === Closure / anonymous ===
        anoncode    => [0, 'AnonSub',    1, 0],
        anonconst   => [1, 'Call',       1, 0],

        # === Format ===
        enterwrite  => [0, undef,        0, 0],
        leavewrite  => [1, undef,        1, 0],
        formline    => ['mark', 'Call',  1, 0],

        # === Socket operations ===
        socket      => ['mark', 'Call', 1, 0],
        connect     => [2, 'Call',      1, 0],
        listen      => [2, 'Call',      1, 0],
        accept      => [2, 'Call',      1, 0],
        bind        => [2, 'Call',      1, 0],
        shutdown    => [2, 'Call',      1, 0],
        send        => ['mark', 'Call', 1, 0],
        recv        => ['mark', 'Call', 1, 0],
        pipe_op     => [2, 'Call',      1, 0],
        sockpair    => ['mark', 'Call', 1, 0],
        getsockname => [1, 'Call',      1, 0],
        getpeername => [1, 'Call',      1, 0],
        gsockopt    => ['mark', 'Call', 1, 0],
        ssockopt    => ['mark', 'Call', 1, 0],

        # === System V IPC ===
        (map { $_ => ['mark', 'Call', 1, 0] }
            qw(msgctl msgget msgrcv msgsnd
               semctl semget semop
               shmctl shmget shmread shmwrite)),

        # === User/group database ===
        (map { $_ => [0, 'Call', 1, 0] }
            qw(gpwnam gpwuid gpwent spwent epwent
               ggrnam ggrgid ggrent sgrent egrent
               ghbyname ghbyaddr ghostent shostent ehostent
               gnbyname gnbyaddr gnetent snetent enetent
               gpbyname gpbynumber gprotoent sprotoent eprotoent
               gsbyname gsbyport gservent sservent eservent
               getpgrp getppid getpriority)),
        setpgrp     => [2, 'Call',      1, 0],
        setpriority => [3, 'Call',      1, 0],

        # === Argument handling ===
        # argelem handled directly in FromOptree.pm (needs targ/varname extraction)
        argdefelem  => [1, undef,       1, BRANCH],

        # === Deferred blocks ===
        pushdefer   => [0, undef,       0, 0],

        # === Comparison chaining ===
        cmpchain_and => [0, undef,      1, BRANCH],
        cmpchain_dup => [0, undef,      1, 0],

        # === Once ===
        once        => [0, undef,       1, BRANCH],

        # === Custom ops ===
        custom      => [0, 'Call',      1, 0],

        # === Remaining ops (uncommon but completeness) ===
        crypt       => [2, 'Call',      1, 0],
        fcntl       => [3, 'Call',      1, 0],
        ioctl       => [3, 'Call',      1, 0],
        dbmopen     => [3, 'Call',      1, 0],
        dbmclose    => [1, 'Call',      1, 0],
        sysopen     => ['mark', 'Call', 1, 0],
        sysread     => ['mark', 'Call', 1, 0],
        syswrite    => ['mark', 'Call', 1, 0],
        sysseek     => [3, 'Call',      1, 0],
        syscall     => ['mark', 'Call', 1, 0],
        study       => [1, 'Call',      1, 0],
        substr_left => [2, 'Call',      1, 0],

        # Lvalue refs and assignment
        lvref       => [1, 'Call',      1, 0],
        lvavref     => [1, 'Call',      1, 0],
        lvrefslice  => ['mark', 'Call', 1, 0],
        refassign   => [2, 'Assign',    1, 0],

        # Internal compiler ops
        introcv     => [0, undef,       0, SKIP],
        clonecv     => [0, undef,       0, SKIP],
        padcv       => [0, undef,       1, SKIP],
        runcv       => [0, 'Call',      1, 0],
        gelem       => [2, 'Subscript', 1, 0],
        coreargs    => ['mark', 'Call', 1, 0],
        hintseval   => [0, 'Constant',  1, 0],
        avhvswitch  => [1, undef,       1, SKIP],

        # any/all (5.40+)
        allstart    => ['mark', 'Call', 1, 0],
        anystart    => ['mark', 'Call', 1, 0],
        anywhile    => [1, undef,       1, BRANCH],
    );

    method lookup ($opname) {
        return $MAP{$opname};
    }

    method is_skip ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & SKIP) ? true : false;
    }

    method is_branch ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & BRANCH) ? true : false;
    }

    method is_loop ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & LOOP) ? true : false;
    }

    method is_pure ($opname) {
        my $entry = $MAP{$opname} // return false;
        return ($entry->[3] & PURE) ? true : false;
    }

    method pop_count ($opname) {
        my $entry = $MAP{$opname} // return undef;
        return $entry->[0];
    }

    method node_type ($opname) {
        my $entry = $MAP{$opname} // return undef;
        return $entry->[1];
    }

    method push_count ($opname) {
        my $entry = $MAP{$opname} // return undef;
        return $entry->[2];
    }

    method is_known ($opname) {
        return exists $MAP{$opname};
    }

    method known_count () {
        return scalar keys %MAP;
    }
}

1;
