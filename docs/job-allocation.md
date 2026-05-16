# Job Allocation

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

## salloc and srun

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

## Multi-Node Interactive Job

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

## sbcast

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

## Number of Tasks

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

## `--cpus-per-task` Option

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

## CPU Allocation

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

## Memory and GPU Options

Similar to CPUs, you can request for memory or GPU resource in your request.

| Option                          | Description                                                                              |
|---------------------------------|------------------------------------------------------------------------------------------|
| `--mem=<MB\|GB>`                | Request a total amount of memory per node for the job.                                   |
| `--mem-per-cpu=<MB\|GB>`        | Request memory per allocated CPU (useful when tasks scale with CPUs).                    |
| `--gres=gpu:<n>`                | Request `<n>` generic GPUs on the node.                                                  |
| `--gres=gpu:<type>:<n>`         | Request `<n>` GPUs of a specific type (e.g., `gpu:tesla:2` requests 2 Tesla GPUs).       |
| `--gres-flags=enforce-binding`  | Ensures GPUs and CPUs are allocated together, improving NUMA locality and performance.   |

## `--exclusive` Option

The `--exclusive` option ensures that the entire node (or set of nodes) allocated to a job is reserved solely for that job. This will prevent any other jobs from sharing those nodes. This is useful when you need full access to all of a node's resources (such as CPU cores, memory, or GPUs) or when you want to avoid resource contention. Even if your job only uses part of the node (e.g., a few CPU cores), Slurm will mark the entire node as unavailable to other jobs, guaranteeing isolation and consistent performance. This requested 2 nodes, exclusively:

    salloc --partition=debug --nodes=2 --ntasks=2 --time=01:00:00 --job-name=job1 --exclusive

    salloc: Granted job allocation 13
    salloc: Nodes compute[1-2] are ready for job

Slurm allocated compute[1-2] and marked them as fully reserved. No other job can share them, regardless of how much or how little resource your job actually uses. If you try to reserve resources from the same partition:

    salloc --partition=debug --nodes=2 --ntasks=2 --time=01:00:00 --job-name=job2

    salloc: Pending job allocation 14
    salloc: job 14 queued and waiting for resources

Slurm tries to find 2 available nodes, but it cannot, because compute[1-2] are already exclusively held by job1. So job2 is pending, queued until resources are free.

## `--no-shell` Option

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

## sbatch

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
