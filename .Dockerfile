FROM ubuntu:yakkety

RUN apt-get update && apt-get -y install \
    curl g++ git cmake make \
    libhyperscan-dev libperl-dev cpanminus

RUN mkdir /build
WORKDIR /build
