## The Runtime version
FROM alpine:3.9 AS runtime

RUN apk --no-cache add curl wget perl make ca-certificates zlib libressl \
                       zlib expat gnupg libxml2 libxml2-utils jq         \
    && curl -L https://cpanmin.us | perl - App::cpanminus                \
    && cpanm -n -q Carton App::cpm                                       \
    && rm -rf ~/.cpanm                                                   \
    && mkdir -p /app /deps /stack

COPY scripts/ /usr/bin/
RUN  chmod +x /usr/bin/pdi-*

ENV PERL5LIB=/app/lib:/deps/local/lib/perl5:/stack/lib:/stack/local/lib/perl5
ENV PATH=/app/bin:/deps/bin:/deps/local/bin:/stack/bin:/stack/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app


## The Build version
FROM runtime AS build

RUN apk --no-cache add build-base zlib-dev perl-dev libressl-dev \
                       expat-dev libxml2-dev perl-test-harness-utils


## The Devel version
FROM build AS devel

ENV PERL5LIB=$PERL5LIB:/app/.docker-perl-local/lib/perl5
ENV PATH=$PATH:/app/.docker-perl-local/bin

ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]
