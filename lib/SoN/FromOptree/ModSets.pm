# ABOUTME: What a sub may store into (its MOD set), through the subs it calls: containers and
# ABOUTME: variables by name, by capture or through a reference; and whether a call may reach one.

use v5.42.0;
use utf8;

package SoN::FromOptree::ModSets;

use B;
use B::Op_private;
use B::SoN::EffectTable;

# WHY. perl pushes an element operand as the element itself, so the op that
# consumes it reads it after every later operand has run:
#
#     my $r = [0]; sub f { $r->[0] = $_[0] + 1; $_[0] }
#     print f(1), $r->[0], f(0), $r->[0];                      perl 1101
#
# Whether a later CALL may store into the element's container is a fact about
# the callee and every sub it calls: its MOD set. A call that provably stores
# nothing there leaves the read where its op stood (`$l->[0], $c->(21)`).
#
# AN EFFECT is { loc, key, reshape }:
#
#   loc  'N:<sigil><stash>::<name>'  a package variable
#        'L:<sigil>:<cv>:<index>'    a lexical, by the pad that declares it
#                                    (a capture is followed out to it)
#        'F:<sigil><name>'           a class field, of any object
#        'R:array' 'R:hash' 'R:scalar'  a container reached through a reference
#        'P'                         the sub's own arguments ($_[N], aliases)
#        'U'                         anything: a call this walk cannot see into
#   key  the element stored, a constant, or '*' for any (or the whole variable)
#   reshape  the container's elements are moved, removed or replaced as a
#        whole (shift, splice, delete, `@a = ...`): an alias to one of them is
#        no longer the element at its index.
#
# CONSERVATIVE ON ALIASING. Two references may name one container, and a
# reference may name a package or captured aggregate: a store through a
# reference reaches every container of its kind that could be referenced.
# Only two constant keys that differ are told apart.
#
# shortcut: implicit calls -- an overloaded operator, a tie's FETCH/STORE, a
# DESTROY -- are not seen; upgrade when a probe shows one storing an operand.

# In a CALLER's terms (op_effects, stores_var) a store into a variable the
# sub declares is one; in a summary it is seen by no caller.
our $KEEP_OWN = 0;

my %SUMMARY;      # cv address -> [ effects ]
my %DIRECT;       # cv address -> { effects => [...], sites => [...] }
my %CV_OF;        # cv address -> B::CV
my $BY_NAME;      # sub name -> [ B::CV ] over the program's own subs

