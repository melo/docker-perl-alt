## The Runtime version

ARG BASE=perl:5.38-slim

FROM ${BASE} AS runtime

## Path and sig of AWS Lambda runtime emulator
## Release 1.14 Jul 28, 2023
## see https://github.com/aws/aws-lambda-runtime-interface-emulator/releases
ENV AWS_LAMBDA_RIE_RELEASE=https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie
ENV AWS_LAMBDA_RIE_SHA256=e0a2ec2d026b0c3e1f381eb445aa282bb1a0ddd1a4c82411aec9719437a5391f

## The main event...
RUN apt update                                                                       \
    && apt install -y --no-install-recommends                                        \
          curl wget make zlib1g libssl3 libexpat1 gnupg libxml2 libxml2-utils jq   \
          build-essential                                                            \
    && apt upgrade -y                                                                \
    && cpm install -g Carton Path::Tiny autodie Module::CPANfile CPAN::Meta::Prereqs \
                   App::cpm Carton::Snapshot AWS::Lambda AWS::XRay                   \
    && rm -rf ~/.cpanm                                                               \
    && mkdir -p /app /deps /stack                                                    \
    && apt purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false      \
    && apt autoremove -y build-essential                                             \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/*

## AWS Lambda Emulator
RUN mkdir -p /usr/local/bin                                               \
    && cd /usr/local/bin                                                  \
    && curl -Lo ./aws-lambda-rie ${AWS_LAMBDA_RIE_RELEASE}                \
    && chmod +x ./aws-lambda-rie                                          \
    && echo "SHA256 (aws-lambda-rie) = ${AWS_LAMBDA_RIE_SHA256}" > ./.sig \
    && shasum -c .sig                                                     \
    && rm .sig

## All our scripts, layers, and default environment
COPY scripts/ /usr/bin/
RUN  chmod +x /usr/bin/pdi-*

COPY bin/lambda-bootstrap /var/runtime/bootstrap
RUN  chmod 555 /var/runtime/bootstrap

COPY layers/ cpanfile* /deps/layers/

ENV PATH=/app/bin:/deps/bin:/deps/local/bin:/stack/bin:/stack/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]

## The Build version
FROM runtime AS build

RUN apt-get update                                                                  \
    && apt-get install -y --no-install-recommends                                   \
          build-essential zlib1g-dev libssl-dev libexpat1-dev libxml2-dev           \
    && apt-get upgrade                                                              \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/*                                 


## The Devel version
FROM build AS devel

RUN pdi-build-deps --layer=devel  \
    && echo 'eval $( pdi-perl-env )' > /etc/profile.d/perl_env.sh


## The Repl version
FROM devel AS reply

RUN /usr/local/bin/cpm install --no-test Reply && rm -rf /root/.perl-cpm