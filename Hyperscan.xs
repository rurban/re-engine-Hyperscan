/* -*- c-basic-offset:4 -*- */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <hs/hs.h>
#include "Hyperscan.h"

#ifndef strEQc
# define strEQc(s, c) strEQ(s, ("" c ""))
#endif

#if PERL_VERSION > 10
#define RegSV(p) SvANY(p)
#else
#define RegSV(p) (p)
#endif

REGEXP *
#if PERL_VERSION < 12
HS_comp(pTHX_ const SV * const pattern, const U32 flags)
#else
HS_comp(pTHX_ SV * const pattern, U32 flags)
#endif
{
    REGEXP *rx;
    regexp *re;
    char   *ri = NULL;

    STRLEN  plen;
    char    *exp = SvPV((SV*)pattern, plen);
    char   *xend = exp + plen;
    U32 extflags = flags;
    SV  *wrapped, *wrapped_unset;

    /* hs_compile */
    unsigned int options = 0;
    hs_database_t *database;
    hs_compile_error_t *compile_err;
    hs_error_t rc;

    int nparens = 0;

    if (flags & RXf_PMf_EXTENDED
#ifdef RXf_PMf_EXTENDED_MORE
        || flags & RXf_PMf_EXTENDED_MORE
#endif
        )
    {
        return Perl_re_compile(pattern, flags);
    }

    wrapped = sv_2mortal(newSVpvn("(?", 2));
    wrapped_unset = sv_2mortal(newSVpvn("", 0));

    /* C<split " ">, bypass the Hyperscan engine alltogether and act as perl does */
    if (flags & RXf_SPLIT && plen == 1 && exp[0] == ' ')
        extflags |= (RXf_SKIPWHITE|RXf_WHITE);

    /* RXf_NULL - Have C<split //> split by characters */
    if (plen == 0)
        extflags |= RXf_NULL;

    /* RXf_START_ONLY - Have C<split /^/> split on newlines */
    else if (plen == 1 && exp[0] == '^')
        extflags |= RXf_START_ONLY;

    /* RXf_WHITE - Have C<split /\s+/> split on whitespace */
    else if (plen == 3 && strnEQ("\\s+", exp, 3))
        extflags |= RXf_WHITE;

    /* Perl modifiers to Hyperscan flags, /s is implicit and /p isn't used
     * but they pose no problem so ignore them */
    /* qr// stringification, TODO: (?flags:pattern) */
    if (flags & RXf_PMf_FOLD) {
        options |= HS_FLAG_CASELESS;  /* /i */
        sv_catpvn(wrapped, "i", 1);
    }
    if (flags & RXf_PMf_SINGLELINE) {
        options |= HS_FLAG_DOTALL;    /* /s */
        sv_catpvn(wrapped, "s", 1);
    }
    if (flags & RXf_PMf_MULTILINE) {
        options |= HS_FLAG_MULTILINE; /* /m */
        sv_catpvn(wrapped, "m", 1);
    }
#ifdef RXf_PMf_CHARSET
    if (flags & RXf_PMf_CHARSET) {
      regex_charset cs;
      if ((cs = get_regex_charset(flags)) != REGEX_DEPENDS_CHARSET) {
        switch (cs) {
        case REGEX_UNICODE_CHARSET:
          options |= (HS_FLAG_UTF8);
          sv_catpvn(wrapped, "u", 1);
          break;
        case REGEX_ASCII_RESTRICTED_CHARSET:
          options &= ~HS_FLAG_UCP; /* /a */
          sv_catpvn(wrapped, "a", 1);
          break;
        case REGEX_ASCII_MORE_RESTRICTED_CHARSET:
          options &= ~HS_FLAG_UTF8; /* /aa */
          sv_catpvn(wrapped, "aa", 2);
          break;
        default:
          Perl_ck_warner(aTHX_ packWARN(WARN_REGEXP),
                         "local charset option ignored by Hyperscan");
        }
      }
    }
#endif
    /* TODO: e r l d g c */

    /* The pattern is known to be UTF-8. Perl wouldn't turn this on unless it's
     * a valid UTF-8 sequence so tell Hyperscan not to check for that */
#ifdef RXf_UTF8
    if (flags & RXf_UTF8)
#else
    if (SvUTF8(pattern))
#endif
        options |= (HS_FLAG_UTF8);

    rc = hs_compile(
        exp,          /* pattern */
        options,      /* options */
        HS_MODE_BLOCK,
        NULL,
        &database,
        &compile_err
    );

    if (rc != HS_SUCCESS) {
        croak("Hyperscan compilation failed with %d: %s\n",
              compile_err->expression, compile_err->message);
        hs_free_compile_error(compile_err);
        sv_2mortal(wrapped);
        return NULL;
    }

#if PERL_VERSION >= 12
    rx = (REGEXP*) newSV_type(SVt_REGEXP);
#else
    Newxz(rx, 1, REGEXP);
    rx->refcnt = 1;
#endif

    re = RegSV(rx);
    re->intflags = options;
    re->extflags = extflags;
    re->engine   = &hs_engine;

    if (SvCUR(wrapped_unset)) {
        sv_catpvn(wrapped, "-", 1);
        sv_catsv(wrapped, wrapped_unset);
    }
    sv_catpvn(wrapped, ":", 1);
#if PERL_VERSION > 10
    re->pre_prefix = SvCUR(wrapped);
#endif
    sv_catpvn(wrapped, exp, plen);
    sv_catpvn(wrapped, ")", 1);

#if PERL_VERSION == 10
    re->wraplen = SvCUR(wrapped);
    re->wrapped = savepvn(SvPVX(wrapped), SvCUR(wrapped));
#else
    RX_WRAPPED(rx) = savepvn(SvPVX(wrapped), SvCUR(wrapped));
    RX_WRAPLEN(rx) = SvCUR(wrapped);
    DEBUG_r(sv_dump((SV*)rx));
#endif

#if PERL_VERSION == 10
    /* Preserve a copy of the original pattern */
    re->prelen = (I32)plen;
    re->precomp = SAVEPVN(exp, plen);
#endif

    /* Store our private object */
    re->pprivate = database;

    re->paren_names = NULL;
    re->nparens = re->lastparen = re->lastcloseparen = nparens;
    /*Newxz(re->offs, nparens + 1, regexp_paren_pair);*/

    return rx;
}

