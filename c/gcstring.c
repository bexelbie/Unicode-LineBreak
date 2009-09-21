#include "linebreak.h"

extern void linebreak_charprop(linebreak_t *, unichar_t,
			       propval_t *, propval_t *, propval_t *,
			       propval_t *);

#define eaw2col(e) (((e) == EA_F || (e) == EA_W)? 2: (((e) == EA_Z)? 0: 1))

static
void _gcinfo(linebreak_t *obj, unistr_t *str, size_t pos,
	     size_t *glenptr, size_t *gcolptr, propval_t *glbcptr)
{
    propval_t glbc = PROP_UNKNOWN, ggbc, gscr;
    size_t glen, gcol;
    propval_t lbc, eaw, gbc, ngbc, scr;

    if (!str || !str->str || !str->len) {
	if (glbcptr) *glbcptr = PROP_UNKNOWN;
	if (glenptr) *glenptr = 0;
	if (gcolptr) *gcolptr = 0;
	return;
    }

    linebreak_charprop(obj, str->str[pos], &lbc, &eaw, &gbc, &scr);
    pos++;
    glen = 1;
    gcol = eaw2col(eaw);

    glbc = lbc;
    ggbc = gbc;
    gscr = scr;

    /* GB4, GB5  */
    /* NL (U+0085 NEXT LINE) is assigned to Grapheme_Cluster_Break Other. */
    if (lbc == LB_BK || lbc == LB_NL || gbc == GB_LF) {
	;
    /* GB3, GB4, GB5 */
    } else if (gbc == GB_CR) {
	if (pos < str->len) {
	    linebreak_charprop(obj, str->str[pos], NULL, NULL, &gbc, NULL);
	    if (gbc == GB_LF) {
		pos++;
		glen++;
	    }
	}
    }
    /* Special case */
    else if (lbc == LB_SP || lbc == LB_ZW || lbc == LB_WJ) {
	while (1) {
	    if (str->len <= pos)
		break;
	    linebreak_charprop(obj, str->str[pos], &lbc, &eaw, NULL, NULL);
 	    if (lbc != glbc)
		break;
	    pos++;
	    glen++;
	    gcol += eaw2col(eaw);
        }
    }
    else if (gbc != GB_Control) { /* GB4 */
	size_t pcol = 0, ecol = 0;
	while (pos < str->len) { /* GB2 */
	    linebreak_charprop(obj, str->str[pos], &lbc, &eaw, &ngbc, &scr);
	    /* GB5 */
	    if (ngbc == GB_Control || ngbc == GB_CR || ngbc == GB_LF)
		break;
	    /* GB6 - GB8 */
	    /*
	     * Assume hangul syllable block is always wide, while most of
	     * isolated junseong (V) and jongseong (T) are narrow.
	     */
	    else if ((gbc == GB_L &&
		      (ngbc == GB_L || ngbc == GB_V || ngbc == GB_LV ||
		       ngbc == GB_LVT)) ||
		     ((gbc == GB_LV || gbc == GB_V) &&
		      (ngbc == GB_V || ngbc == GB_T)) ||
		     ((gbc == GB_LVT || gbc == GB_T) && ngbc == GB_T))
		gcol = 2;
	    /* GB9, GB9a */
	    /*
	     * Some morbid sequences such as <L Extend V T> are allowed.
	     */
	    else if (ngbc == GB_Extend || ngbc == GB_SpacingMark) {
		ecol += eaw2col(eaw);
		pos++;
		glen++;
		continue;
	    }
	    /* GB9b */
	    else if (gbc == GB_Prepend) {
		glbc = lbc;
		ggbc = ngbc;
		gscr = scr;
		pcol += gcol;
		gcol = eaw2col(eaw);
	    }
	    /* GB10 */
	    else
		break;

	    pos++;
	    glen++;
	    gbc = ngbc;
	}
	gcol += pcol + ecol;
    }

    if (glbc == LB_SA) {
#ifdef USE_LIBTHAI
	if (gscr != SC_Thai)
#endif
	    glbc = (ggbc == GB_Extend || ggbc == GB_SpacingMark)? LB_CM: LB_AL;
    }
    if (glenptr) *glenptr = glen;
    if (gcolptr) *gcolptr = gcol;
    if (glbcptr) *glbcptr = glbc;
}