sub _fo ($name) { return SoN::FromOptree->can($name) // die "no SoN::FromOptree::$name\n" }

sub _root ($cv) {
    return B::main_root() if $$cv == ${ B::main_cv() };
    my $r = eval { $cv->ROOT };
    return $r && $$r ? $r : undef;
}

sub _kids ($o) {
    my @k;
    return @k unless $o->flags & B::OPf_KIDS;
    for ( my $k = $o->first; $k && $$k; $k = $k->sibling ) { push @k, $k }
    return @k;
}

# _strip($op) -> the op under a null wrapping only it (ex-rv2sv, ex-aelem);
# a null of several kids (an ex-list) is itself.
sub _strip ($o) {
    $o = $o->first while $o->name eq 'null' && ( $o->flags & B::OPf_KIDS ) && ${ $o->first } && !${ $o->first->sibling };
    return $o;
}

sub _effect ( $loc, $key = '*', $reshape = 0 ) { return { loc => $loc, key => $key // '*', reshape => $reshape ? 1 : 0 } }

sub _sv_of ( $cv, $op ) {
    my $sv = eval { $op->sv };
    if ( ( !$sv || !$$sv || $sv->isa('B::SPECIAL') ) && $op->targ ) {
        $sv = eval { $cv->PADLIST->ARRAYelt(1)->ARRAYelt( $op->targ ) };
    }
    return $sv && $$sv && !$sv->isa('B::SPECIAL') ? $sv : undef;
}

# _const_key($cv, $op) -> a constant subscript's value, or '*'.
sub _const_key ( $cv, $op ) {
    return '*' unless $op && $$op;
    $op = _strip($op);
    return '*' unless $op->name eq 'const';
    my $sv = _sv_of( $cv, $op ) or return '*';
    my $pv = $sv->can('PV') ? eval { $sv->PV } : undef;
    return $pv // ( $sv->can('IV') ? $sv->IV : '*' );
}

sub _gv_key ( $sigil, $gv ) {
    return undef unless $gv && $$gv && $gv->isa('B::GV');
    return 'N:' . $sigil . $gv->STASH->NAME . '::' . $gv->NAME;
}

# _lex($cv, $targ) -> (loc, own): a pad variable, by the pad that declares it.
# A capture is followed OUTSIDE to its declaration; a field or an `our` name is
# not a lexical's storage.
sub _lex ( $cv, $targ ) {
    my $own = 1;
    while (1) {
        my $pn = eval { $cv->PADLIST->ARRAYelt(0)->ARRAYelt($targ) };
        return () unless ref $pn eq 'B::PADNAME' && ( $pn->PV // '' ) =~ /\A([\$\@%])(.+)\z/s;
        my ( $sigil, $name ) = ( $1, $2 );
        return ( 'F:' . $sigil . $name, 0 ) if $pn->FLAGS & B::PADNAMEf_FIELD();
        if ( $pn->FLAGS & B::PADNAMEf_OUR() ) {
            my $st = eval { $pn->OURSTASH };
            return ( 'N:' . $sigil . ( $st && $$st ? $st->NAME : 'main' ) . '::' . $name, 0 );
        }
        return ( "L:$sigil:" . $$cv . ":$targ", $own ) unless $pn->FLAGS & B::PADNAMEf_OUTER();
        my $parent = eval { $pn->PARENT_PAD_INDEX };
        my $out    = eval { $cv->OUTSIDE };
        return ( "L:$sigil:" . $$cv . ":$targ", 0 ) unless $parent && ref $out eq 'B::CV' && $$out;
        ( $cv, $targ, $own ) = ( $out, $parent, 0 );
    }
}

# _referenced($cv) -> { pad index => 1 } for $cv's own variables a reference
# or a closure reaches (SoN::FromOptree::_address_taken).
my %REFERENCED;
sub _referenced ($cv) {
    return $REFERENCED{$$cv} //= _fo('_address_taken')->( $cv, _root($cv), 1 );
}

# _lex_effects($cv, $targ, $reshape, $key) -> the effects of a store into a pad
# variable. One the sub declares itself is a new one each call: seen by no
# caller, unless a closure or a reference reaches it.
sub _lex_effects ( $cv, $targ, $reshape, $key = '*' ) {
    my ( $loc, $own ) = _lex( $cv, $targ );
    return () unless defined $loc;
    return _effect( $loc, $key, $reshape ) unless $own && !$KEEP_OWN;
    return () unless _referenced($cv)->{$targ};
    my $kind = { '$' => 'scalar', '@' => 'array', '%' => 'hash' }->{ substr( $loc, 2, 1 ) };
    return ( _effect( $loc, $key, $reshape ), _effect( "R:$kind", $key, $reshape ) );
}

# _container($cv, $op) -> (loc, holder-op) of an aggregate op: padav, rv2av(gv),
# rv2av(anything). @_ is 'P'. The holder is the op yielding the reference.
sub _container ( $cv, $op ) {
    $op = _strip($op);
    my $n = $op->name;
    return ( ( _lex( $cv, $op->targ ) )[0], undef ) if $n =~ /\Apad[ah]v\z/;
    return () unless $n =~ /\Arv2([ah])v\z/ && ( $op->flags & B::OPf_KIDS );
    my $kind = $1 eq 'a' ? 'array' : 'hash';
    my $in = _strip( $op->first );
    if ( $in->name eq 'gv' ) {
        my $gv = _fo('_op_gv')->( $cv, $in );
        return ( 'P', undef ) if $kind eq 'array' && $gv && $$gv && $gv->NAME eq '_' && $gv->STASH->NAME eq 'main';
        return ( _gv_key( $kind eq 'array' ? '@' : '%', $gv ), undef );
    }
    return ( "R:$kind", $in );
}

# _mderef($cv, $op) -> the levels of a multideref, outermost first: each
# { loc, key }, and the holder loc of the first reference (or undef).
sub _mderef ( $cv, $op ) {
    my @aux = eval { $op->aux_list($cv) };
    return () unless @aux;
    my $actions = shift @aux;
    my ( @levels, $holder );
    my $sv_key = sub ($x) { ref $x ? ( $x->can('PV') && defined eval { $x->PV } ? $x->PV : $x->can('IV') ? $x->IV : '*' ) : $x };
    while (1) {
        my $a   = $actions & B::MDEREF_MASK();
        my $act = $a & B::MDEREF_ACTION_MASK();
        if ( $act == B::MDEREF_reload() ) { $actions = shift @aux; next }
        my $kind = $act < 8 ? 'array' : 'hash';
        my $sig  = $kind eq 'array' ? '@' : '%';
        my $base = $act < 8 ? $act : $act - 7;   # 1 pop, 2 gvsv, 3 padsv, 4 vivify, 5 pad agg, 6 gv agg
        my $loc;
        if    ( $base == 5 ) { ($loc) = _lex( $cv, shift @aux ) }
        elsif ( $base == 6 ) { $loc = _gv_key( $sig, shift @aux ) }
        else {
            if    ( $base == 3 ) { ($holder) = _lex( $cv, shift @aux ) }
            elsif ( $base == 2 ) { $holder = _gv_key( '$', shift @aux ) }
            $loc = "R:$kind";
        }
        my $ix  = $a & B::MDEREF_INDEX_MASK();
        my $key = '*';
        if    ( $ix == B::MDEREF_INDEX_const() ) { $key = $sv_key->( shift @aux ) }
        elsif ( $ix != B::MDEREF_INDEX_none() )  { shift @aux }
        push @levels, { loc => $loc // 'U', key => $key, kind => $kind };
        last if $a & B::MDEREF_FLAG_last();
        $actions >>= B::MDEREF_SHIFT();
    }
    return ( \@levels, $holder );
}

sub _signed_byte ($n) { return $n > 127 ? $n - 256 : $n }

sub _target_my ($o) {
    return ( $o->private & B::OPpTARGET_MY() )
        && ( $B::Op_private::bits{ $o->name }{4} // '' ) eq 'OPpTARGET_MY';
}

# _target_effects($cv, $op, $how) -> the effects of storing into $op, an lvalue:
# $how 'whole' (the variable itself; for an aggregate a reshape) or 'elems'
# (each of an aggregate's elements, as chomp(@a) or an argument does).
sub _target_effects ( $cv, $op, $how = 'whole' ) {
    return () unless $op && $$op;
    my $was = $op->name eq 'null' && $op->targ ? B::ppname( $op->targ ) =~ s/\App_//r : $op->name;
    $op = _strip($op);
    # (an ex-helem keeps its kids; a null with none keeps its old type in its
    # targ, not a pad index)
    return () if $op->name eq 'null' && !( $op->flags & B::OPf_KIDS );
    my $n = $op->name eq 'null' ? $was : $op->name;
    return () if $n =~ /\A(?:pushmark|const|undef|stub|padrange|null)\z/;
    return map { _target_effects( $cv, $_, $how ) } _kids($op) if $n eq 'list';
    return map { _target_effects( $cv, $_, $how ) } ( _kids($op) )[ 1, 2 ] if $n eq 'cond_expr';
    return _lex_effects( $cv, $op->targ, 0 ) if $n eq 'padsv' || $n eq 'padsv_store';
    return _lex_effects( $cv, $op->targ, $how eq 'whole' ) if $n =~ /\Apad[ah]v\z/;
    if ( $n eq 'gvsv' || ( $n eq 'rv2sv' && _strip( $op->first )->name eq 'gv' ) ) {
        my $gv = _fo('_op_gv')->( $cv, $n eq 'gvsv' ? $op : _strip( $op->first ) );
        my $k = _gv_key( '$', $gv );
        return defined $k ? _effect($k) : _effect('U');
    }
    return _effect('R:scalar') if $n eq 'rv2sv';
    if ( $n =~ /\Arv2[ah]v\z/ ) {
        my ($loc) = _container( $cv, $op );
        return () if ( $loc // '' ) eq 'P' && $how eq 'whole';   # the sub's own @_
        return _effect( $loc // 'U', '*', $how eq 'whole' );
    }
    if ( $n eq 'aelem' || $n eq 'helem' ) {
        my ( $c, $k ) = _kids($op);
        my $key = _const_key( $cv, $k );
        my $c0 = _strip($c);
        return _lex_effects( $cv, $c0->targ, 0, $key ) if $c0->name =~ /\Apad[ah]v\z/;
        my ($loc) = _container( $cv, $c );
        return _effect( $loc // 'U', $key );
    }
    if ( $n eq 'aelemfast' ) {
        return _effect( _gv_key( '@', _fo('_op_gv')->( $cv, $op ) ) // 'U', _signed_byte( $op->private ) );
    }
    return _lex_effects( $cv, $op->targ, 0, _signed_byte( $op->private ) )
        if $n eq 'aelemfast_lex' || $n eq 'aelemfastlex_store';
    if ( $n eq 'multideref' ) {
        my ($levels) = _mderef( $cv, $op ) or return _effect('U');
        my $last = $levels->[-1];
        return _effect( $last->{loc}, $last->{key} );
    }
    if ( $n =~ /\A(?:a|h|kva|kvh)slice\z/ ) {
        my @agg = grep { _strip($_)->name =~ /\A(?:pad[ah]v|rv2[ah]v)\z/ } _kids($op);
        my ($loc) = @agg ? _container( $cv, $agg[-1] ) : ();
        return _effect( $loc // 'U' );
    }
    return map { $_->{reshape} = 1; $_ } _target_effects( $cv, ( _kids($op) )[0], 'whole' ) if $n eq 'av2arylen';
    return _target_effects( $cv, ( _kids($op) )[0], 'whole' ) if $n =~ /\A(?:substr|vec|pos)\z/;
    return _effect('U') if $n =~ /\Aentersub\z/;   # an lvalue sub
    return ();
}

# _stores($cv, $op) -> the effects of $op itself as a store (not its kids').
sub _stores ( $cv, $o ) {
    my $n    = $o->name;
    my @kids = _kids($o);
    my $real = sub { grep { $_->name ne 'pushmark' && !( $_->name eq 'null' && !( $_->flags & B::OPf_KIDS ) ) } @_ };
    return _target_effects( $cv, $kids[-1] ) if $n eq 'sassign' && @kids == 2;
    return _target_effects( $cv, $kids[-1] ) if $n eq 'aassign';
    return _lex_effects( $cv, $o->targ, 0 ) if $n eq 'padsv_store';
    return _lex_effects( $cv, $o->targ, 0, _signed_byte( $o->private ) ) if $n eq 'aelemfastlex_store';
    my @e;
    push @e, _lex_effects( $cv, $o->targ, 0 ) if $o->targ && _target_my($o);
    push @e, _target_effects( $cv, $kids[0] ) if $n =~ /\A(?:i_)?(?:pre|post)(?:inc|dec)\z/;
    push @e, _target_effects( $cv, $kids[0] )
        if $o->isa('B::BINOP') && ( $o->flags & B::OPf_STACKED ) && $n ne 'sassign'
        && !$o->isa('B::PMOP');   # op= (a PMOP's STACKED is its =~ target: subst is below, a match stores nothing)
    push @e, _target_effects( $cv, $kids[-1] ), _target_effects( $cv, $kids[0] )
        if $n eq 'multiconcat' && ( $o->flags & B::OPf_STACKED );
    if ( $n =~ /\A(?:subst|trans)\z/ ) {
        my $nondestructive = $n eq 'subst'
            ? ( ( eval { $o->pmflags } // 0 ) & 0x4000000 )            # s///r
            : ( $o->private & ( B::OPpTRANS_IDENTICAL() ) );            # tr counting
        unless ($nondestructive) {
            if    ( $o->flags & B::OPf_STACKED ) { push @e, _target_effects( $cv, $kids[0] ) }
            elsif ( $o->targ && ( eval { $cv->PADLIST->ARRAYelt(0)->ARRAYelt( $o->targ )->PV } // '' ) =~ /\A\$./ ) {
                push @e, _lex_effects( $cv, $o->targ, 0 );
            }
            else { push @e, _effect('N:$main::_') }
        }
    }
    if ( my $which = B::SoN::EffectTable::stores_operands($n) ) {
        my @args = $real->(@kids);
        if ( !@args && $which eq 'all' ) { push @e, _effect('N:$main::_') }   # chomp;
        else {
            my @t = $which eq 'all' ? @args : $which eq 'first' ? $args[0] : $args[1];
            push @e, map { _target_effects( $cv, $_, $which eq 'all' ? 'elems' : 'whole' ) } grep { defined } @t;
        }
    }
    # The container's elements are moved, removed or replaced.
    if ( $n =~ /\A(?:push|unshift|pop|shift|splice)\z/ ) {
        my ($agg) = $real->(@kids);
        push @e, map { $_->{reshape} = 1; $_ } _target_effects( $cv, $agg, 'whole' ) if $agg;
    }
    # (delete's element names its container; a slice's too)
    push @e, map { $_->{reshape} = 1; $_->{key} = '*'; $_ } _target_effects( $cv, $kids[0], 'whole' )
        if $n eq 'delete' && @kids;
    if ( $n eq 'undef' && @kids ) { push @e, _target_effects( $cv, $kids[0], 'whole' ) }
    if ( $n eq 'sort' && ( $o->private & B::OPpSORT_INPLACE() ) ) {
        push @e, map { $_->{reshape} = 1; $_ } _target_effects( $cv, $kids[-1], 'whole' );
    }
    if ( $n eq 'split' && ( $o->private & B::OPpSPLIT_ASSIGN() ) ) {
        if ( $o->private & B::OPpSPLIT_LEX() ) { push @e, _lex_effects( $cv, $o->targ, 1 ) }
        else { push @e, _effect('U') }   # (its array is the pmreplroot gv, or the last kid)
    }
    return @e;
}

# _user_subs() -> { name => [ B::CV ] }: the subs of the program and the
# modules it follows, by their name (a method call is dispatched by name).
sub _user_subs () {
    return $BY_NAME if $BY_NAME;
    my %by;
    my $ours = B::SoN->can('_cv_is_user_code');
    my @stashes = ('main::');
    my %seen;
    while ( defined( my $st = shift @stashes ) ) {
        next if $seen{$st}++;
        no strict 'refs';
        for my $name ( sort keys %{$st} ) {
            if ( $name =~ /\A[A-Za-z_]\w*::\z/ && $st ne 'main::' . $name ) { push @stashes, $st eq 'main::' ? $name : $st . $name; next }
            next unless $name =~ /\A[A-Za-z_]\w*\z/;
            my $glob = ${$st}{$name};
            next unless ref( \$glob ) eq 'GLOB';
            my $code = *{$glob}{CODE} or next;
            my $c = B::svref_2object($code);
            next unless $c->isa('B::CV');
            next unless $st eq 'main::' || !$ours || $ours->($c);
            push $by{$name}->@*, $c;
        }
    }
    return $BY_NAME = \%by;
}

# may_be_called_unknown($cv) -> true when a call this walk cannot see into may
# be a call of $cv (and so hand it places, arg_stored_by_call's `unknown`): an
# anonymous sub, a named one whose code is taken (`\&f`, `*f{CODE}`, `goto
# &f` counts as seen), or any sub where the program calls a method by a name
# made at run time (audit 2, K1).
my ( %CODE_TAKEN, $DYNAMIC_METHOD, $SCANNED_CALLS );
sub may_be_called_unknown ($cv) {
    return 1 if $cv->CvFLAGS & B::CVf_ANON;
    unless ($SCANNED_CALLS) {
        $SCANNED_CALLS = 1;
        my @roots = ( [ B::main_cv(), B::main_root() ], map { [ $_, _root($_) ] } map { $_->@* } values _user_subs()->%* );
        for my $pair (@roots) {
            my ( $rcv, $root ) = @$pair;
            next unless $root && $$root;
            for my $o ( _fo('_subtree_ops')->($root) ) {
                $DYNAMIC_METHOD = 1 if $o->name eq 'method';
                next unless $o->name =~ /\A(?:s?refgen|rv2gv|anoncode)\z/ || $o->name eq 'rv2cv' && !( $o->private & B::OPpENTERSUB_NOPAREN() );
                for my $g ( grep { $_->name eq 'gv' } _fo('_subtree_ops')->($o) ) {
                    my $gv = eval { _fo('_op_gv')->( $rcv, $g ) } // next;
                    my $code = $gv && $$gv ? $gv->CV : undef;
                    $CODE_TAKEN{$$code} = 1 if $code && $$code;
                }
            }
        }
    }
    return 1 if $DYNAMIC_METHOD || $CODE_TAKEN{$$cv};
    return 0;
}

# args_may_be_places($cv) -> true when a caller may hand $cv its arguments as
# places (FromOptree's _handle_entersub): it, or one it calls, stores through
# $_[N] or its invocant; or it reads @_ after a store; or a call this walk
# cannot see into may be its call (audit 2, K1).
sub args_may_be_places ($cv) {
    my @s = summary($cv)->@* or return 0;
    return 1 if grep { $_->{loc} eq 'P' } @s;
    return 1 if _read_after_store( $cv, sub (@eff) { scalar @eff }, 1 );
    return may_be_called_unknown($cv);
}

# Methods every object has that store nothing of the program's.
my %UNIVERSAL_READ = map { $_ => 1 } qw(isa can DOES VERSION);

# _callees($cv, $entersub) -> (\@cvs, $shares_args) or () for a call that
# cannot be resolved: a named sub, a method by its name (every sub of that
# name), a code ref held by a lexical stored once with `\&name` or `sub {...}`.
sub _callees ( $cv, $call ) {
    my @kids = _kids($call);
    my $list = @kids == 1 && _strip( $kids[0] ) != $kids[0] || ( @kids == 1 && $kids[0]->name eq 'null' ) ? $kids[0] : $call;
    my @items = _kids($list);
    my $last = $items[-1] or return ();
    my $shares = ( $call->private & B::OPpENTERSUB_AMPER() ) && !( $call->flags & B::OPf_STACKED ) ? 1 : 0;
    my $c = _strip($last);
    my $cn = $c->name;
    if ( $cn =~ /\Amethod_(?:named|super|redir|redir_super)\z/ ) {
        my $sv = eval { $c->meth_sv };
        if ( ( !$sv || !$$sv || $sv->isa('B::SPECIAL') ) && $c->targ ) {
            $sv = eval { $cv->PADLIST->ARRAYelt(1)->ARRAYelt( $c->targ ) };
        }
        my $name = $sv && $$sv && $sv->can('PV') ? $sv->PV : return ();
        $name =~ s/\A.*:://;
        my $subs = _user_subs()->{$name};
        return ( $subs, 0 ) if $subs && @$subs;
        return ( [], 0 ) if $UNIVERSAL_READ{$name};
        return ();
    }
    if ( $cn eq 'gv' || $cn eq 'rv2cv' && _strip( $c->first )->name eq 'gv' ) {
        my $gvop = $cn eq 'gv' ? $c : _strip( $c->first );
        my $gv = _fo('_op_gv')->( $cv, $gvop );
        my $code = $gv && $$gv ? $gv->CV : undef;
        return () unless $code && $$code && $code->isa('B::CV') && _root($code);
        return ( [$code], $shares );
    }
    # A CODE REF in a lexical the sub stores once, with a sub it names.
    if ( $cn eq 'padsv' || ( $cn eq 'rv2cv' && _strip( $c->first )->name eq 'padsv' ) ) {
        my $pad = $cn eq 'padsv' ? $c : _strip( $c->first );
        my $code = _code_ref_of( $cv, $pad->targ );
        return $code ? ( [$code], $shares ) : ();
    }
    return ();
}

# _code_ref_of($cv, $targ) -> the B::CV a lexical holds, when $cv declares it
# and stores it once, from `\&name` or `sub {...}`; undef otherwise.
sub _code_ref_of ( $cv, $targ ) {
    my ( $loc, $own ) = _lex( $cv, $targ );
    return undef unless $own;
    my $root = _root($cv) or return undef;
    my @stores = grep {
        my $o = $_;
        ( $o->name eq 'padsv_store' && $o->targ == $targ )
            || ( $o->name eq 'sassign' && do { my @k = _kids($o); @k == 2 && _strip( $k[1] )->name eq 'padsv' && _strip( $k[1] )->targ == $targ } )
    } _fo('_subtree_ops')->($root);
    return undef unless @stores == 1;
    return undef if _referenced($cv)->{$targ};
    my $val = _strip( ( _kids( $stores[0] ) )[0] );
    if ( $val->name eq 'anoncode' ) { return _fo('_anoncode_cv')->( $cv, $val ) }
    if ( $val->name =~ /\As?refgen\z/ ) {
        my @ops = _fo('_subtree_ops')->($val);
        my @g = grep { $_->name eq 'gv' } @ops;
        return undef unless @g == 1 && grep { $_->name eq 'rv2cv' } @ops;
        my $gv = _fo('_op_gv')->( $cv, $g[0] );
        my $code = $gv && $$gv ? $gv->CV : undef;
        return $code && $$code && $code->isa('B::CV') && _root($code) ? $code : undef;
    }
    return undef;
}

# _call_args($call) -> the argument ops of an entersub (no pushmark, no cv).
sub _call_args ($call) {
    my @kids = _kids($call);
    my @items = @kids == 1 && ( $kids[0]->flags & B::OPf_KIDS ) ? _kids( $kids[0] ) : @kids;
    pop @items;
    return grep { $_->name ne 'pushmark' } @items;
}

# arg_stored_by_call($cv, $call) -> true when the call is passed a variable or
# an element -- $_[N] is that location, not a copy -- that a sub it reaches
# stores by name and then reads through @_: the wire passes the value as it
# was, so the read gives the old one (final audit 2026-11-24, class C). In the
# sub's own order: a read of @_ before the store took the value it had; a
# `local` is a new variable, not the one $_[N] names; reshaping an aggregate
# leaves its element where $_[N] holds it; a store through $_[N] itself is the
# argument's copy-out, lowered.
sub arg_stored_by_call ( $cv, $call ) {
    my @args = _call_args($call) or return 0;
    my $site = _site( $cv, $call );
    local $KEEP_OWN = 1;
    # (REACHABLE: other code may name the argument's variable -- a package
    # variable, an element, a captured or referenced lexical -- so a call this
    # walk cannot see into may store it: nothing proves the alias private)
    my ( @places, $reachable );
    for my $a (@args) {
        my $o = _strip($a);
        if ( $o->name =~ /\A(?:padsv|gvsv|rv2sv)\z/ ) {
            push @places, [ loc => $_->{loc} ] for _target_effects( $cv, $o );
            my ( undef, $own ) = $o->name eq 'padsv' ? _lex( $cv, $o->targ ) : ( undef, 0 );
            $reachable = 1 if !$own || _referenced($cv)->{ $o->targ };
        }
        # (shortcut: an argument that is the caller's own $_[N] aliases what
        # nothing here names -- any store meets it; not counted, upgrade when
        # a sub hands its $_[N] on to one storing that variable by name)
        elsif ( my $p = place( $cv, $o ) ) {
            next if $p->{levels}[-1]{loc} eq 'P';
            push @places, [ place => $p ];
            $reachable = 1;
        }
    }
    return 0 unless @places;
    # AN UNKNOWN CALLEE (a code value, a name made at run time) may store a
    # reachable variable and read @_: not proved private.
    return $reachable ? 1 : 0 if $site->{unknown};
    my $hits = sub (@eff) {
        @eff = grep { $_->{loc} ne 'P' && $_->{loc} ne 'U' && !$_->{reshape} } @eff;
        for my $pl (@places) {
            return 1 if $pl->[0] eq 'loc' ? scalar( grep { $_->{loc} eq $pl->[1] } @eff ) : ( conflict( $pl->[1], \@eff ) // '' ) eq 'store';
        }
        return 0;
    };
    for my $sub ( ( $site->{cvs} // [] )->@* ) { return 1 if _read_after_store( $sub, $hits, $reachable ) }
    return 0;
}

# arg_localized_by_call($cv, $call, $places) -> true when the call is passed a
# variable or an element that a sub it reaches -- or one that sub calls --
# localizes, and the argument is an alias there: passed as a place ($places),
# or an $_[N] a reached sub takes a reference to (audit 2, K2). `local` gives
# the NAME a new scalar; the caller's $_[N] still holds the old one, which
# the place, a pointer to the name's storage, does not. A call this walk
# cannot see into may do either.
sub arg_localized_by_call ( $cv, $call, $places, $elems = 0 ) {
    # ($elems: only an element argument, and only an element's `local`)
    my %locs = map { $_->{loc} => 1 } grep { $_->{loc} =~ /\A[NL]:/ } map { _target_effects( $cv, $_ ) }
        grep { !$elems || _strip($_)->name =~ /\A(?:aelem|helem|multideref|aelemfast(?:_lex)?)\z/ } _call_args($call);
    return 0 unless %locs;
    my @todo = _site( $cv, $call );
    my ( %seen, $localized, $aliased );
    $aliased = $places;
    while ( my $site = shift @todo ) {
        # (a call this walk cannot see into: any code the program runs that
        # localizes the variable, or a package not read whole, may be it)
        return 1 if $site->{unknown} && grep { _fo('_localized_anywhere')->($_) } sort keys %locs;
        next if $site->{unknown};
        for my $sub ( ( $site->{cvs} // [] )->@* ) {
            next if $seen{$$sub}++;
            my $root = _root($sub) or next;
            for my $o ( _fo('_subtree_ops')->($root) ) {
                if ( $o->name =~ ( $elems ? qr/\A(?:helem|aelem|multideref)\z/ : qr/\A(?:gvsv|rv2sv|rv2av|rv2hv|helem|aelem)\z/ ) && ( $o->private & 128 ) ) {   # OPpLVAL_INTRO
                    local $KEEP_OWN = 1;
                    $localized ||= grep { $locs{ $_->{loc} } } _target_effects( $sub, $o );
                }
                # (`\$_[0]`: a reference to the caller's variable itself)
                $aliased ||= grep { $_->name =~ /\Aaelem/ && ( ( place( $sub, $_ ) // { levels => [ {} ] } )->{levels}[0]{loc} // '' ) eq 'P' }
                    _fo('_subtree_ops')->($o) if $o->name =~ /\A(?:s?refgen)\z/;
                push @todo, _site( $sub, $o ) if _is_call($o);
            }
        }
    }
    return $localized && $aliased ? 1 : 0;
}

# _read_after_store($sub, $hits, $reachable) -> true when, in $sub's ops in
# order, a store $hits names (its own, not a `local`; or a call's; or, where
# the arguments are $reachable, a call it cannot see into) comes before a read
# of @_ (_reads_args_op).
sub _read_after_store ( $sub, $hits, $reachable = 0 ) {
    my $root = _root($sub) or return 0;    # (no body here -- XS: it stores none of the program's variables by name)
    my $stored = 0;
    for my $o ( _post_order($root) ) {
        return 1 if $stored && _reads_args_op( $sub, $o );
        next if $stored;
        if ( _is_call($o) ) {
            my $s = _site( $sub, $o );
            # (a call this walk cannot see into may store what other code reaches)
            $stored = 1 if $s->{unknown} ? $reachable : $hits->( map { summary($_)->@* } ( $s->{cvs} // [] )->@* );
        }
        elsif ( !_is_local($o) ) {
            $stored = 1 if $hits->( _stores( $sub, $o ) );
        }
    }
    return 0;
}

# _post_order($root) -> its ops, each after its kids: the order straight code
# runs in (a store after the operands it reads).
sub _post_order ($root) {
    my @out;
    my $walk;
    $walk = sub ($o) {
        if ( $o->flags & B::OPf_KIDS ) { for ( my $k = $o->first; ref($k) && $$k; $k = $k->sibling ) { $walk->($k) } }
        push @out, $o;
    };
    $walk->($root);
    undef $walk;
    return @out;
}

# _is_local($op) -> true for a `local` of a package variable: a new one the
# old is saved from, not a store into it.
sub _is_local ($o) {
    my $t = $o->name eq 'sassign' && $o->can('last') ? _strip( $o->last ) : $o;
    return ( $t->name =~ /\A(?:gvsv|rv2sv|rv2av|rv2hv)\z/ && ( $t->private & 128 ) ) ? 1 : 0;   # OPpLVAL_INTRO
}

# call_stores_through_args($cv, $call) -> true when a sub the call reaches
# stores through its arguments ($_[N], aliases): a P effect in its summary.
sub call_stores_through_args ( $cv, $call ) {
    my ($cvs) = _callees( $cv, $call ) or return 0;
    return scalar grep { grep { $_->{loc} eq 'P' } summary($_)->@* } ( $cvs // [] )->@*;
}

# stores_invocant($cv, $call) -> true for a method call a sub of whose name
# may store its $_[0] -- the caller's invocant variable, which the wire passes
# as a value (final audit 2026-11-24, class H). (Moving @_, a shift, is no
# store; nor is a store through the invocant, `$_[0]{k} = 1`.)
sub stores_invocant ( $cv, $call ) {
    my @k = _kids($call);
    my @items = @k == 1 && ( $k[0]->flags & B::OPf_KIDS ) ? _kids( $k[0] ) : @k;
    return 0 unless @items && _strip( $items[-1] )->name =~ /\Amethod/;
    # (a `my` scalar's: an element or a package scalar invocant is passed as
    # its location, and its store reaches it)
    my ($inv) = _call_args($call);
    return 0 unless $inv && _strip($inv)->name eq 'padsv';
    my ($cvs) = _callees( $cv, $call ) or return 0;
    for my $sub ( ( $cvs // [] )->@* ) {
        return 1 if grep { $_->{loc} eq 'P' && !$_->{reshape} && ( $_->{key} eq '0' || $_->{key} eq '*' ) } summary($sub)->@*;
    }
    return 0;
}

# _reads_args_op($sub, $op) -> true for an op of $sub that reads its @_: an
# element of it, all of it, a shift or pop of it, `&f;` or `goto &f` handing
# it on (a multideref is counted: it may start at @_). A foreach, map or grep
# over it too: its alias reads each element where the body does.
sub _reads_args_op ( $sub, $o ) {
    my $n = $o->name;
    return 1 if $n =~ /\A(?:shift|pop)\z/ && !( $o->flags & B::OPf_KIDS );
    return 1 if $n eq 'multideref' || $n eq 'goto';
    return 1 if $n eq 'entersub' && !( $o->flags & B::OPf_STACKED );   # `&f;`
    return 0 unless $n =~ /\A(?:aelemfast|gv)\z/;
    my $gv = eval { _fo('_op_gv')->( $sub, $o ) } or return 0;
    return 0 unless $gv->NAME eq '_';
    return 1 if $n eq 'aelemfast';
    my $av = $o->parent;
    return 0 unless $$av && $av->name eq 'rv2av';
    # (an element or a slice of it; all of it a copy only where a list
    # assign takes it, `my ($v) = @_` -- read whole elsewhere, a join or a
    # foreach, T2 reads its aliases)
    my $up = $av->parent; $up = $up->parent while $$up && $up->name =~ /\A(?:null|list)\z/;
    # (a foreach, map or grep over @_ reads each element where its body does:
    # after a store before it, the alias is no value -- aliases-as-places)
    return $$up && $up->name =~ /\A(?:aassign|aelem|aslice|enteriter|mapstart|grepstart)\z/ ? 1 : 0;
}

# _is_call($op) -> true for an op that runs code of the program: a sub or
# method call, a string eval, a require or do FILE, a tie.
sub _is_call ($o) { return $o->name =~ /\A(?:entersub|entereval|require|dofile|tie|untie|goto)\z/ ? 1 : 0 }

# _site($cv, $op) -> { cvs => [...], shares => 0|1, args => [...] } for a
# call op, or { unknown => 1 }.
sub _site ( $cv, $o ) {
    my $n = $o->name;
    if ( $n eq 'goto' ) {   # goto &sub shares @_
        my ($k) = _kids($o);
        return { unknown => 1 } unless $k;
        my @g = grep { $_->name eq 'gv' } _fo('_subtree_ops')->($k);
        my $gv = @g == 1 ? _fo('_op_gv')->( $cv, $g[0] ) : undef;
        my $code = $gv && $$gv ? $gv->CV : undef;
        return { unknown => 1 } unless $code && $$code && $code->isa('B::CV') && _root($code);
        return { cvs => [$code], shares => 1, args => [] };
    }
    return { unknown => 1 } unless $n eq 'entersub';
    my ( $cvs, $shares ) = _callees( $cv, $o );
    return { unknown => 1 } unless $cvs;
    return { cvs => $cvs, shares => $shares, args => [ _call_args($o) ] };
}

# _alias_loops($cv, $root, \@ops) -> effects of a foreach, map or grep whose
# iterator is stored: each element of its list is the iterator in turn.
sub _alias_loops ( $cv, $ops, $stored_scalar ) {
    my @e;
    for my $o (@$ops) {
        my ( $var_loc, @list );
        if ( $o->name eq 'enteriter' ) {
            my @k = _kids($o);
            if ( $o->targ ) { ($var_loc) = _lex( $cv, $o->targ ) }
            else {
                my ($g) = grep { _strip($_)->name eq 'gv' } @k;
                $var_loc = $g ? _gv_key( '$', _fo('_op_gv')->( $cv, _strip($g) ) ) : 'N:$main::_';
            }
            my ($l) = grep { $_->name eq 'null' && ( $_->flags & B::OPf_KIDS ) || $_->name eq 'list' } @k;
            @list = $l ? grep { $_->name ne 'pushmark' } _kids($l) : ();
        }
        elsif ( $o->name =~ /\A(?:map|grep)start\z/ ) {
            $var_loc = 'N:$main::_';
            my @k = grep { $_->name ne 'pushmark' } _kids($o);
            @list = @k[ 1 .. $#k ];
        }
        else { next }
        next unless defined $var_loc && $stored_scalar->{$var_loc};
        push @e, map { _target_effects( $cv, $_, 'elems' ) } @list;
    }
    return @e;
}

# _direct($cv) -> { effects, sites }: what $cv's own ops store, and its calls.
sub _direct ($cv) {
    return $DIRECT{$$cv} if $DIRECT{$$cv};
    $CV_OF{$$cv} = $cv;
    my $root = _root($cv);
    my ( @e, @sites, @loops );
    my @ops = $root ? _fo('_subtree_ops')->($root) : ();
    my %stored;    # every scalar loc stored, an own one too (a loop's iterator)
    for my $o (@ops) {
        my @s = _stores( $cv, $o );
        for my $s (@s) { $stored{ $s->{loc} } = 1 }
        # (an own lexical's store has no effect outside, but a loop it iterates may)
        if ( $o->name =~ /\A(?:padsv|padsv_store)\z/ && ( $o->flags & B::OPf_MOD ) ) {
            my ($loc) = _lex( $cv, $o->targ );
            $stored{$loc} = 1 if defined $loc;
        }
        push @e, @s;
        push @loops, $o if $o->name =~ /\A(?:enteriter|mapstart|grepstart)\z/;
        if ( _is_call($o) ) {
            my $site = _site( $cv, $o );
            push @sites, $site;
            # (an iterator handed to a call may be stored by it)
            if ( $site->{args} ) {
                for my $a ( $site->{args}->@* ) {
                    my $s = _strip($a);
                    if ( $s->name eq 'padsv' ) { my ($loc) = _lex( $cv, $s->targ ); $stored{$loc} = 1 if defined $loc }
                    elsif ( $s->name eq 'gvsv' || $s->name eq 'rv2sv' ) { $stored{$_->{loc}} = 1 for _target_effects( $cv, $s ) }
                }
            }
        }
    }
    push @e, _alias_loops( $cv, \@loops, \%stored );
    return $DIRECT{$$cv} = { effects => \@e, sites => \@sites };
}

sub _ekey ($e) { return join "\t", $e->{loc}, $e->{key}, $e->{reshape} }

# _site_effects($cv, $site, \%summary) -> a call's effects in its caller's
# terms: what each callee may store, its argument stores onto the arguments.
sub _site_effects ( $cv, $site, $sum ) {
    return _effect('U') if $site->{unknown};
    my @e;
    my $params = 0;
    for my $c ( $site->{cvs}->@* ) {
        for my $x ( ( $sum->{$$c} // [] )->@* ) {
            if   ( $x->{loc} eq 'P' ) { $params = 1 }
            else                      { push @e, $x }
        }
    }
    if ($params) {
        push @e, map { _target_effects( $cv, $_, 'elems' ) } ( $site->{args} // [] )->@*;
        push @e, _effect('P') if $site->{shares};
    }
    return @e;
}

# summary($cv) -> [ effects ]: what a call of $cv may store, transitively.
sub summary ($cv) {
    return $SUMMARY{$$cv} if $SUMMARY{$$cv};
    # Every sub reachable from $cv, then a fixpoint over them.
    my @todo = ($cv);
    my %reach;
    while ( my $c = shift @todo ) {
        next if $reach{$$c}++ || $SUMMARY{$$c};
        $CV_OF{$$c} = $c;
        for my $s ( _direct($c)->{sites}->@* ) { push @todo, ( $s->{cvs} // [] )->@* }
    }
    my %sum = map { $_ => $SUMMARY{$_} } grep { $SUMMARY{$_} } map { $$_ } values %CV_OF;
    my %set = map { $_ => {} } keys %reach;
    my $changed = 1;
    while ($changed) {
        $changed = 0;
        for my $a ( sort keys %reach ) {
            my $c = $CV_OF{$a};
            my $d = _direct($c);
            my @new = ( $d->{effects}->@*, map { _site_effects( $c, $_, \%sum ) } $d->{sites}->@* );
            for my $e (@new) {
                next if $set{$a}{ _ekey($e) };
                $set{$a}{ _ekey($e) } = $e;
                $changed = 1;
            }
            $sum{$a} = [ map { $set{$a}{$_} } sort keys $set{$a}->%* ];
        }
    }
    $SUMMARY{$_} = $sum{$_} for keys %reach;
    return $SUMMARY{$$cv};
}

# op_effects($cv, $op) -> the effects of the calls in $op's subtree, in $cv's
# terms (not the stores $op makes itself, nor a sub it only makes).
sub op_effects ( $cv, $op ) {
    my @e;
    for my $o ( _fo('_subtree_ops')->($op) ) {
        next unless _is_call($o);
        my $site = _site( $cv, $o );
        my %sum = map { ( $$_ => summary($_) ) } ( $site->{cvs} // [] )->@*;
        local $KEEP_OWN = 1;
        push @e, _site_effects( $cv, $site, \%sum );
    }
    return @e;
}

# subtree_effects($cv, $op) -> what $op's subtree may store, in $cv's terms:
# its own ops' stores, a foreach, map or grep's writes through its iterator
# into its list, and its calls' (audit 2, K7).
sub subtree_effects ( $cv, $op ) {
    local $KEEP_OWN = 1;
    my ( @e, @loops, %stored );
    for my $o ( _fo('_subtree_ops')->($op) ) {
        my @s = _stores( $cv, $o );
        $stored{ $_->{loc} } = 1 for @s;
        if ( $o->name =~ /\A(?:padsv|padsv_store)\z/ && ( $o->flags & B::OPf_MOD ) ) {
            my ($loc) = _lex( $cv, $o->targ );
            $stored{$loc} = 1 if defined $loc;
        }
        push @e, @s;
        push @loops, $o if $o->name =~ /\A(?:enteriter|mapstart|grepstart)\z/;
    }
    return ( @e, _alias_loops( $cv, \@loops, \%stored ), op_effects( $cv, $op ) );
}

# aggregate_place($cv, $op) -> where a whole aggregate (padav, padhv, or a
# package one's rv2av/rv2hv) lives, as place() gives an element's: any element.
sub aggregate_place ( $cv, $op ) {
    $op = _strip($op);
    my $kind = $op->name =~ /av\z/ ? 'array' : 'hash';
    if ( $op->name =~ /\Apad[ah]v\z/ ) {
        my $p = array_place( $cv, $op->targ ) or return undef;
        $_->{kind} = $kind for $p->{levels}->@*;
        return $p;
    }
    local $KEEP_OWN = 1;
    my ($e) = _target_effects( $cv, $op, 'elems' ) or return undef;
    return { levels => [ { loc => $e->{loc}, key => '*', kind => $kind, refd => 1 } ] };
}

# stores_var($cv, $op, $key) -> true when $op itself stores the variable
# $key names: 'p<pad index>' or 'g<sigil><stash>::<name>' (as
# SoN::FromOptree::_reread_alias_operand_stored_later spells it).
sub stores_var ( $cv, $op, $key ) {
    my $loc = $key =~ /\Ap(\d+)\z/ ? ( _lex( $cv, $1 ) )[0] : $key =~ /\Ag(.+)\z/s ? "N:$1" : undef;
    return 0 unless defined $loc;
    local $KEEP_OWN = 1;
    return scalar grep { $_->{loc} eq $loc } _stores( $cv, $op );
}

# place($cv, $op) -> where an element operand lives: { levels => [ { loc,
# key, kind } ... ] outermost first, holder => loc of the scalar holding the
# first reference (or undef), refd => may a reference reach the container }.
sub place ( $cv, $op ) {
    my $p = _place( $cv, $op ) or return undef;
    # A lexical the sub declares is reached by a reference only if one is taken.
    for my $l ( $p->{levels}->@* ) {
        $l->{refd} = $l->{loc} =~ /\AL:.:(\d+):(\d+)\z/ && $1 == $$cv ? ( _referenced($cv)->{$2} ? 1 : 0 ) : 1;
    }
    return $p;
}

# array_place($cv, $targ) -> where a lexical array lives, as place() gives an
# element's, for any element of it (a foreach's list).
sub array_place ( $cv, $targ ) {
    my ($loc) = _lex( $cv, $targ );
    return undef unless defined $loc;
    my $refd = $loc =~ /\AL:.:(\d+):(\d+)\z/ && $1 == $$cv ? ( _referenced($cv)->{$2} ? 1 : 0 ) : 1;
    return { levels => [ { loc => $loc, key => '*', kind => 'array', refd => $refd } ] };
}

sub _place ( $cv, $op ) {
    $op = _strip($op);
    my $n = $op->name;
    if ( $n eq 'multideref' ) {
        my ( $levels, $holder ) = _mderef( $cv, $op ) or return undef;
        return { levels => $levels, holder => $holder };
    }
    if ( $n eq 'aelemfast' ) {
        return { levels => [ { loc => _gv_key( '@', _fo('_op_gv')->( $cv, $op ) ) // 'U', key => _signed_byte( $op->private ), kind => 'array' } ] };
    }
    if ( $n eq 'aelemfast_lex' ) {
        my ($loc) = _lex( $cv, $op->targ );
        return { levels => [ { loc => $loc // 'U', key => _signed_byte( $op->private ), kind => 'array' } ] };
    }
    return undef unless $n eq 'aelem' || $n eq 'helem';
    my ( $c, $k ) = _kids($op);
    my $kind = $n eq 'aelem' ? 'array' : 'hash';
    my ( $loc, $holder_op ) = _container( $cv, $c );
    my $level = { loc => $loc // 'U', key => _const_key( $cv, $k ), kind => $kind };
    return { levels => [$level] } unless $holder_op;
    my $h = _strip($holder_op);
    if ( $h->name eq 'padsv' ) {
        my ($hl) = _lex( $cv, $h->targ );
        return { levels => [$level], holder => $hl };
    }
    if ( $h->name eq 'gvsv' || ( $h->name eq 'rv2sv' && _strip( $h->first )->name eq 'gv' ) ) {
        my ($e) = _target_effects( $cv, $h );
        return { levels => [$level], holder => $e ? $e->{loc} : 'U' };
    }
    if ( $h->name =~ /\A(?:aelem|helem|multideref|aelemfast|aelemfast_lex)\z/ ) {
        my $inner = _place( $cv, $h ) or return { levels => [$level], holder => 'U' };
        return { levels => [ $inner->{levels}->@*, $level ], holder => $inner->{holder} };
    }
    return { levels => [$level] };
}

sub _kind_of_loc ($loc) {
    return $1 if $loc =~ /\AR:(\w+)\z/;
    return { '$' => 'scalar', '@' => 'array', '%' => 'hash' }->{$1} if $loc =~ /\A[NLF]:([\$\@%])/;
    return '?';
}

sub _keys_meet ( $a, $b, $kind ) {
    return 1 if $a eq '*' || $b eq '*';
    if ( $kind eq 'array' ) {
        return 1 unless $a =~ /\A\d+\z/ && $b =~ /\A\d+\z/;   # (a negative index counts from the end)
        return $a == $b ? 1 : 0;
    }
    return $a eq $b ? 1 : 0;
}

# _may_be($e_loc, $c_loc, $kind) -> may an effect's location be this container?
sub _may_be ( $e, $c, $kind, $refd = 1 ) {
    return 1 if $e eq $c;
    return 1 if $c eq 'U' || $e eq 'U';
    my ( $ek, $ck ) = ( _kind_of_loc($e), _kind_of_loc($c) );
    return 0 if $ek ne '?' && $ck ne '?' && $ek ne $ck;
    # A REFERENCE may name a container of its kind that a reference can reach:
    # one through a reference, a package or field one, a captured lexical.
    return $refd if $e =~ /\AR:/ && $c =~ /\A[RNFL]:/;
    return 1 if $c =~ /\AR:/ && $e =~ /\A[NFL]:/;
    return 0;
}

# conflict($place, \@effects) -> undef, or the worst of: 'store' (an element
# of the container may be stored), 'reshape' (the container may be reshaped,
# or what holds it replaced), 'unknown' (a call nothing can be said of).
sub conflict ( $place, $effects ) {
    my $worst = '';
    my %rank = ( '' => 0, store => 1, reshape => 2, unknown => 3 );
    my $note = sub ($w) { $worst = $w if $rank{$w} > $rank{$worst} };
    my @levels = $place->{levels}->@*;
    my $last   = $levels[-1];
    for my $e (@$effects) {
        if ( $e->{loc} eq 'U' ) { $note->('unknown'); next }
        # THE SCALAR HOLDING THE FIRST REFERENCE, replaced, frees the container.
        if ( defined $place->{holder} && ( $e->{loc} eq $place->{holder}
            || ( $e->{loc} eq 'R:scalar' && $place->{holder} !~ /\AL:/ ) || $place->{holder} eq 'U' ) ) {
            $note->('reshape');
            next;
        }
        # AN ELEMENT HOLDING A REFERENCE further in, stored or removed.
        for my $l ( @levels[ 0 .. $#levels - 1 ] ) {
            $note->('reshape')
                if _may_be( $e->{loc}, $l->{loc}, $l->{kind}, $l->{refd} )
                && ( $e->{reshape} || _keys_meet( $e->{key}, $l->{key}, $l->{kind} ) );
        }
        # A store through a scalar reference, or into an iterator aliasing
        # some element, may be into this one.
        if ( $e->{loc} eq 'R:scalar' || $e->{loc} eq 'N:$main::_' ) { $note->('store'); next }
        # The sub's own arguments are other variables' aliases.
        if ( $last->{loc} eq 'P' ) {
            $note->( $e->{reshape} ? 'reshape' : 'store' ) if $e->{loc} ne 'P' || _keys_meet( $e->{key}, $last->{key}, 'array' );
            next;
        }
        next unless _may_be( $e->{loc}, $last->{loc}, $last->{kind}, $last->{refd} );
        if ( $e->{reshape} ) { $note->('reshape'); next }
        $note->('store') if _keys_meet( $e->{key}, $last->{key}, $last->{kind} );
    }
    return $worst || undef;
}

1;
