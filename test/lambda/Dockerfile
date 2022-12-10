FROM melopt/perl-alt:perl-latest-build AS build

COPY cpanfile* /app
RUN  cd /app && pdi-build-deps

FROM melopt/perl-alt:perl-latest-runtime

COPY . /app