/*
 * Exports
 */

/*
 *
 */
gcstring_t *gcstring_new(unistr_t *unistr, linebreak_t *lbobj)
{
    gcstring_t *gcstr;
    size_t pos, len;
    size_t glen, gcol;
    propval_t glbc;
    gcchar_t gc = {0, 0, 0, PROP_UNKNOWN, 0};

    if ((gcstr = malloc(sizeof(gcstring_t))) == NULL)
	return NULL;
    memset(gcstr, 0, sizeof(gcstring_t));

    if (lbobj == NULL)
	gcstr->lbobj = linebreak_new();
    else
	gcstr->lbobj = linebreak_incref(lbobj);
    if (unistr == NULL || unistr->str == NULL || unistr->len == 0)
	return gcstr;
    gcstr->str = unistr->str;
    gcstr->len = len = unistr->len;

    for (pos = 0; pos < len; pos += glen) {
	if ((gcstr->gcstr =
	     realloc(gcstr->gcstr, sizeof(gcchar_t) * (pos + 1))) == NULL)
	    return NULL;
	_gcinfo(gcstr->lbobj, unistr, pos, &glen, &gcol, &glbc);
	gc.idx = pos;
	gc.len = glen;
	gc.col = gcol;
	gc.lbc = glbc;
	memcpy(gcstr->gcstr + gcstr->gclen, &gc, sizeof(gcchar_t));
	gcstr->gclen++;
    }

    return gcstr;
}

gcstring_t *gcstring_copy(gcstring_t *gcstr)
{
    gcstring_t *new;
    unichar_t *newstr = NULL;
    gcchar_t *newgcstr = NULL;

    if (gcstr == NULL)
	return (errno = EINVAL), NULL;

    if ((new = malloc(sizeof(gcstring_t))) == NULL)
	return NULL;
    memcpy(new, gcstr, sizeof(gcstring_t));

    if (gcstr->str && gcstr->len) {
	if ((newstr = malloc(sizeof(unichar_t) * gcstr->len)) == NULL) {
	    free(new);
	    return NULL;
	}
	memcpy(newstr, gcstr->str, sizeof(unichar_t) * gcstr->len);
    }
    new->str = newstr;
    if (gcstr->gcstr && gcstr->gclen) {
	if ((newgcstr = malloc(sizeof(gcchar_t) * gcstr->gclen)) == NULL) {
	    if (new->str) free(new->str);
	    free(new);
	    return NULL;
	}
	memcpy(newgcstr, gcstr->gcstr, sizeof(gcchar_t) * gcstr->gclen);
    }
    new->gcstr = newgcstr;
    if (gcstr->lbobj != NULL)
	new->lbobj = linebreak_incref(gcstr->lbobj);
    else
	new->lbobj = linebreak_new();
    new->pos = 0;

    return new;
}

void gcstring_destroy(gcstring_t *gcstr)
{
    if (gcstr == NULL)
	return;
    if (gcstr->str) free(gcstr->str);
    if (gcstr->gcstr) free(gcstr->gcstr);
    if (gcstr->lbobj) linebreak_destroy(gcstr->lbobj);
    free(gcstr);
}

