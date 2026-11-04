FROM debian:12
RUN apt-get update && apt-get install -y --no-install-recommends \
    nftables wireguard-tools iproute2 iputils-ping tcpdump \
    rsyslog ulogd2 curl procps && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]