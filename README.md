# Slurm Cluster in Docker

This project sets up a complete [Slurm](https://slurm.schedmd.com/) cluster using Docker containers for local development, experimentation, and testing purposes.

This is tested on "Ubuntu 20.04.6".

## Components

The Slurm cluster consists of:

- 1 controller node (slurmctld)
- 4 compute nodes (slurmd)
- 1 SlurmDBD node (slurmdbd)
- 1 MariaDB node for accounting backend
- 1 REST API node (slurmrestd) to interact with the cluster via REST

The project structure looks like this:

    slurm-docker-cluster/
    ├── Dockerfile
    ├── entrypoint.sh
    ├── slurm.conf
    ├── slurmdbd.conf
    ├── munge.key
    ├── docker-compose.yml

## Authentication

`MUNGE` is a lightweight authentication service used by Slurm to securely verify users across nodes.

All nodes in the cluster need to share the same MUNGE key (usually at /etc/munge/munge.key).

It ensures that jobs submitted from one node are trusted and accepted by the controller.

Install the munge package on the host:

    sudo apt update
    sudo apt install munge

Generate a munge key:

    cd slurm-docker-cluster/
    sudo ./create-munge-key

Copy the key to the current project directory:

    sudo cp /etc/munge/munge.key ./munge.key

Set the correct ownership for munge.key:

    sudo chown 999:999 munge.key

## Build and Lunch

Set the correct ownership and permission for slurmdbd.conf:

    sudo chown 999:999 slurmdbd.conf
    sudo chmod 600 slurmdbd.conf

Build the Docker image:

    docker build --build-arg SLURM_VERSION=24.11.3 -t slurm-base .

Start all the containers:

    docker compose up -d

Open an interactive shell to the controller node:

    docker exec -it slurm-controller bash

Display the current state of nodes and partitions in the cluster:

    sinfo

    PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
    debug*       up   infinite      4   idle compute[1-4]

## Slurm REST

We are exposing slurmrestd on port 6820, so REST requests should go to:

    http://localhost:6820

We must generate a JWT token for REST API:

    docker exec -it slurmrestd bash
    /usr/bin/scontrol token username=root lifespan=31536000

Lifespan is in seconds and we set it to 1 year:

    365 days/year × 24 hours/day × 60 minutes/hour × 60 seconds/minute = 31,536,000 seconds

Then you can send a REST request from the host such as:

    curl http://localhost:6820/slurm/v0.0.40/nodes \
    -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzU3MDUwMDksImlhdCI6MTc0NDE2OTAwOSwic3VuIjoicm9vdCJ9.gI-Ij2ZIOYlm4mCoKZVYWExRKJc8G6sXJeiqxnXAkFk"
