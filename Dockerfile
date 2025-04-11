# Dockerfile

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for Slurm build
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    vim \
    nano \
    munge \
    libmunge-dev \
    libssl-dev \
    libpam0g-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    python3 \
    python3-pip \
    mariadb-client \
    libdbus-1-dev \
    wget \
    libhwloc-dev \
    libnuma-dev \
    liblz4-dev \
    libjson-c-dev \
    libjwt-dev \
    libhttp-parser-dev \
    libyaml-dev \
    ca-certificates

# Add slurm group
RUN groupadd -r slurm

# Add slurm user
RUN useradd -r -g slurm -d /var/lib/slurm -s /bin/bash slurm

# Set working directory
WORKDIR /opt

ARG SLURM_VERSION=24.11.3
ENV SLURM_VERSION=${SLURM_VERSION}

RUN echo "Building Slurm version ${SLURM_VERSION}"

# Download and build Slurm from source
RUN wget https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2 && \
    tar -xjf slurm-${SLURM_VERSION}.tar.bz2 && \
    cd slurm-${SLURM_VERSION} && \
    ./configure --prefix=/usr --sysconfdir=/etc/slurm --with-munge --with-hwloc --with-json --with-http-parser --with-jwt --enable-slurmrestd --enable-multiple-slurmd && \
    make -j$(nproc) && \
    make install

# Create necessary directories
RUN mkdir -p /var/log/slurm /var/spool/slurmd /var/spool/slurmctld /var/run/slurm /etc/slurm \
    && chown -R slurm:slurm /var/log/slurm /var/spool/slurmd /var/spool/slurmctld /var/run/slurm /etc/slurm

# Ensure Munge has correct ownership and runtime dirs
RUN mkdir -p /etc/munge /var/log/munge /var/lib/munge /run/munge && \
    chown -R slurm:slurm /etc/munge /var/log/munge /var/lib/munge /run/munge

# Add a non-slurm group and user
RUN groupadd restgroup && \
    useradd -r -g restgroup -d /home/restuser -s /bin/bash restuser

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
