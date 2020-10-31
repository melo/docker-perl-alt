#!/bin/sh

docker build -t melopt/perl-alt:test --target runtime --file ../Dockerfile ..
docker build -t t .
docker run -it --rm t
