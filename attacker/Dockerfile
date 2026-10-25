FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates iproute2 procps netcat-openbsd lsof chkrootkit \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 10001 labuser

COPY scripts/ /opt/lab/scripts/
RUN chmod +x /opt/lab/scripts/*.sh \
    && pip install --no-cache-dir PySocks

WORKDIR /opt/lab
USER labuser

# No ENTRYPOINT: compose run attacker /opt/lab/scripts/foo.sh executes foo directly.
CMD ["/bin/bash"]
