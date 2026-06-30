# ================================================================
#  Dockerfile — image "valise" embarquant tous les outils requis
#  par le toolkit, pour ne rien installer sur le host cible.
#
#  Usage :
#    docker build -t vps-security-toolkit .
#    docker run --rm \
#      --pid=host --network=host \
#      -v /:/host:ro \
#      -v /var/run/docker.sock:/var/run/docker.sock:ro \
#      -v $(pwd)/out:/out \
#      -e NGINX_LOG_PATHS=/host/var/log/nginx/site1.access.log \
#      vps-security-toolkit --output /out/report.html
# ================================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    procps \
    iproute2 \
    net-tools \
    lsof \
    curl \
    wget \
    ca-certificates \
    gnupg \
    openssl \
    jq \
    file \
    sudo \
    cron \
    less \
    # --- sécurité / audit ---
    lynis \
    rkhunter \
    chkrootkit \
    debsums \
    aide \
    fail2ban \
    # --- docker cli (pour piloter le docker du host via socket) ---
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Trivy (scanner CVE) — installé via leur script officiel
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin

WORKDIR /toolkit
COPY . /toolkit

RUN chmod +x /toolkit/run.sh /toolkit/lib/*.sh /toolkit/collectors/*.sh

# Le rapport sera écrit dans /out par défaut — monter un volume dessus
RUN mkdir -p /out

ENTRYPOINT ["/toolkit/run.sh"]
CMD ["--output", "/out/vps-audit.html"]
