# Slurm Cluster in Docker

This project sets up a complete [Slurm](https://slurm.schedmd.com/) cluster using Docker containers for local development, experimentation, and testing purposes.

This is tested on "Ubuntu 20.04.6".

## Components

The Slurm cluster consists of:

- 1 controller node (slurmctld)
- 5 compute nodes (slurmd)
- 1 SlurmDBD node (slurmdbd)
- 1 MariaDB node for accounting backend
- 1 REST API node (slurmrestd) to interact with the cluster via REST

The `/shared` directory is a shared volume mounted across all nodes in the Slurm cluster.

It is used to share configuration files, binaries, and other data that need to be accessible from multiple nodes.

The project structure looks like this:

    slurm-docker-cluster/
    ├── Dockerfile
    ├── entrypoint.sh
    ├── slurm.conf
    ├── slurmdbd.conf
    ├── munge.key
    ├── docker-compose.yml

Set the correct ownership and permission for slurmdbd.conf:

    sudo chown 999:999 slurmdbd.conf
    sudo chmod 600 slurmdbd.conf

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

Build the Docker image:

    docker build --build-arg SLURM_VERSION=24.11.3 -t slurm-base .

Start all the containers:

    docker compose up -d

Open an interactive shell to the controller node:

    docker exec -it slurm-controller bash

Display the current state of nodes and partitions in the cluster:

    sinfo

    PARTITION AVAIL  TIMELIMIT  NODES  STATE  NODELIST
    debug*       up  1:00:00      2    idle   compute[1-2]
    batch        up  1-00:00:00   2    idle   compute[3-4]
    gpu          up  2-00:00:00   1    idle   compute5
    all          up  infinite     5    idle   compute[1-5]

## Interactive Job

Open an interactive shell to the controller node:

    docker exec -it slurm-controller bash

Request an interactive allocation:

```bash
salloc --partition=debug --nodes=2 --time=01:00:00

salloc: Granted job allocation 1
salloc: Nodes compute[1-2] are ready for job
```

Create a Python script (hello.py):

```bash
nano hello.py
```

```python
#!/usr/bin/env python3

import socket
print(f"Hello from {socket.gethostname()}")
```

This script prints the hostname of the node it's running on — a nice way to verify it's distributed correctly.

Make it executable:

```bash
chmod 755 hello.py
```

Distribute the script to all compute nodes using `sbcast`:

```bash
sbcast hello.py /tmp/hello.py
```

This sends your local `hello.py` file to `/tmp/hello.py` on both compute nodes, so each task can access it locally.

`sbcast` is much faster and more efficient than using scp or a shared filesystem for small files in a distributed job.

Run the script across all allocated nodes:

```bash
srun /tmp/hello.py

Hello from compute2
Hello from compute1
```

## Batch Job

Create a job script `hello_job.sh`:

```bash
nano hello_job.sh
```

```bash
#!/bin/bash
#SBATCH --job-name=hello_job
#SBATCH --output=hello_output.txt
#SBATCH --ntasks=1
#SBATCH --time=00:01:00
#SBATCH --partition=debug

echo "Hello from $(hostname)"
```

Job script is a shell script with SBATCH directives used to submit batch jobs.

Submit it with sbatch:

```bash
sbatch hello_job.sh

Submitted batch job 25
```

You can check your job status with:

```bash
sacct -j 25 --format=JobID,JobName,State,ExitCode

JobID           JobName      State ExitCode 
------------ ---------- ---------- -------- 
25            hello_job  COMPLETED      0:0 
25.batch          batch  COMPLETED      0:0
```

The output file is written by the node that executes the job.

Open an interactive shell to `compute1`:

```bash
docker exec -it bash compute1
```

And check the output file:

```bash
ls -l /root

-rw-r--r-- 1 root root 20 Apr 11 23:21 hello_output.txt
```

## Job Enforcement

By default, Slurm allocates resources like CPUs and memory based on job requests but does not strictly prevent a job from exceeding these limits.

This means a job can potentially use more CPUs or memory than requested if the system allows it, which can impact other jobs on the same node.

To ensure strict enforcement, administrators must enable and configure Linux control groups (`cgroups`) via slurm.conf and cgroup.conf.

This allows Slurm to constrain CPU usage through `cpusets` and enforce memory limits, terminating jobs that exceed their allocations.

To enable cgroups, we need to edit the `slurm.conf` and ensure the following line is present:

    TaskPlugin=task/cgroup

Create a file called `/etc/slurm/cgroup.conf` on all nodes (controller and compute), with content like this:

    ConstrainCores=yes
    ConstrainRAMSpace=yes
    ConstrainDevices=no

Let us go over an example on how cgroups works in practice on Slurm.

Open an interactive shell to compute1:

```bash
docker exec -it compute1 bash
```

Install `htop` and `stress` packages:

```bash
apt update && apt install htop stress -y
```

Invoke the stress test in the background that spawns 4 CPU workers:

```bash
stress --cpu 4 --timeout 30 &
```

Open `htop` to confirm four CPUs are busy:

```bash
htop
```

<img src="pics/slurm_stress_1.jpg" alt="segment" width="700">

Open an interactive shell to the controller:

```bash
docker exec -it slurm-controller bash
```

And invoke the same stress test, but through Slurm:

```bash
sbatch --cpus-per-task=1 --wrap="stress --cpu 4 --timeout 30"
```

Slurm, with cgroup enforcement enabled, does the following:

- Allocates only 1 CPU core to the job.
- Creates a cpuset cgroup that limits which CPU(s) the job can use.
- Even though stress spawns 4 processes, the kernel scheduler ensures that only 1 core is allowed for execution.

So in htop, you'll still see 4 process, but only one will be consuming CPU.

The others will be throttled/stalled due to the cgroup constraint.

<img src="pics/slurm_stress_2.jpg" alt="segment" width="700">

## Slurm and MPI

MPI (Message Passing Interface) is a standardized and portable communication protocol used to program parallel applications that run across multiple nodes.

It allows processes to communicate with one another by sending and receiving messages, making it ideal for high-performance computing (HPC) tasks.

Slurm integrates seamlessly with MPI to run distributed parallel applications across multiple nodes in a cluster.

Slurm handles resource allocation and job scheduling, while MPI handles inter-process communication.

`MpiDefault` parameter tells Slurm which MPI type to use by default when launching jobs with srun:

| Value       | Description                                                                   |
|-------------|-------------------------------------------------------------------------------|
| none        | No special support for MPI. Slurm will not handle MPI-specific startup tasks. |
| openmpi     | Legacy OpenMPI support (rarely needed with newer versions).                   |
| pmi2        | Use PMI2 interface (common with OpenMPI and MPICH).                           |
| hydra       | For Intel MPI or MPICH with Hydra process manager.                            |
| cray_shasta | Special plugin for Cray Shasta systems.                                       |
| pmix        | Use PMIx interface (more scalable and modern).                                |

OpenMPI is a popular open-source implementation of the MPI standard, providing tools and libraries that support a variety of platforms and interconnects.

It is widely used in research and industry for building scalable applications that require efficient communication among distributed processes.

Let's walk through an example to demonstrate how OpenMPI can be used within a Slurm-managed environment.

Open an interactive shell to the head node:

```bash
docker exec -it slurm-controller bash
```

From the `debug` partition, request two physical node for an hour:

```bash
salloc --partition=debug --nodes=2 --time=01:00:00 --job-name=mpi-testing

salloc: Granted job allocation 1
salloc: Nodes compute[1-2] are ready for job
```

Install OpenMPI packages on all reserved compute nodes:

```bash
srun bash -c 'apt-get update && apt install openmpi-bin openmpi-common libopenmpi-dev -y'
```

Open a shell on compute1:

```bash
srun --nodelist=compute1 --pty bash
```

Go to the shared folder that is accessible across all Slurm cluster:

```bash
cd /shared
```

Create `hello_mpi.c` file:

```bash
nano hello_mpi.c
```

With this content:

```C
#include <stdio.h>
#include <mpi.h>

int main(int argc, char** argv) {
    int node, total;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &node);
    MPI_Comm_size(MPI_COMM_WORLD, &total);
    printf("Hello World from Node %d of %d!\n", node, total);
    MPI_Finalize();
    return 0;
}
```

Compile the MPI program:

```bash
mpicc hello_mpi.c -o hello_mpi
```

This produces an executable called `hello_mpi`.

Return to the controller node:

```bash
exit
```

Instead of using `mpirun`, Slurm recommends using `srun` to launch MPI programs.

It enables better job tracking, process binding, and scalability through direct integration with process management interfaces like PMI and PMIx.

Invoke the `hello_mpi` program:

```bash
srun /shared/hello_mpi

Hello World from Node 1 of 2!
Hello World from Node 0 of 2!
```

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
