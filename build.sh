#!/bin/sh

REPO=melopt/perl-alt
TAG=latest

docker build --target devel   -t ${REPO}:${TAG}-devel   .
docker build --target build   -t ${REPO}:${TAG}-build   .
docker build --target runtime -t ${REPO}:${TAG}-runtime .

if [ -n "$1" -a "x$1" == "xpush" ] ; then
	docker push ${REPO}:${TAG}-build
	docker push ${REPO}:${TAG}-devel
  docker push ${REPO}:${TAG}-runtime

  ## Tag latest as the devel image, the most used one
	docker tag  ${REPO}:${TAG}-devel ${REPO}:${TAG}
	docker push ${REPO}:${TAG}
fi
