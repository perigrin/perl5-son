/* ABOUTME: Thin XS exposing PadnameFIELDINFO for feature class field metadata. */
/* ABOUTME: Provides is_field() and field_info() that B:: does not expose. */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* Peephole-optimizer suppression. B::SoN reads the optree, and the peephole
 * pass fuses element access (aelemfast / multideref), list-intro (padrange),
 * and similar into opaque ops that obscure the canonical structure. Replacing
 * PL_rpeepp with a no-op while the target program compiles keeps the optree in
 * its canonical, unfused form. rpeep is an optimization, not a correctness
 * pass, so the optree still executes; we only walk it. */
static peep_t son_orig_rpeepp = NULL;

static void
son_noop_rpeep(pTHX_ OP *o)
{
    PERL_UNUSED_ARG(o);
}

/* Extract PADNAME* from a B::PADNAME object (an RV to an IV holding the ptr) */
static PADNAME *
extract_padname(pTHX_ SV *sv)
{
    if (!SvROK(sv))
        croak("Not a reference");
    return INT2PTR(PADNAME *, SvIV(SvRV(sv)));
}

MODULE = SoN  PACKAGE = SoN::FieldInfo

PROTOTYPES: DISABLE

bool
is_field(sv)
    SV *sv
    CODE:
        PADNAME *pn = extract_padname(aTHX_ sv);
        if (!pn)
            XSRETURN_NO;
        RETVAL = PadnameIsFIELD(pn) ? TRUE : FALSE;
    OUTPUT:
        RETVAL

void
field_info(sv)
    SV *sv
    PPCODE:
        PADNAME *pn = extract_padname(aTHX_ sv);
        if (!pn || !PadnameIsFIELD(pn))
            XSRETURN_EMPTY;
        struct padname_fieldinfo *info = PadnameFIELDINFO(pn);
        if (!info)
            XSRETURN_EMPTY;
        EXTEND(SP, 4);
        mPUSHu(info->fieldix);
        if (info->fieldstash && HvNAME(info->fieldstash))
            mPUSHp(HvNAME(info->fieldstash), HvNAMELEN(info->fieldstash));
        else
            PUSHs(&PL_sv_undef);
        if (info->paramname)
            mPUSHs(newSVsv(info->paramname));
        else
            PUSHs(&PL_sv_undef);
        mPUSHi(info->def_if_undef | (info->def_if_false << 1));

MODULE = SoN  PACKAGE = SoN::ClassAux

PROTOTYPES: DISABLE

# A feature-class stores its field initializers and ADJUST blocks as separate
# CVs on the class HvAUX struct (CORE/hv.h xpvhv_aux), not in the built-in `new`
# XSUB. These accessors expose them, plus the :isa superclass, so B::SoN can
# extract the full class structure from the compiled program.

bool
is_class(stashref)
    SV *stashref
    CODE:
        if (!SvROK(stashref) || SvTYPE(SvRV(stashref)) != SVt_PVHV)
            XSRETURN_NO;
        HV *stash = (HV *)SvRV(stashref);
        RETVAL = HvSTASH_IS_CLASS(stash) ? TRUE : FALSE;
    OUTPUT:
        RETVAL

SV *
initfields_cv(stashref)
    SV *stashref
    CODE:
        if (!SvROK(stashref) || SvTYPE(SvRV(stashref)) != SVt_PVHV)
            XSRETURN_UNDEF;
        HV *stash = (HV *)SvRV(stashref);
        if (!HvSTASH_IS_CLASS(stash))
            XSRETURN_UNDEF;
        CV *cv = HvAUX(stash)->xhv_class_initfields_cv;
        if (!cv)
            XSRETURN_UNDEF;
        RETVAL = newRV_inc((SV *)cv);
    OUTPUT:
        RETVAL

void
adjust_cvs(stashref)
    SV *stashref
    PPCODE:
        if (!SvROK(stashref) || SvTYPE(SvRV(stashref)) != SVt_PVHV)
            XSRETURN_EMPTY;
        HV *stash = (HV *)SvRV(stashref);
        if (!HvSTASH_IS_CLASS(stash))
            XSRETURN_EMPTY;
        AV *blocks = HvAUX(stash)->xhv_class_adjust_blocks;
        if (!blocks)
            XSRETURN_EMPTY;
        SSize_t n = av_count(blocks);
        EXTEND(SP, n);
        for (SSize_t i = 0; i < n; i++) {
            SV **el = av_fetch(blocks, i, 0);
            if (el && *el)
                mPUSHs(newRV_inc(*el));
        }

SV *
superclass_name(stashref)
    SV *stashref
    CODE:
        if (!SvROK(stashref) || SvTYPE(SvRV(stashref)) != SVt_PVHV)
            XSRETURN_UNDEF;
        HV *stash = (HV *)SvRV(stashref);
        if (!HvSTASH_IS_CLASS(stash))
            XSRETURN_UNDEF;
        HV *super = HvAUX(stash)->xhv_class_superclass;
        if (!super || !HvNAME(super))
            XSRETURN_UNDEF;
        RETVAL = newSVpv(HvNAME(super), HvNAMELEN(super));
    OUTPUT:
        RETVAL

# The class's OWN field padnames, from HvAUX(stash)->xhv_class_fields (a
# PADNAMELIST of PadnameIsFIELD padnames). Returns a flat (name, fieldix) list in
# declaration order -- the authoritative source of a field's variable name,
# independent of whether any method/ADJUST body references the field. Inherited
# fields are NOT included (each class's list holds only its own fields), and
# fieldix stays continuous across the :isa chain.
void
class_field_names(stashref)
    SV *stashref
    PPCODE:
        if (!SvROK(stashref) || SvTYPE(SvRV(stashref)) != SVt_PVHV)
            XSRETURN_EMPTY;
        HV *stash = (HV *)SvRV(stashref);
        if (!HvSTASH_IS_CLASS(stash))
            XSRETURN_EMPTY;
        PADNAMELIST *fields = HvAUX(stash)->xhv_class_fields;
        if (!fields)
            XSRETURN_EMPTY;
        SSize_t max = PadnamelistMAX(fields);
        PADNAME **arr = PadnamelistARRAY(fields);
        for (SSize_t i = 0; i <= max; i++) {
            PADNAME *pn = arr[i];
            if (!pn || pn == &PL_padname_undef)
                continue;
            mPUSHp(PadnamePV(pn), PadnameLEN(pn));                /* "$left" */
            mPUSHu(PadnameFIELDINFO(pn)->fieldix);               /* 0, 1, ... */
        }

MODULE = SoN  PACKAGE = SoN::OptSuppress

PROTOTYPES: DISABLE

void
suppress_peep()
    CODE:
        if (!son_orig_rpeepp) {
            son_orig_rpeepp = PL_rpeepp;
            PL_rpeepp = son_noop_rpeep;
        }

void
restore_peep()
    CODE:
        if (son_orig_rpeepp) {
            PL_rpeepp = son_orig_rpeepp;
            son_orig_rpeepp = NULL;
        }
