## The Runtime version

## 3.9 is the latest "safest" version
ARG BASE=3.9

FROM alpine:${BASE} AS runtime

RUN apk --no-cache add curl wget perl make ca-certificates zlib openssl  \
                       zlib expat gnupg libxml2 libxml2-utils jq tzdata  \
    && curl -L https://cpanmin.us | perl - App::cpanminus                \
    && cpanm -n -q Carton App::cpm Path::Tiny                            \
                   autodie Module::CPANfile CPAN::Meta::Prereqs          \
    && rm -rf ~/.cpanm                                                   \
    && mkdir -p /app /deps /stack

COPY scripts/ /usr/bin/
RUN  chmod +x /usr/bin/pdi-*

COPY cpanfile* /deps/layers/devel/

ENV PERL5LIB=/app/lib:/deps/local/lib/perl5:/stack/lib:/stack/local/lib/perl5
ENV PATH=/app/bin:/deps/bin:/deps/local/bin:/stack/bin:/stack/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]

## The Build version
FROM runtime AS build

RUN apk --no-cache add build-base zlib-dev perl-dev openssl-dev \
                       expat-dev libxml2-dev perl-test-harness-utils


## The Devel version
FROM build AS devel

RUN pdi-build-deps --layer=devel  \
    && echo 'eval $( pdi-perl-env )' > /etc/profile.d/perl_env.sh


## The Repl version
FROM devel AS repl

RUN /usr/local/bin/cpm install --no-test Reply && rm -rf /root/.perl-cpm