#if PERL_VERSION >= 18
REGEXP*  HS_op_comp(pTHX_ SV ** const patternp, int pat_count,
                       OP *expr, const struct regexp_engine* eng,
                       REGEXP *old_re,
                       bool *is_bare_re, U32 orig_rx_flags, U32 pm_flags)
{
    SV *pattern = NULL;

    PERL_UNUSED_ARG(pat_count);
    PERL_UNUSED_ARG(eng);
    PERL_UNUSED_ARG(old_re);
    PERL_UNUSED_ARG(is_bare_re);
    PERL_UNUSED_ARG(pm_flags);

    if (!patternp) {
        for (; !expr || OP_CLASS(expr) != OA_SVOP; expr = expr->op_next) ;
        if (expr && OP_CLASS(expr) == OA_SVOP)
            pattern = cSVOPx_sv(expr);
    } else {
        pattern = *patternp;
    }
    return HS_comp(aTHX_ pattern, orig_rx_flags);
}
#endif

static int eventHandler(unsigned int id, unsigned long long from,
                        unsigned long long to, unsigned int flags, void *ctx) {
    DEBUG_r(printf("Match for pattern \"%s\" at offset %llu\n", (char *)ctx, to));
    return 0;
}

I32
#if PERL_VERSION < 20
HS_exec(pTHX_ REGEXP * const rx, char *stringarg, char *strend,
          char *strbeg, I32 minend, SV * sv,
          void *data, U32 flags)
#else
HS_exec(pTHX_ REGEXP * const rx, char *stringarg, char *strend,
          char *strbeg, SSize_t minend, SV * sv,
          void *data, U32 flags)
#endif
{
    regexp * re = RegSV(rx);
    hs_database_t *ri = re->pprivate;
    int rc;
    I32 i;

    hs_scratch_t *scratch = NULL;
    if ((rc = hs_alloc_scratch(ri, &scratch)) != HS_SUCCESS) {
        croak("Hyperscan scratch memory error %d\n", rc);
        return 0;
    }
    rc = hs_scan(ri, stringarg,
                 strend - strbeg,      /* length */
                 stringarg - strbeg,   /* offset */
                 scratch, eventHandler, NULL);

    /* Matching failed */
    if (rc != HS_SUCCESS) {
        hs_free_scratch(scratch);
        croak("Hyperscan error %d\n", rc);
        return 0;
    }

    re->subbeg = strbeg;
    re->sublen = strend - strbeg;

#if 0
    rc = hs_get_ovector_count(match_data);
    ovector = hs_get_ovector_pointer(match_data);
    for (i = 0; i < rc; i++) {
        re->offs[i].start = ovector[i * 2];
        re->offs[i].end   = ovector[i * 2 + 1];
    }

    for (i = rc; i <= re->nparens; i++) {
        re->offs[i].start = -1;
        re->offs[i].end   = -1;
    }
#endif
    hs_free_scratch(scratch);
    return 1;
}

char *
#if PERL_VERSION < 20
HS_intuit(pTHX_ REGEXP * const rx, SV * sv,
             char *strpos, char *strend, const U32 flags, re_scream_pos_data *data)
#else
HS_intuit(pTHX_ REGEXP * const rx, SV * sv, const char *strbeg,
             char *strpos, char *strend, U32 flags, re_scream_pos_data *data)
#endif
{
	PERL_UNUSED_ARG(rx);
	PERL_UNUSED_ARG(sv);
#if PERL_VERSION >= 20
	PERL_UNUSED_ARG(strbeg);
#endif
	PERL_UNUSED_ARG(strpos);
	PERL_UNUSED_ARG(strend);
	PERL_UNUSED_ARG(flags);
	PERL_UNUSED_ARG(data);
    return NULL;
}

SV *
HS_checkstr(pTHX_ REGEXP * const rx)
{
    PERL_UNUSED_ARG(rx);
    return NULL;
}

void
HS_free(pTHX_ REGEXP * const rx)
{
    regexp * re = RegSV(rx);
    hs_free_database(re->pprivate);
}

void *
HS_dupe(pTHX_ REGEXP * const rx, CLONE_PARAMS *param)
{
    PERL_UNUSED_ARG(param);
    regexp * re = RegSV(rx);
    return re->pprivate;
}

SV *
HS_package(pTHX_ REGEXP * const rx)
{
    PERL_UNUSED_ARG(rx);
    return newSVpvs("re::engine::Hyperscan");
}

MODULE = re::engine::Hyperscan	PACKAGE = re::engine::Hyperscan
PROTOTYPES: ENABLE

void
ENGINE(...)
PROTOTYPE:
PPCODE:
    mXPUSHs(newSViv(PTR2IV(&hs_engine)));

