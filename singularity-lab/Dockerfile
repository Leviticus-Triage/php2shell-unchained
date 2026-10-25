FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential kmod git curl ca-certificates flex bison libssl-dev \
    libelf-dev bc dwarves \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/singularity

CMD ["sleep", "infinity"]
