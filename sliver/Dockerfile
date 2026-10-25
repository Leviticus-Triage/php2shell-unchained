FROM golang:1.24-bookworm

# Sliver server compiles implants with this Go toolchain (needs module downloads -> lab_egress network).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl procps git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/sliver
# Binaries come from third_party/sliver (fetch-sliver.sh); build context is repo root via compose.
COPY third_party/sliver/sliver-server /opt/sliver/sliver-server
COPY third_party/sliver/sliver-client /opt/sliver/sliver-client
RUN chmod +x /opt/sliver/sliver-server /opt/sliver/sliver-client

ENV SLIVER_ROOT=/opt/sliver/data
ENV GOPROXY=https://proxy.golang.org,direct
RUN mkdir -p /opt/sliver/data /out

EXPOSE 31337 8888 8889
ENTRYPOINT ["/opt/sliver/sliver-server"]
CMD ["daemon"]