gcstring_t *gcstring_append(gcstring_t *gcstr, gcstring_t *appe)
{
    unistr_t ustr = {0, 0};

    if (gcstr == NULL)
	return (errno = EINVAL), NULL;
    if (appe == NULL || appe->str == NULL || appe->len == 0)
	return gcstr;
    if (gcstr->gclen && appe->gclen) {
	size_t aidx, alen, blen, newlen, newgclen, i;
	unsigned char bflag;
	gcstring_t *cstr;

	aidx = gcstr->gcstr[gcstr->gclen - 1].idx;
	alen = gcstr->gcstr[gcstr->gclen - 1].len;
	blen = appe->gcstr[0].len;
	bflag = appe->gcstr[0].flag;

	if ((ustr.str = malloc(sizeof(unichar_t) * (alen + blen))) == NULL)
	    return NULL;
	memcpy(ustr.str, gcstr->str + aidx, sizeof(unichar_t) * alen);
	memcpy(ustr.str + alen, appe->str, sizeof(unichar_t) * blen);
	ustr.len = alen + blen;
	if ((cstr = gcstring_new(&ustr, gcstr->lbobj)) == NULL) {
	    free(ustr.str);
	    return NULL;
	}

	newlen = gcstr->len + appe->len;
	newgclen = gcstr->gclen - 1 + cstr->gclen + appe->gclen - 1;
	if ((gcstr->str = realloc(gcstr->str,
				  sizeof(unichar_t) * newlen)) == NULL) {
	    gcstring_destroy(cstr);
	    return NULL;
	}
	if ((gcstr->gcstr = realloc(gcstr->gcstr,
				    sizeof(gcchar_t) * newgclen)) == NULL) {
	    free(gcstr->str);
	    gcstring_destroy(cstr);
	    return NULL;
	}
	memcpy(gcstr->str + gcstr->len, appe->str,
	       sizeof(unichar_t) * appe->len);
	for (i = 0; i < cstr->gclen; i++) {
	    gcchar_t *gc = gcstr->gcstr + gcstr->gclen - 1 + i;

	    gc->idx = cstr->gcstr[i].idx + aidx;
	    gc->len = cstr->gcstr[i].len;
	    gc->col = cstr->gcstr[i].col;
	    gc->lbc = cstr->gcstr[i].lbc;
	    if (aidx + alen == gc->idx) /* Restore flag if possible */
		gc->flag = bflag;
	}
	for (i = 1; i < appe->gclen; i++) {
	    gcchar_t *gc =
		gcstr->gcstr + gcstr->gclen - 1 + cstr->gclen + i - 1;
	    gc->idx = appe->gcstr[i].idx - blen + aidx + cstr->len;
	    gc->len = appe->gcstr[i].len;
	    gc->col = appe->gcstr[i].col;
	    gc->lbc = appe->gcstr[i].lbc;
	    gc->flag = appe->gcstr[i].flag;
	}

	gcstr->len = newlen;
	gcstr->gclen = newgclen;
	gcstring_destroy(cstr);
    } else if (appe->gclen) {
	if ((gcstr->str = malloc(sizeof(unichar_t) * appe->len)) == NULL)
	    return NULL;
	if ((gcstr->gcstr = malloc(sizeof(gcchar_t) * appe->gclen)) == NULL) {
	    free(gcstr->str);
	    return NULL;
	}
	memcpy(gcstr->str, appe->str, sizeof(unichar_t) * appe->len);
	gcstr->len = appe->len;
	memcpy(gcstr->gcstr, appe->gcstr, sizeof(gcchar_t) * appe->gclen);
	gcstr->gclen = appe->gclen;

	gcstr->pos = 0;
    }

    return gcstr;
}

int gcstring_cmp(gcstring_t *a, gcstring_t *b)
{
    size_t i;

    if (!a->str || !b->str)
	return (a->str? 1: 0) - (b->str? 1: 0);
    for (i = 0; i < a->len && i < b->len; i++)
	if (a->str[i] != b->str[i])
	    return a->str[i] - b->str[i];
    return a->len - b->len;
}

size_t gcstring_columns(gcstring_t *gcstr)
{
    size_t col, i;

    if (gcstr == NULL)
	return 0;
    for (col = 0, i = 0; i < gcstr->gclen; i++)
	col += gcstr->gcstr[i].col;
    return col;
}

