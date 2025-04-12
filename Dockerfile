# Dockerfile

FROM ubuntu:22.04

LABEL maintainer="Mani Amoozadeh <mani.amoozadeh2@gmail.com>" \
      org.opencontainers.image.authors="Mani Amoozadeh <mani.amoozadeh2@gmail.com>" \
      org.opencontainers.image.title="My Slurm Cluster" \
      org.opencontainers.image.description="Slurm controller and compute node Docker image." \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for Slurm build
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    vim \
    nano \
    python3 \
    python3-pip \
    ca-certificates \
    munge \
    libmunge-dev \
    libssl-dev \
    libpam0g-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    mariadb-client \
    libdbus-1-dev \
    hwloc \
    libhwloc-dev \
    libnuma-dev \
    liblz4-dev \
    libjson-c-dev \
    libjwt-dev \
    libhttp-parser-dev \
    libyaml-dev \
    libevent-dev \
    libpmix-dev

# Add slurm group and user
RUN groupadd -r slurm && \
    useradd -r -g slurm -d /var/lib/slurm -s /bin/bash slurm

# Add a non-slurm group and user
RUN groupadd restgroup && \
    useradd -r -g restgroup -d /home/restuser -s /bin/bash restuser

ARG SLURM_VERSION=24.11.3
ENV SLURM_VERSION=${SLURM_VERSION}

RUN echo "Building Slurm version ${SLURM_VERSION}"

# Set working directory
WORKDIR /opt

# Download and extract Slurm source
RUN wget https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2 && \
    tar -xjf slurm-${SLURM_VERSION}.tar.bz2

# Build and install Slurm
RUN cd slurm-${SLURM_VERSION} && \
    ./configure --prefix=/usr --sysconfdir=/etc/slurm --with-munge --with-hwloc --with-json --with-http-parser --with-jwt --enable-slurmrestd --enable-multiple-slurmd --with-pmix && \
    make -j$(nproc) && \
    make install

# Create necessary directories
RUN mkdir -p /var/log/slurm /var/spool/slurmd /var/spool/slurmctld /var/run/slurm /etc/slurm \
    && chown -R slurm:slurm /var/log/slurm /var/spool/slurmd /var/spool/slurmctld /var/run/slurm /etc/slurm

# Ensure Munge has correct ownership and runtime dirs
RUN mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge && \
    chown -R slurm:slurm /etc/munge /var/log/munge /var/lib/munge /run/munge

# Create /etc/slurm/cgroup.conf with cgroup settings
RUN mkdir -p /etc/slurm && \
    echo "ConstrainCores=yes"        >> /etc/slurm/cgroup.conf && \
    echo "ConstrainRAMSpace=yes"     >> /etc/slurm/cgroup.conf && \
    echo "ConstrainDevices=no"       >> /etc/slurm/cgroup.conf

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set final working directory to root's home
WORKDIR /root

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
