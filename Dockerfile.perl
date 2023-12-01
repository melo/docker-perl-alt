## The Perl Official version

ARG BASE=perl:5.38-slim

FROM ${BASE} AS runtime-base

## Path and sig of AWS Lambda runtime emulator
## Release 1.15 Nov 20, 2023
## see https://github.com/aws/aws-lambda-runtime-interface-emulator/releases
ENV AWS_LAMBDA_RIE_RELEASE=https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie
ENV AWS_LAMBDA_RIE_SHA256=a2bca0ff67c5435a02bf28a85524a8ff2ec222f403c19d92fe304f3f7c7cce10

## The main event...
RUN apt update                                                                       \
    && apt install -y --no-install-recommends                                        \
          curl wget make zlib1g libssl3 libexpat1 gnupg libxml2 libxml2-utils jq     \
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


## The setup...
ENV PATH=/app/bin:/deps/bin:/deps/local/bin:/stack/bin:/stack/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /app
ENTRYPOINT [ "/usr/bin/pdi-entrypoint" ]


## The Build version
FROM runtime-base AS build-base

RUN apt update                                                                  \
    && apt install -y --no-install-recommends                                   \
          build-essential zlib1g-dev libssl-dev libexpat1-dev libxml2-dev       \
    && apt upgrade -y                                                           \
    && apt purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/*                                 


## Our files
FROM scratch AS project

COPY bin/lambda-bootstrap /var/runtime/bootstrap
COPY layers/ cpanfile* /deps/layers/
COPY scripts/ /usr/bin/


## Final Versions: Development
FROM build-base AS devel
COPY --from=project / /

RUN pdi-build-deps --layer=devel  \
    && echo 'eval $( pdi-perl-env )' > /etc/profile.d/perl_env.sh


## Final Versions: Build
FROM build-base AS build
COPY --from=project / /


## Final Versions: Runtime
FROM runtime-base AS runtime
COPY --from=project / /


## Final Versions: Repl
FROM devel AS reply
RUN /usr/local/bin/cpm install --no-test Reply && rm -rf /root/.perl-cpm

CMD ["reply"]