gcstring_t *gcstring_concat(gcstring_t *gcstr, gcstring_t *appe)
{
    gcstring_t *new;
    size_t pos;

    if (gcstr == NULL)
	return (errno = EINVAL), NULL;
    pos = gcstr->pos;
    if ((new = gcstring_copy(gcstr)) == NULL)
	return NULL;
    new->pos = pos;
    return gcstring_append(new, appe);
}

gcchar_t *gcstring_next(gcstring_t *gcstr)
{
    if (gcstr->gclen <= gcstr->pos)
	return NULL;
    return gcstr->gcstr + (gcstr->pos++);
}

void gcstring_setpos(gcstring_t *gcstr, int pos)
{
    if (pos < 0)
	pos += gcstr->gclen;
    if (pos < 0 || gcstr->gclen < pos)
	return;
    gcstr->pos = pos;
}

void gcstring_shrink(gcstring_t *gcstr, int length)
{
    if (length < 0)
	length += gcstr->gclen;

    if (length <= 0) {
	if (gcstr->str) free(gcstr->str);
	gcstr->str = NULL;
	gcstr->len = 0;
	if (gcstr->gcstr) free(gcstr->gcstr);
	gcstr->gcstr = NULL;
	gcstr->gclen = 0;
    } else if (gcstr->gclen <= length)
	return;
    else {
	gcstr->len = gcstr->gcstr[length].idx;
	gcstr->gclen = length;
    }
}

gcstring_t *gcstring_substr(gcstring_t *gcstr, int offset, int length,
			    gcstring_t *replacement)
{
    gcstring_t *new, *tail;
    size_t ulength, i;

    if (gcstr == NULL)
	return (errno = EINVAL), NULL;

    if (offset < 0)
	offset += gcstr->gclen;
    if (offset < 0) {
	length += offset;
	offset = 0;
    }
    if (length < 0)
	length += gcstr->gclen - offset;

    if (length < 0 || gcstr->gclen < offset) {
	if (replacement)
	    return (errno = EINVAL), NULL;
	else
	    return gcstring_new(NULL, gcstr->lbobj);
    }

    if (gcstr->gclen == offset) {
	length = 0;
	ulength = 0;
    } else if (gcstr->gclen <= offset + length) {
	length = gcstr->gclen - offset;
	ulength = gcstr->len - gcstr->gcstr[offset].idx;
    } else
	ulength = gcstr->gcstr[offset + length].idx -
	    gcstr->gcstr[offset].idx;

    if ((new = gcstring_new(NULL, gcstr->lbobj)) == NULL)
	return NULL; 

    if ((new->str = malloc(sizeof(unichar_t) * ulength)) == NULL) {
	gcstring_destroy(new);
	return NULL;
    }
    if ((new->gcstr = malloc(sizeof(gcchar_t) * length)) == NULL) {
	free(new->str);
	gcstring_destroy(new);
	return NULL;
    }
    memcpy(new->str, gcstr->str + gcstr->gcstr[offset].idx,
	   sizeof(unichar_t) * ulength);
    new->len = ulength;
    for (i = 0; i < length; i++) {
	memcpy(new->gcstr + i, gcstr->gcstr + offset + i, sizeof(gcchar_t));
	new->gcstr[i].idx -= gcstr->gcstr[offset].idx;
    }
    new->gclen = length;

    if (replacement) {
	if ((tail = gcstring_substr(gcstr, offset + length,
				    gcstr->gclen - (offset + length), NULL))
	    == NULL) {
	    gcstring_destroy(new);
	    return NULL;
	}
	gcstring_shrink(gcstr, offset);
	if (gcstring_append(gcstr, replacement) == NULL ||
	    gcstring_append(gcstr, tail) == NULL) {
	    gcstring_destroy(new);
	    gcstring_destroy(tail);
	    return NULL;
	}
	gcstring_destroy(tail);
    }

    return new;
}
