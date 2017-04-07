FROM ubuntu:yakkety

RUN apt-get update && apt-get -y install \
    git cmake make \
    libhyperscan-dev libperl-dev cpanminus

RUN mkdir /build
WORKDIR /build
