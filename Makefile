EXTENSION    = pgtap
EXTVERSION   = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")
NUMVERSION   = $(shell echo $(EXTVERSION) | sed -e 's/\([[:digit:]]*[.][[:digit:]]*\).*/\1/')
DATA         = $(filter-out $(wildcard sql/*--*.sql),$(wildcard sql/*.sql))
TESTS        = $(wildcard test/sql/*.sql)
EXTRA_CLEAN  = sql/pgtap.sql sql/uninstall_pgtap.sql sql/pgtap-core.sql sql/pgtap-schema.sql doc/*.html
DOCS         = doc/pgtap.mmd
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test --load-language=plpgsql
PG_CONFIG    = pg_config

ifdef NO_PGXS
top_builddir = ../..
PG_CONFIG := $(top_builddir)/src/bin/pg_config/pg_config
else
# Run pg_config to get the PGXS Makefiles
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
endif

# We need to do various things with the PostgreSQLl version.
VERSION = $(shell $(PG_CONFIG) --version | awk '{print $$2}')

# We support 8.0 and later.
ifeq ($(shell echo $(VERSION) | grep -qE " 7[.]" && echo yes || echo no),yes)
$(error pgTAP requires PostgreSQL 8.0 or later. This is $(VERSION))
endif

# Compile the C code only if we're on 8.3 or older.
ifeq ($(shell echo $(VERSION) | grep -qE " 8[.][0123]" && echo yes || echo no),yes)
MODULES = src/pgtap
endif

# We need Perl.
ifndef PERL
PERL := $(shell which perl)
endif

# Load PGXS now that we've set all the variables it might need.
ifdef NO_PGXS
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
else
include $(PGXS)
endif

# Is TAP::Parser::SourceHandler::pgTAP installed?
ifdef PERL
HAVE_HARNESS := $(shell $(PERL) -le 'eval { require TAP::Parser::SourceHandler::pgTAP }; print 1 unless $$@' )
endif

ifndef HAVE_HARNESS
    $(warning To use pg_prove, TAP::Parser::SourceHandler::pgTAP Perl module)
    $(warning must be installed from CPAN. To do so, simply run:)
    $(warning     cpan TAP::Parser::SourceHandler::pgTAP) 
endif

# Enum tests not supported by 8.2 and earlier.
ifeq ($(shell echo $(VERSION) | grep -qE " 8[.][012]" && echo yes || echo no),yes)
TESTS   := $(filter-out sql/enumtap.sql,$(TESTS))
REGRESS := $(filter-out enumtap,$(REGRESS))
endif

# Values tests not supported by 8.1 and earlier.
ifeq ($(shell echo $(VERSION) | grep -qE " 8[.][01]" && echo yes || echo no),yes)
TESTS   := $(filter-out sql/enumtap.sql sql/valueset.sql,$(TESTS))
REGRESS := $(filter-out enumtap valueset,$(REGRESS))
endif

# Throw, runtests, and roles aren't supported in 8.0.
ifeq ($(shell echo $(VERSION) | grep -qE " 8[.]0" && echo yes || echo no),yes)
TESTS   := $(filter-out sql/throwtap.sql sql/runtests.sql sql/roletap.sql,$(TESTS))
REGRESS := $(filter-out throwtap runtests roletap,$(REGRESS))
endif

# Determine the OS. Borrowed from Perl's Configure.
OSNAME := $(shell ./getos.sh)

# Make sure we build these.
all: sql/pgtap.sql sql/uninstall_pgtap.sql sql/pgtap-core.sql sql/pgtap-schema.sql

# Add extension build targets on 9.1 and up.
ifeq ($(shell $(PG_CONFIG) --version | grep -qE " 8[.]| 9[.]0" && echo no || echo yes),yes)
all: sql/$(EXTENSION)--$(EXTVERSION).sql

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

DATA = $(wildcard sql/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN += sql/$(EXTENSION)--$(EXTVERSION).sql
endif

sql/pgtap.sql: sql/pgtap.sql.in test/setup.sql
	cp $< $@
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][0123]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.3.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][012]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.2.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][01]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.1.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][0]" && echo yes || echo no),yes)
	patch -p0 < compat/install-8.0.patch
#	Hack for E'' syntax (<= PG8.0)
	mv sql/pgtap.sql sql/pgtap.tmp
	sed -e "s/ E'/ '/g" sql/pgtap.tmp > sql/pgtap.sql
	rm sql/pgtap.tmp
endif
	sed -e 's,MODULE_PATHNAME,$$libdir/pgtap,g' -e 's,__OS__,$(OSNAME),g' -e 's,__VERSION__,$(NUMVERSION),g' sql/pgtap.sql > sql/pgtap.tmp
	mv sql/pgtap.tmp sql/pgtap.sql

sql/uninstall_pgtap.sql: sql/uninstall_pgtap.sql.in test/setup.sql
	cp sql/uninstall_pgtap.sql.in sql/uninstall_pgtap.sql
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][0123]" && echo yes || echo no),yes)
	patch -p0 < compat/uninstall-8.3.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][012]" && echo yes || echo no),yes)
	patch -p0 < compat/uninstall-8.2.patch
endif
ifeq ($(shell echo $(VERSION) | grep -qE "8[.][0]" && echo yes || echo no),yes)
	patch -p0 < compat/uninstall-8.0.patch
endif

sql/pgtap-core.sql: sql/pgtap.sql.in
	cp $< $@
	sed -e 's,sql/pgtap,sql/pgtap-core,g' compat/install-8.3.patch | patch -p0
	sed -e 's,MODULE_PATHNAME,$$libdir/pgtap,g' -e 's,__OS__,$(OSNAME),g' -e 's,__VERSION__,$(NUMVERSION),g' sql/pgtap-core.sql > sql/pgtap-core.tmp
	$(PERL) compat/gencore 0 sql/pgtap-core.tmp > sql/pgtap-core.sql
	rm sql/pgtap-core.tmp

sql/pgtap-schema.sql: sql/pgtap.sql.in
	cp $< $@
	sed -e 's,sql/pgtap,sql/pgtap-schema,g' compat/install-8.3.patch | patch -p0
	sed -e 's,MODULE_PATHNAME,$$libdir/pgtap,g' -e 's,__OS__,$(OSNAME),g' -e 's,__VERSION__,$(NUMVERSION),g' sql/pgtap-schema.sql > sql/pgtap-schema.tmp
	$(PERL) compat/gencore 1 sql/pgtap-schema.tmp > sql/pgtap-schema.sql
	rm sql/pgtap-schema.tmp

# Make sure that we build the regression tests.
installcheck: test/setup.sql

# In addition to installcheck, one can also run the tests through pg_prove.
test: test/setup.sql
	pg_prove --pset tuples_only=1 $(TESTS)

html:
	MultiMarkdown.pl doc/pgtap.mmd > doc/pgtap.html
	./tocgen doc/pgtap.html 2> doc/toc.html
	perl -MPod::Simple::XHTML -E "my \$$p = Pod::Simple::XHTML->new; \$$p->html_header_tags('<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">'); \$$p->strip_verbatim_indent(sub { (my \$$i = \$$_[0]->[0]) =~ s/\\S.*//; \$$i }); \$$p->parse_from_file('`perldoc -l pg_prove`')" > doc/pg_prove.html

