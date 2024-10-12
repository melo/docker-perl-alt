# Perl Docker Image System #

![Docker Pulls](https://img.shields.io/docker/pulls/melopt/perl-alt.svg)
![Docker Build Status](https://img.shields.io/github/issues/melo/docker-perl-alt.svg)

This set of images provides a full and extensible setup to run your Perl
applications with Docker.

There are three main versions of the image:

* a `-runtime` version that should be used to run the final
  applications - the final target of your `Dockerfile` should
  use this one;
* a `-build` version that can be used to build your applications;
* a `-devel` version that can be used to debug and develop
  applications: this is mostly the `-build` version with extra modules.

Each of these is available in combination with an Alpine, the official Perl base image,
and the `wolfi-base` from the [Chainguard](https://www.chainguard.dev) project.

| Base Image  | Development | Build | Runtime |
|-------------|-------------|-------|---------|
| `alpine:3.20` | `alpine-latest-devel` / `alpine-3.20-devel` | `alpine-latest-build` / `alpine-3.20-build`| `alpine-latest-runtime` / `alpine-3.20-runtime` |
| `alpine:edge` | `alpine-next-devel` / `alpine-edge-devel` | `alpine-next-build` / `alpine-edge-build` | `alpine-next-runtime` / `alpine-edge-runtime` |
| `perl:5.40-slim` | `perl-latest-devel` / `perl-5.40-slim-devel` | `perl-latest-build` / `perl-5.40-slim-build` | `perl-latest-runtime` / `perl-5.40-slim-runtime` |
| `perl:5.40` | `perl-full-devel` / `perl-5.40-devel` | `perl-full-build` / `perl-5.40-build` | `perl-full-runtime` / `perl-5.40-runtime` |
| `cgr.dev/chainguard/wolfi-base` | `chainguard-latest-devel` | `chainguard-latest-build` | `chainguard-latest-runtime` |

See below how to create a Dockerfile for your project that makes
full use of this setup, while making sure that you'll end up with the
smallest possible final image.


## What's inside? ##

All images are based on Alpine and Perl images and include:

* [perl](https://metacpan.org/release/perl):
  * on Alpine images, we use the system `perl`:
    * 3.20: perl 5.38.2;
    * edge: perl 5.40.0.
  * on official Perl images, currently 5.40.0;
  * on Chainguard images, currently 5.40.0.
* [cpanm](https://metacpan.org/release/App-cpanminus);
* [Carton](https://metacpan.org/release/Carton);
* [App::cpm](https://metacpan.org/release/App-cpm).

Some common libs and tools are also included:

* `openssl`: this is not the default for Alpine, but a lot of software
  fails to build without it;
* `zlib`;
* `expat`;
* `libxml2` and `libxml-utils`;
* `jq`.

The `-build` and `-devel` versions include the development
versions of these libraries.


### Lambda Support (Experimental) ###

The Lambda support is still experimental. It seems to work fine but we
are not using it in production at this moment.

The support includes testing your functions locally using the
[AWS Lambda Runtime Interface Emulator][AWS-RIE].

Most of the Lambda logic is provided by the excellent [AWS::Lambda][]
Perl module. Kudos to Shogo Ichinose for this.

Your handlers should be placed in the `lambda-handlers/` of your
project. Make sure your `.pl` handlers are executable.

A sample handler (named `functions.pl`) looks like this:

```
#!perl

use strict;
use warnings;
use JSON::MaybeXS;

sub echo {
  my ($payload, $context) = @_;

  return encode_json({ payload => $payload, context => { %$context } });
}

1;
```

The name of this function is `functions.echo`. The first part,
`functions`, is the name of the handler file, `functions.pl`. The second
part, `echo`, is the name of the sub called in that file. See
[AWS::Lambda][] for details on writing Lambda handlers.

To test the function locally, build your image then run it like this:

```
$ docker run --rm -it -p 9000:8080 your_image your_handler.your_function
10 Dec 2022 16:31:26,839 [INFO] (rapid) exec '/var/runtime/bootstrap' (cwd=/app, handler=your_handler.your_function)
10 Dec 2022 16:31:36,015 [INFO] (rapid) extensionsDisabledByLayer(/opt/disable-extensions-jwigqn8j) -> stat /opt/disable-extensions-jwigqn8j: no such file or directory
10 Dec 2022 16:31:36,015 [WARNING] (rapid) Cannot list external agents error=open /opt/extensions: no such file or directory
```

You can then test with:
```
$ curl -XPOST 'http://localhost:9000/2015-03-31/functions/function/invocations' -d '{}'
```

The logs will show something like this:

```
START RequestId: 3503ccbd-0dfc-4eba-99f7-5aa72b58692b Version: $LATEST
END RequestId: 3503ccbd-0dfc-4eba-99f7-5aa72b58692b
REPORT RequestId: 3503ccbd-0dfc-4eba-99f7-5aa72b58692b	Init Duration: 0.36 ms	Duration: 63.70 ms	Billed Duration: 64 ms	Memory Size: 3008 MB	Max Memory Used: 3008 MB
```

For a fully working example see [test/lambda][lambda-test] inside this repository.


## Entrypoint ##

The system includes a standard ENTRYPOINT script that sets a decent
`PERL5LIB` based on the assumption that your app libs are under
`/app/lib`.

It will also check for submodules under `/app/elib/` and include
all `/app/elib/*/lib` folders in `PERL5LIB`.

Finally, if you need your own ENTRYPOINT script, place an executable
at `/entrypoint` and it will be executed before the `COMMAND`.


## Rational ##

The system was designed to have a big, fully featured, build-time image,
and another slim runtime image. A third version that you can use during
development time can also be created with a small addition to your
app `Dockerfile`.

With a Docker multi-stage build, you can use a single Dockerfile to
build and generate all the images, including the final runtime image.

The system assumes a specific directory layout for the app, the app
dependencies, and the "stack".

* application is inside `/app`;
* application dependencies will be installed at `/deps`;
* stack code and dependencies will be installed at `/stack`;

The fact that the stack code and dependencies are placed outside the app
locations allow you to create Docker images with just the stack
components that you can reuse between multiple projects. See below for
two sample stacks, one for a Dancer2+Xslate+Starman combo, and another
to have all the things needed to run a Minion job system.

The reason to split your app dependencies and your code is to
allow you to use an image with your work directory from your laptop
mounted under `/app`. If the app dependencies are in `/deps` and only
your code is under `/apps` you can start a container with an image
created from your app Dockerfile, and mount the laptop work directory
with `docker run` `-v`-option under `/app` and develop with the same
environment as your deployment environment will look like.


# How to use #

Below you'll find the recommended Dockerfile. The goal is to get a fast
build, making use as much as possible of the Docker build cache, and
provide the smallest possible image in the end.

This is an ordinary application. Dependencies are tracked with
[Carton](https://metacpan.org/pod/Carton) in a `cpanfile` with the
associate `cpanfile.snapshot`.

You should be able to just copy&paste this sample `Dockerfile` to your
app work directory, and tweak the `apk add` lines to make sure that
you add any packaged dependencies you might need. If you don't need
any package dependencies, you can just remove those lines altogether.

```Dockerfile
### First stage, just to add our package dependencies. We put this on a
### separate stage to be able to reuse them across the "build" and
### "devel" phases lower down
FROM melopt/perl-alt:alpine-latest-build AS package_deps

### Add any packaged dependencies that your application might need. Make
### sure you use the -devel or -libs package, as this is to be used to
### build your dependencies and app. The postgres-libs shown below is
### just an example
RUN apk --no-cache add postgres-libs


### Second stage, build our app. We start from the previous stage, package_deps
FROM package_deps AS builder

### We copy all cpanfiles (this includes the optional cpanfile.snapshot)
### to the application directory, and we install the dependencies. Note
### that by default pdi-build-deps will install our apps dependencies
### under /deps. This is important later on.
COPY cpanfile* /app/
RUN cd /app && pdi-build-deps

### Copy the rest of the application to the app folder
COPY . /app/


### The third stage is used to create a developers image, based on the
### package_deps and build phases, and with
### possible some extra tools that you might want during local
### development. This layer has no impact on the runtime final version,
### but can be generated with a `docker build --target devel`
FROM package_deps AS devel

### Add any packaged dependencies that your application might need
### during development time. Given that we start from package_deps
### phase, all package dependencies from the build phase are already
### included.
RUN apk --no-cache add jq

### Assuming you have a cpanfile.devel file with all your devel-time
### dependencies, you can install it with this
RUN cd /app && pdi-build-deps cpanfile.devel

### Copy the App dependencies and the app code
COPY --from=builder /deps/ /deps/
COPY --from=builder /app/ /app/

### And we are done: this "development" image can be generated with:
###
###      docker build -t my-app-devel --target devel .
###
### You can then run it as:
###
###      cd your-app-workdir; docker run -it --rm -v `pwd`:/app my-app-devel
###


### Now for the fourth and final stage, the runtime edition. We start from the
### runtime version and add all the files from the build phase
FROM melopt/perl-alt:alpine-latest-runtime

### Add any packaged dependencies that your application might need
RUN apk --no-cache add postgres-libs

### Copy the App dependencies and the app code
COPY --from=builder /deps/ /deps/
COPY --from=builder /app/ /app/

### Add the command to start the application
CMD [ "your_app_start_command.pl" ]
```

## Reuseable Stacks ##

You can also make stacks with commonly used combinations of packages.
The setup is almost the same, the only difference is that when
installing the dependencies and any other software you might need, the
destination directory is `/stack`. The `-runtime` image will
automatically include all of `/stack` dependencies and libs into
`PERL5LIB`, and it will also make sure that any commands that are placed
on `bin/` directories are included on our `PATH`.


### Dancer2 + Text::Xslate + Starman ###

Below you'll find an example of a Dockerfile for a stack that provides you:

* Dancer2;
* Text::Xslate for templating;
* Starman for a web server.

This is actually available at [melopt/dancer2-xslate-starman](https://hub.docker.com/r/melopt/dancer2-xslate-starman) (repository is at [Github melo/docker-dancer2-xslate-starman](https://www.github.com/melo/docker-dancer2-xslate-starman)). You can check the [`cpanfile` used for the stack](https://github.com/melo/docker-dancer2-xslate-starman/blob/master/cpanfile).

```Dockerfile
FROM melopt/perl-alt:alpine-latest-build AS builder

COPY cpanfile* /stack/
RUN cd /stack && pdi-build-deps --stack


FROM melopt/perl-alt:alpine-latest-runtime

COPY --from=builder /stack /stack/
```

Some notes about this `Dockerfile`:

* notice that the `pdi-build-deps` is run with the `--stack` option;
* for the runtime version, we copy the `/stack` folders.

With this setup, you'll end up with a Docker image for your stack that you can reuse with multiple projects. For example, a simple Dancer2+Xslate-based web app could have a `Dockerfile` like this:

```Dockerfile
### Package deps, for build and devel phases
FROM melopt/perl-alt:latest-build AS package_deps

RUN apk --no-cache add mariadb-dev

### Build phase, build our app and our app deps
FROM package_deps AS builder

COPY cpanfile* /app/
RUN cd /app && pdi-build-deps

COPY . /app/


### Create the "development" image
FROM package_deps AS devel

RUN apk --no-cache add jq
RUN cd /app && pdi-build-deps cpanfile.devel

COPY --from=builder /deps/ /deps/
COPY --from=builder /app/ /app/


### Final phase: the runtime version - notice that we start from the stack image
FROM melopt/dancer2-xslate-starman

ENV PLACK_ENV=production
RUN apk --no-cache add mariadb-client

COPY --from=builder /deps/ /deps/
COPY --from=builder /app/ /app/

CMD [ "plackup", "--port", "80", "--server", "Starman" ]
```

### Minion ###

Another stack, this time to allow users to run Minion workers and the admin interface. You can find the image at [melopt/minion](https://hub.docker.com/r/melopt/minion) (repository at [Github melo/docker-minion](https://github.com/melo/docker-minion)).

```Dockerfile
### Prepare the dependencies
FROM melopt/perl-alt:alpine-latest-build AS builder

RUN apk --no-cache add mariadb-dev postgresql-dev

COPY cpanfile* /stack/
RUN  cd /stack && pdi-build-deps --stack

### This stack includes some helper scripts
COPY bin /stack/bin/
### small "test phase", just to catch stupid mistakes...
RUN set -e && cd /stack && for script in bin/* ; do perl -wc $script ; done


### Runtime image
FROM melopt/perl-alt:alpine-latest-runtime

RUN apk --no-cache add mariadb-client postgresql-libs

COPY --from=builder /stack /stack

ENTRYPOINT [ "/stack/bin/minion-entrypoint" ]
```


# Repository #

This image source repository is at [https://github.com/melo/docker-perl-alt][repo].


# Author #

Pedro Melo [melo@simplicidade.org](mailto:melo@simplicidade.org)

[repo]: https://github.com/melo/docker-perl-alt
[AWS-RIE]: https://github.com/aws/aws-lambda-runtime-interface-emulator
[AWS::Lambda]: https://metacpan.org/pod/AWS::Lambda
[lambda-test]: https://github.com/melo/docker-perl-alt/tree/master/test/lambda
