#!/bin/sh

docker build -t z .
clear

cmd="docker run -it -p 9000:8080 z"

echo "**** Should fail..."
echo
$cmd notfound.echo

echo
echo "**** Will start but fails later... Try:"
echo "curl -XPOST 'http://localhost:9000/2015-03-31/functions/function/invocations' -d '{}'"
echo
$cmd handler.notfound

echo
echo "**** To test:"
echo "curl -XPOST 'http://localhost:9000/2015-03-31/functions/function/invocations' -d '{}'"
echo
$cmd handler.echo
