ARG BASE=perl-latest-devel
FROM melopt/perl-alt:${BASE}

RUN pdi-build-deps --layer=devel
COPY cpanfile* /app/
RUN pdi-build-deps

COPY t/ /app/t/
RUN mkdir -p /app/elib/x/lib
