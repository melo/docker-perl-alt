ARG BASE=next-devel
FROM melopt/perl-alt:${BASE}

COPY cpanfile* /app/
RUN pdi-build-deps

COPY t/ /app/t/
RUN mkdir -p /app/elib/x/lib

ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]
