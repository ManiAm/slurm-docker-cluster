
# Slurm Cluster on Docker

This project sets up a complete [Slurm](https://slurm.schedmd.com/) cluster using Docker containers for local development, experimentation, and testing purposes. For an overview of Slurm concepts, architecture, and commands, see the [Slurm Guide](./README_SLURM.md).

> This project is tested on "Ubuntu 20.04.6".

> You can find the Slurm Git repository in [here](https://github.com/SchedMD/slurm).

> All Slurm releases are [here](https://download.schedmd.com/slurm/).

## Project Structure

The project structure looks like this:

    slurm-docker-cluster/
    ├── Dockerfile
    ├── entrypoint.sh
    ├── slurm.conf
    ├── slurmdbd.conf
    ├── munge.key
    ├── docker-compose.yml

The Slurm cluster consists of:

- 1 controller node (`slurmctld`)
- 5 compute nodes (`slurmd`)
- 1 SlurmDBD node (`slurmdbd`)
- 1 MariaDB node for accounting backend
- 1 REST API node (`slurmrestd`) to interact with the cluster via REST

The `/shared` directory is a shared volume mounted across all nodes in the Slurm cluster. It is used to share configuration files, binaries, and other data that need to be accessible from multiple nodes.



## Deployment Notes and Design Considerations

### Static Networking and Hostname Resolution

In this setup, each container is assigned a static IP address to ensure stable and predictable communication between Slurm components. Slurm relies heavily on hostname-based communication. Internally, hostnames are resolved to IP addresses and used for all control-plane interactions between `slurmctld` (controller) and `slurmd` (compute nodes).

In dynamic container environments like Docker, IP addresses can change across restarts unless explicitly fixed. If hostnames resolve to different IPs over time or DNS resolution is inconsistent then Slurm daemons may fail to communicate, leading to node registration issues, job dispatch failures, or cluster instability. By using static IPs, we ensure consistent identity and connectivity across all nodes in the cluster.

### Configless Slurm

This deployment uses [configless Slurm](./README_SLURM.md#configless-slurm), where compute nodes do not require local copies of configuration files. Instead, the controller (`slurmctld`) serves as the central source of configuration, and compute nodes retrieve the required settings dynamically at startup.

This approach simplifies cluster management by eliminating the need to manually distribute and synchronize configuration files across nodes. It ensures consistency, reduces operational overhead, and makes it easier to scale or redeploy nodes. In containerized environments (where instances may be frequently recreated) configless mode is especially useful because new nodes can automatically bootstrap themselves without manual intervention.

### `slurmrestd` and Extended Linux Capabilities

The `slurmrestd` container is configured with additional Linux capabilities using Docker’s `cap_add` option. This is necessary because `slurmrestd` interacts closely with Slurm’s control and execution subsystems, exposing APIs that can query and manipulate jobs, resources, and system state.

Some of these operations involve access to low-level system features such as cgroups, process management, shared memory, and other kernel-controlled resources. In a containerized environment, these capabilities are restricted by default for security reasons. Granting the required capabilities allows `slurmrestd` to function correctly while still running inside a container. This is a common trade-off when containerizing system-level services that need deeper integration with the host.



## Getting Started

### Authentication

`MUNGE` is a lightweight authentication service used by Slurm to securely verify users across nodes. All nodes in the cluster need to share the same MUNGE key (usually at /etc/munge/munge.key). It ensures that jobs submitted from one node are trusted and accepted by the controller.

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

### Build and Launch

Set the correct ownership and permission for slurmdbd.conf:

    sudo chown 999:999 slurmdbd.conf
    sudo chmod 600 slurmdbd.conf

Build the Docker image:

    docker build --build-arg SLURM_VERSION=24.11.3 -t slurm-base .

Start all the containers:

    docker compose up -d

### Validate the Cluster

Open an interactive shell to the controller node:

    docker exec -it slurm-controller bash

Display the current state of nodes and partitions in the cluster:

    sinfo

    PARTITION AVAIL  TIMELIMIT  NODES  STATE  NODELIST
    debug*       up  1:00:00      2    idle   compute[1-2]
    batch        up  1-00:00:00   2    idle   compute[3-4]
    gpu          up  2-00:00:00   1    idle   compute5
    all          up  infinite     5    idle   compute[1-5]

Our slurm cluster is organized into four partitions. The asterisk (`*`) after `debug` indicates that it is the default partition. When a user submits a job without explicitly specifying a partition, Slurm will automatically place the job in the default partition, which in this case is `debug`. This helps streamline job submissions by not requiring users to always specify a partition unless needed. Note that you can run `sinfo` command on any compute nodes too.

When you run `sinfo` on a node (controller or compute), the following happens:

- It looks for the Slurm controller hostname/IP.
- It contacts the controller (usually over TCP port 6817, unless configured otherwise).
- It gets the cluster state and prints it.



## Job Allocation

Slurm has different utilities to allocate jobs.

| Command   | Purpose                                    | Interaction Type      | Typical Use Case                                     |
|-----------|--------------------------------------------|-----------------------|------------------------------------------------------|
| `salloc`  | Allocate resources for interactive use     | Interactive shell     | Debugging, testing, running commands manually        |
| `srun`    | Launch tasks or programs on compute nodes  | Interactive or Script | Parallel processing, running jobs within allocations |
| `sbatch`  | Submit batch job scripts for scheduling    | Non-interactive       | Automated, scheduled execution of job scripts        |
| `sbcast`  | Distribute files to nodes in a job         | Pre-job utility       | Copy large files or configs to all allocated nodes   |

Open an interactive shell to the head node:

    docker exec -it slurm-controller bash

Let us go over these commands.

### salloc and srun

`salloc` is a Slurm command used to request resources for an interactive job allocation. It doesn't immediately run a job but reserves compute resources (like nodes, CPUs, memory, and time) for your use. From the `debug` partition, request 1 physical node for an hour:

    salloc --partition=debug --nodes=1 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 3
    salloc: Nodes compute1 are ready for job

Slurm has successfully reserved the requested resources and assigned your job the unique job ID 3. The compute node `compute1` has been allocated and is now available for you to run tasks. However, this doesn't mean you've been moved into the compute node automatically. You are still on the head node and need to use `srun` to execute commands on `compute1` within this job allocation.

    srun hostname
    compute1

The command above runs the `hostname` command on the compute node `compute1`. This is commonly used to verify which node your job is running on, especially in multi-node or parallel environments. This is to ensure that your tasks are being executed on the intended compute nodes rather than the login node. You can start an interactive bash shell on the compute node:

    srun --pty bash

This will switch your shell to something like:

    root@compute1:~$

You can monitor your job with `squeue`:

    JOBID  PARTITION       NAME    USER  ST     TIME  NODES  NODELIST(REASON)
        3      debug    testing    root   R     0:19      1  compute1

It is a good practice to specify a name for the job allocation. The specified name will appear along with the job id number when querying running jobs on the system.

You can use any of these formats with the `--time` option:

| Format                         | Example     | Meaning                                 |
|--------------------------------|-------------|-----------------------------------------|
| `minutes`                      | `30`        | 30 minutes                              |
| `minutes:seconds`              | `30:10`     | 30 minutes, 10 seconds                  |
| `hours:minutes:seconds`        | `2:00:00`   | 2 hours                                 |
| `days-hours`                   | `1-2`       | 1 day and 2 hours                       |
| `days-hours:minutes`           | `1-2:30`    | 1 day, 2 hours, 30 minutes              |
| `days-hours:minutes:seconds`   | `1-2:30:10` | 1 day, 2 hours, 30 minutes, 10 seconds  |

### Multi-Node Interactive Job

When you run:

    salloc --partition=debug --nodes=2 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 15
    salloc: Nodes compute[1-2] are ready for job

You're requesting a job allocation that includes:

- 2 compute nodes
- A runtime limit of 1 hour
- A custom job name: `testing`

Once granted, Slurm assigns nodes `compute1` and `compute2` to your job (JOBID=15). You're still on the controller node, but now you can use `srun` to launch tasks on the allocated nodes. When you run:

    srun hostname

    compute2
    compute1

Slurm launches the `hostname` command once per task (i.e., 2 times), automatically distributing them across the two nodes. Each task runs on a different node, showing that the workload was correctly distributed across your allocation. You can check your job status with `squeue`:

    JOBID  PARTITION     NAME     USER ST       TIME  NODES  NODELIST(REASON)
    15     debug      testing     root  R       0:29      2  compute[1-2]

### sbcast

`sbcast` is used to broadcast (copy) a file to all compute nodes allocated to your job. It's faster than using `scp` or `rsync` to send files individually, especially in large clusters. Let us go over an example.

Request an interactive allocation:

    salloc --partition=debug --nodes=2 --time=01:00:00
    salloc: Granted job allocation 1
    salloc: Nodes compute[1-2] are ready for job

Create a Python script (`hello.py`) on the controller.

    nano hello.py

With this content:

```python
#!/usr/bin/env python3

import socket
print(f"Hello from {socket.gethostname()}")
```

This script prints the hostname of the node it's running on - a nice way to verify it's distributed correctly.

Make it executable:

    chmod 755 hello.py

Distribute the script to all nodes using `sbcast`:

    sbcast hello.py /tmp/hello.py

This sends your local `hello.py` file to `/tmp/hello.py` on both compute nodes, so each task can access it locally. `sbcast` is faster and more efficient than using scp or a shared filesystem for small files in a distributed job. Run the script across all allocated nodes:

    srun /tmp/hello.py

    Hello from compute2
    Hello from compute1

### Number of Tasks

You can set the number of tasks using these options:

| Option                 | Description                             | Example                          | Result                                                              |
|------------------------|-----------------------------------------|----------------------------------|---------------------------------------------------------------------|
| `--ntasks=N`           | Total number of tasks across all nodes  | `--nodes=2 --ntasks=4`           | Slurm places 4 tasks across 2 nodes (e.g., 2 per node, if possible) |
| `--ntasks-per-node=N`  | Number of tasks **per node**            | `--nodes=2 --ntasks-per-node=2`  | Total 4 tasks (2 on each of 2 nodes)                                |

The `--ntasks` option specifies the total number of tasks (or processes) a job will run across the allocated resources. Without explicitly setting `--ntasks`, Slurm implicitly sets it equal to the number of nodes. This is often the expected behavior for multi-node allocations. Consider the following invocation, where `--ntasks` is not explicitly specified:

    salloc --partition=debug --nodes=2 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 32
    salloc: Nodes compute[1-2] are ready for job

Number of tasks is set to two (the number of nodes), and you can verify it by:

    scontrol show job 32

    <snip>
        NumNodes=2 NumCPUs=2 NumTasks=2 CPUs/Task=1 ReqB:S:C:T=0:0:*:*
    <snip>

Invoking srun will result in:

    srun hostname

    compute1
    compute2

Now let us ask Slurm to allocate 2 nodes and run 3 tasks across them:

    salloc --partition=debug --nodes=2 --ntasks=3 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 17
    salloc: Nodes compute[1-2] are ready for job

Once granted, Slurm gives you access to `compute1` and `compute2`.

When you run:

    srun hostname

    compute1
    compute2
    compute1

You're asking Slurm to launch 3 tasks, each executing the `hostname` command. Slurm distributes these tasks across the allocated nodes, often using a round-robin strategy by default. Since you only have 2 nodes but requested 3 tasks, one of the nodes will run two tasks, and the other will run one.

In Slurm, the number of tasks should generally be greater than or equal to the number of nodes. This is because each task represents a process that needs to run somewhere. If you request more nodes than tasks, some nodes may remain idle with no tasks assigned, leading to inefficient use of resources. Slurm may even override your request and reduce the number of nodes to match the number of tasks, as it assumes there's no need to allocate extra nodes with nothing to do.

    salloc --partition=debug --nodes=2 --ntasks=1 --time=01:00:00 --job-name=testing

    salloc: warning: can't run 1 processes on 2 nodes, setting nnodes to 1
    salloc: Granted job allocation 18
    salloc: Nodes compute1 are ready for job

### `--cpus-per-task` Option

Consider the following invocation:

    salloc --partition=debug --nodes=1 --ntasks=1 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 13
    salloc: Nodes compute1 are ready for job

We are requesting an interactive job allocation from partition `debug` on one node with a single task for one hour. However, it does not explicitly specify how many CPUs each task should receive, so Slurm assigns the default of 1 CPU per task. You can verify this by:

    scontrol show job 13

    <snip>
        NumNodes=1 NumCPUs=1 NumTasks=1 CPUs/Task=1 ReqB:S:C:T=0:0:*:*
    <snip>

Now consider this invocation where we request two tasks:

    salloc --partition=debug --nodes=1 --ntasks=2 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 14
    salloc: Nodes compute1 are ready for job

Slurm applies the default value of 1 CPU per task:

    scontrol show job 14

    <snip>
        NumNodes=1 NumCPUs=2 NumTasks=2 CPUs/Task=1 ReqB:S:C:T=0:0:*:*
    <snip>

This means Slurm has allocated:

- 1 node
- 2 tasks total
- 1 CPU per task, totaling 2 CPUs (2 tasks × 1 CPU each)
- All tasks running on the same node (`compute1`)

The `--cpus-per-task=n` option specifies that each task in the job should be allocated `n` logical CPUs. This is particularly useful for multi-threaded applications where a single task can benefit from multiple logical CPUs.

    salloc --partition=debug --nodes=1 --ntasks=1 --cpus-per-task=2 --time=01:00:00 --job-name=testing

The maximum value for `--cpus-per-task` depends on how many logical CPUs are available on the node(s) where the job will run. The `debug` partition has two compute nodes: `compute1` and `compute2`. Each of those compute nodes has 4 logical CPUs:

    scontrol show node compute1 | grep CPUTot
        CPUAlloc=0 CPUEfctv=4 CPUTot=4 CPULoad=0.27

This means that you cannot request for more than 4 CPUs:

    salloc --partition=debug --nodes=1 --ntasks=1 --cpus-per-task=5 --time=01:00:00 --job-name=testing

    salloc: error: CPU count per node can not be satisfied
    salloc: error: Job submit/allocate failed: Requested node configuration is not available
    salloc: Job allocation 16 has been revoked.

### CPU Allocation

The CPU allocation summary in Slurm, typically shown in the format `A/I/O/T`, represents the state of CPU resources on a node.

| Field | Description                                                                |
|-------|----------------------------------------------------------------------------|
| A     | **Allocated** – Number of CPUs currently assigned to running jobs          |
| I     | **Idle** – Number of CPUs currently available for new tasks                |
| O     | **Other** – CPUs that are reserved, unavailable, or in an undefined state  |
| T     | **Total** – Total number of CPUs on the node                               |

The following command shows the node state as well as its CPU allocation:

    sinfo -n compute1 -o "%N %t %C"

    NODELIST  STATE  CPUS(A/I/O/T)
    compute1  idle   0/4/0/4

Recall that a node state represents the current status or availability of a compute node within the cluster. `idle` means that the node is available and ready to run jobs. Here's a breakdown of the CPU allocation summary 0/4/0/4:

- 0 (Allocated): No CPUs are currently assigned to any running jobs
- 4 (Idle): All 4 CPUs are available and ready to be allocated to new jobs
- 0 (Other): No CPUs are reserved or marked unavailable
- 4 (Total): The node has a total of 4 CPUs

Now let us send the following request:

    salloc --partition=debug --nodes=1 --ntasks=1 --cpus-per-task=2 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 18
    salloc: Nodes compute1 are ready for job

The node state of `compute1` is mix which means the node is partially allocated - some CPUs are used, others are free.

    sinfo -n compute1 -o "%N %t %C"

    NODELIST  STATE  CPUS(A/I/O/T)
    compute1  mix    2/2/0/4

Let us request one more allocation:

    salloc --partition=debug --nodes=1 --ntasks=1 --cpus-per-task=2 --time=01:00:00 --job-name=testing

    salloc: Granted job allocation 24
    salloc: Nodes compute1 are ready for job

The node state of `compute1` is alloc which means the node is fully allocated to one or more jobs.

    sinfo -n compute1 -o "%N %t %C"

    NODELIST  STATE  CPUS(A/I/O/T)
    compute1  alloc  4/0/0/4

### Memory and GPU Options

Similar to CPUs, you can request for memory or GPU resource in your request.

| Option                          | Description                                                                              |
|---------------------------------|------------------------------------------------------------------------------------------|
| `--mem=<MB\|GB>`                | Request a total amount of memory per node for the job.                                   |
| `--mem-per-cpu=<MB\|GB>`        | Request memory per allocated CPU (useful when tasks scale with CPUs).                    |
| `--gres=gpu:<n>`                | Request `<n>` generic GPUs on the node.                                                  |
| `--gres=gpu:<type>:<n>`         | Request `<n>` GPUs of a specific type (e.g., `gpu:tesla:2` requests 2 Tesla GPUs).       |
| `--gres-flags=enforce-binding`  | Ensures GPUs and CPUs are allocated together, improving NUMA locality and performance.   |

### `--exclusive` Option

The `--exclusive` option ensures that the entire node (or set of nodes) allocated to a job is reserved solely for that job. This will prevent any other jobs from sharing those nodes. This is useful when you need full access to all of a node's resources (such as CPU cores, memory, or GPUs) or when you want to avoid resource contention. Even if your job only uses part of the node (e.g., a few CPU cores), Slurm will mark the entire node as unavailable to other jobs, guaranteeing isolation and consistent performance. This requested 2 nodes, exclusively:

    salloc --partition=debug --nodes=2 --ntasks=2 --time=01:00:00 --job-name=job1 --exclusive

    salloc: Granted job allocation 13
    salloc: Nodes compute[1-2] are ready for job

Slurm allocated compute[1-2] and marked them as fully reserved. No other job can share them, regardless of how much or how little resource your job actually uses. If you try to reserve resources from the same partition:

    salloc --partition=debug --nodes=2 --ntasks=2 --time=01:00:00 --job-name=job2

    salloc: Pending job allocation 14
    salloc: job 14 queued and waiting for resources

Slurm tries to find 2 available nodes, but it cannot, because compute[1-2] are already exclusively held by job1. So job2 is pending, queued until resources are free.

### `--no-shell` Option

`salloc` automatically starts a subshell after allocating resources. This behavior ensures that any commands you run after the allocation are executed within the context of the allocated job environment.

    salloc --partition=debug --nodes=1 --time=01:00:00 --job-name=testing

    echo $SHLVL
    2

By starting a new shell, `salloc` gives you a clear boundary for the job's lifetime. If you exit that shell, the job allocation ends.

    exit

    salloc: Relinquishing job allocation 3
    salloc: Job allocation 9 has been revoked.

The `--no-shell` option tells Slurm not to automatically start a new shell after granting a job allocation:

    salloc --partition=debug --nodes=1 --time=01:00:00 --job-name=testing --no-shell

This is useful when you want to manage the environment yourself.

### sbatch

`sbatch` is a Slurm command used to submit batch jobs to the cluster for later execution. Instead of running interactively, the job script provided to `sbatch` runs in the background once scheduled. This allows users to define job parameters like partition, number of nodes, CPUs, memory, and runtime directly in the script or via command-line options. The scheduler determines the optimal time and resources for execution. The job output can be redirected to files for later review, making `sbatch` ideal for running long or unattended tasks in HPC environments.

Create a job script `hello_job.sh`:

    nano hello_job.sh

With this content:

```bash
#!/bin/bash
#SBATCH --job-name=hello_job
#SBATCH --output=hello_output.txt
#SBATCH --ntasks=1
#SBATCH --time=00:01:00
#SBATCH --partition=debug

echo "Hello from $(hostname)"
```

Job script is a shell script with `SBATCH` directives used to submit batch jobs.

Submit it with `sbatch`:

    sbatch hello_job.sh
    Submitted batch job 25

You can check the job data with:

    sacct -j 25 --format=JobID,JobName,State,ExitCode

    JobID           JobName      State ExitCode
    ------------ ---------- ---------- --------
    25            hello_job  COMPLETED      0:0
    25.batch          batch  COMPLETED      0:0

The output file is written by the node that executes the job. Open an interactive shell to `compute1`:

    docker exec -it bash compute1

And check the output file:

    ls -l /root

    -rw-r--r-- 1 root root 20 Apr 11 23:21 hello_output.txt


## Job Enforcement

By default, Slurm allocates resources like CPUs and memory based on job requests but does not strictly prevent a job from exceeding these limits. This means a job can potentially use more CPUs or memory than requested if the system allows it, which can impact other jobs on the same node.

To ensure strict enforcement, administrators must enable and configure Linux control groups (`cgroups`) via slurm.conf and cgroup.conf. This allows Slurm to constrain CPU usage through `cpusets` and enforce memory limits, terminating jobs that exceed their allocations.

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



## Restricting Direct SSH Access to Compute Nodes

By default, Slurm handles resource allocation and job scheduling, but it does not manage system-level network access. If a user has valid login credentials (such as an SSH key) for the compute nodes, they could potentially bypass Slurm entirely, SSH directly into an idle node (e.g., `compute3`), and run unauthorized workloads. This defeats the purpose of the scheduler and causes resource contention. To solve this, we must bridge the gap between the system's SSH service and Slurm. This is achieved using **PAM (Pluggable Authentication Modules)** and a specific Slurm module called `pam_slurm_adopt`.

### How `pam_slurm_adopt` Works

Linux relies on PAM to authorize logins. By configuring the compute nodes' PAM stack to include `pam_slurm_adopt.so`, we force the SSH daemon to check with Slurm before allowing a user to log in. The workflow looks like this:

1. A user attempts to SSH into a compute node.
2. The SSH service delegates authentication to PAM.
3. The `pam_slurm_adopt` module queries the local Slurm daemon (`slurmd`).
4. It asks: *"Does this user currently have an active, allocated job running on this exact node?"*
    * **If Yes:** The SSH connection is permitted.
    * **If No:** The SSH connection is immediately rejected ("Access denied").

### Cgroup Integration

`pam_slurm_adopt` provides an additional layer of resource enforcement. When it permits an SSH connection, it does not just let the user roam free on the node. Instead, it adopts the SSH session and places it directly into the Linux `cgroup` of the user's currently running job. If a user uses `salloc` to request 1 CPU and 2GB of RAM, and then SSHs into that allocated node to run commands manually, their entire SSH session is strictly bound by that 1 CPU and 2GB RAM limit. This ensures that interactive debugging or manual tasks cannot accidentally consume resources meant for other jobs on the same node.


## Slurm and MPI

MPI (Message Passing Interface) is a standardized and portable communication protocol used to program parallel applications that run across multiple nodes. It allows processes to communicate with one another by sending and receiving messages, making it ideal for HPC tasks. When Slurm allocates compute nodes for an MPI job, those individual tasks need a way to find each other and synchronize across the network as they boot up. You control exactly how Slurm handles this startup phase using the `MpiDefault` parameter in your `slurm.conf`. Here are the different values you can set for `MpiDefault` depending on your environment:

| Value         | Description                                                                   |
|---------------|-------------------------------------------------------------------------------|
| `none`        | No special support for MPI. Slurm will not handle MPI-specific startup tasks. |
| `openmpi`     | Legacy OpenMPI support (rarely needed with newer versions).                   |
| `pmi2`        | Use PMI2 interface (common with OpenMPI and MPICH).                           |
| `hydra`       | For Intel MPI or MPICH with Hydra process manager.                            |
| `cray_shasta` | Special plugin for Cray Shasta systems.                                       |
| `pmix`        | Use PMIx interface (more scalable and modern).                                |

Historically, Slurm used a specific plugin called `openmpi` to wire up these tasks. However, this legacy method was incredibly slow and struggled to scale as clusters grew larger. Today, modern HPC environments have completely abandoned that old method. Instead, they use the **Process Management Interface (PMI)** to handle synchronization. Slurm acts as a massive dispatcher, using PMI to securely and instantly hand out the network map to thousands of tasks simultaneously. The modern gold standard is **PMIx** (PMI Exascale), which is built for lightning-fast synchronization on massive clusters.

### Example: A Simple MPI "Hello World"

Let's walk through an example to demonstrate how MPI can be used within a Slurm-managed environment.

Open an interactive shell to the head node:

```bash
docker exec -it slurm-controller bash
```

From the `debug` partition, request two physical nodes for an hour:

```bash
salloc --partition=debug --nodes=2 --time=01:00:00 --job-name=mpi-testing

salloc: Granted job allocation 1
salloc: Nodes compute[1-2] are ready for job
```

Install OpenMPI packages on all reserved compute nodes:

```bash
srun bash -c 'apt-get update && apt install openmpi-bin openmpi-common libopenmpi-dev -y'
```

Open a shell on `compute1`:

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
#include <string.h>
#include <mpi.h>

int main(int argc, char** argv) {

    int rank, total;
    char message[100];

    // 1. Initialize the MPI environment
    MPI_Init(&argc, &argv);

    // 2. Get the total number of processes (size) and this process's ID (rank)
    MPI_Comm_size(MPI_COMM_WORLD, &total);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    // 3. Demonstrate actual network communication
    if (rank == 0) {
        // Rank 0 creates a message and sends it to Rank 1
        sprintf(message, "Hello from the head process (Rank 0)!");
        MPI_Send(message, strlen(message) + 1, MPI_CHAR, 1, 0, MPI_COMM_WORLD);
        printf("Rank 0: I sent a message to Rank 1.\n");
    }
    else if (rank == 1) {
        // Rank 1 waits to receive the message from Rank 0
        MPI_Recv(message, 100, MPI_CHAR, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("Rank 1: I received a message -> '%s'\n", message);
    }

    // 4. Everyone prints their standard status
    printf("Process Rank %d of %d is alive and well!\n", rank, total);

    // 5. Cleanly shut down the MPI environment
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

Instead of using `mpirun`, Slurm recommends using `srun` to launch MPI programs. It enables better job tracking, process binding, and scalability through direct integration with process management interfaces like PMI and PMIx.

Invoke the `hello_mpi` program:

```bash
srun /shared/hello_mpi
```

Sample output:

```text
Rank 0: I sent a message to Rank 1.
Process Rank 0 of 2 is alive and well!
Rank 1: I received a message -> 'Hello from the head process (Rank 0)!'
Process Rank 1 of 2 is alive and well!
```


### How the MPI Code Works

When you type `srun /shared/hello_mpi`, Slurm launches a completely independent copy of this program on `compute1` and another independent copy on `compute2`. Because they run on different physical machines, they do not share memory. They must communicate over the network. Here is exactly what happens step-by-step:

1. **Initialization (`MPI_Init`):** When this line runs, the program reaches out to the environment (via PMIx) to wire itself into the MPI network so it can find the other tasks.

2. **Finding Identity (`MPI_Comm_size` & `MPI_Comm_rank`):** The program asks the MPI environment two questions:
   * *"How many total processes are running this job?"* (The **size**, which is `2`).
   * *"What is my unique ID number?"* (The **rank**). The process on `compute1` is assigned Rank `0`, and the process on `compute2` is assigned Rank `1`.

3. **Network Communication (`MPI_Send` & `MPI_Recv`):**
   This is where the actual cross-node communication happens.
   * **Rank 0** (on `compute1`) prepares a text message. It then uses `MPI_Send` to push that message over the network, specifically targeting Rank 1.
   * **Rank 1** (on `compute2`) hits the `MPI_Recv` command and pauses. It waits listening to the network until it catches the incoming message from Rank 0. Once received, it prints the message to the screen.

4. **Shutdown (`MPI_Finalize`):** This politely shuts down the MPI environment and disconnects the process from the network, allowing the Slurm job to finish cleanly.


## Slurm REST

`Slurmrestd` is Slurm's RESTful API daemon that allows external applications, scripts, or web interfaces to interact with Slurm using HTTP/JSON instead of traditional CLI tools. It provides endpoints to submit jobs, query job and node status, manage accounts, and more. This makes it ideal for integration with portals, dashboards, or custom automation tools. Built for modern workflows, `slurmrestd` supports token-based authentication and can run alongside or separate from the main Slurm controller. In our slurm docker setup, `slurmrestd` is running inside `slurmrestd` container.

We are exposing `slurmrestd` on port 6820, so REST requests should go to:

    http://localhost:6820

We must generate a JWT token for REST API:

    docker exec -it slurmrestd bash
    /usr/bin/scontrol token username=root lifespan=31536000

Lifespan is in seconds and we set it to 1 year:

    365 days/year × 24 hours/day × 60 minutes/hour × 60 seconds/minute = 31,536,000 seconds

Then you can send a REST request from the host such as:

    curl http://localhost:6820/slurm/v0.0.40/nodes \
    -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzU3MDUwMDksImlhdCI6MTc0NDE2OTAwOSwic3VuIjoicm9vdCJ9.gI-Ij2ZIOYlm4mCoKZVYWExRKJc8G6sXJeiqxnXAkFk"

To get a list of all endpoints:

    curl http://localhost:6820/openapi/v3 \
    -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzU3MDUwMDksImlhdCI6MTc0NDE2OTAwOSwic3VuIjoicm9vdCJ9.gI-Ij2ZIOYlm4mCoKZVYWExRKJc8G6sXJeiqxnXAkFk"
