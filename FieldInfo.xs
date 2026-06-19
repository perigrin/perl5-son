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
