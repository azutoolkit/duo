FROM python:3.8

# Install H2Load and H2Spec
RUN apt-get update
RUN apt-get install -y g++ make binutils autoconf automake autotools-dev libtool pkg-config \
zlib1g-dev libcunit1-dev libssl-dev libxml2-dev libev-dev libevent-dev libjansson-dev \
libc-ares-dev libjemalloc-dev cython python3-dev python-setuptools -qy

ADD https://github.com/summerwind/h2spec/releases/download/v2.6.0/h2spec_linux_amd64.tar.gz ./
RUN tar -xzf h2spec_linux_amd64.tar.gz && rm h2spec_linux_amd64.tar.gz
RUN ls 

ADD https://github.com/nghttp2/nghttp2/releases/download/v1.43.0/nghttp2-1.43.0.tar.gz ./
RUN tar -xzf nghttp2-1.43.0.tar.gz && rm nghttp2-1.43.0.tar.gz
WORKDIR /nghttp2-1.43.0
RUN autoreconf -i
RUN automake
RUN autoconf
RUN ./configure --enable-app
RUN make
WORKDIR /root

FROM crystallang/crystal:1.0.0
WORKDIR /
COPY --from=0 /nghttp2-1.43.0/src/h2load /bin/h2load
COPY --from=0 /h2spec /bin/h2spec
RUN h2spec --help