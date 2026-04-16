FROM ghcr.io/paperist/texlive-ja:debian

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    ssh \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
