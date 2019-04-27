FROM alpine:3.9

RUN apk --no-cache add curl wget perl make ca-certificates zlib libressl \
                       zlib expat gnupg libxml2 libxml2-utils jq         \
    && curl -L https://cpanmin.us | perl - App::cpanminus                \
    && cpanm -n -q Carton App::cpm                                       \
    && rm -rf ~/.cpanm

ENV PERL5LIB=/app/lib:/app/local/lib/perl5:/deps/local/lib/perl5:/stack/local/lib/perl5
ENV PATH=/app/bin:/app/local/bin:/deps/local/bin:/stack/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
