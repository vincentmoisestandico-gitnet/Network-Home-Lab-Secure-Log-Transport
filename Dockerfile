FROM debian:12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping nftables wireguard-tools rsyslog ulogd2 \
    ulogd2-pcap tcpdump curl netcat-openbsd procps openssh-server \
    && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]