## The Runtime version

ARG BASE=perl:5.36-slim

FROM ${BASE} AS runtime

RUN apt-get update                                                                   \
    && apt-get install -y --no-install-recommends                                    \
          curl wget make zlib1g libssl1.1 libexpat1 gnupg libxml2 libxml2-utils jq   \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false  \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/*                                  \
    && cpm install -g Carton Path::Tiny autodie Module::CPANfile CPAN::Meta::Prereqs \
                   App::cpm Carton::Snapshot                                         \
    && rm -rf ~/.cpanm                                                               \
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

RUN apt-get update                                                                  \
    && apt-get install -y --no-install-recommends                                   \
          build-essential zlib1g-dev libssl-dev libexpat1-dev libxml2-dev           \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/*                                 


## The Devel version
FROM build AS devel

RUN pdi-build-deps --layer=devel  \
    && echo 'eval $( pdi-perl-env )' > /etc/profile.d/perl_env.sh


## The Repl version
FROM devel AS repl

RUN /usr/local/bin/cpm install --no-test Reply && rm -rf /root/.perl-cpm