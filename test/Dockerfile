ARG BASE=test
FROM melopt/perl-alt:${BASE}

COPY cpanfile* /app/
RUN pdi-build-deps

COPY t/ /app/t/

ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]
