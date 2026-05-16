
# Slurm Cluster on Docker

A fully containerized [Slurm](https://slurm.schedmd.com/) cluster for local development, experimentation, and testing. For an overview of Slurm concepts, architecture, and commands, see the [Slurm Guide](./docs/slurm-guide.md).

|               |                |
|---------------|----------------|
| **Tested on** | Ubuntu 20.04.6 |
| **Source**    | [github.com/SchedMD/slurm](https://github.com/SchedMD/slurm) |
| **Releases**  | [download.schedmd.com/slurm](https://download.schedmd.com/slurm/) |


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

This deployment uses [configless Slurm](./docs/slurm-guide.md#configless-slurm), where compute nodes do not require local copies of configuration files. Instead, the controller (`slurmctld`) serves as the central source of configuration, and compute nodes retrieve the required settings dynamically at startup.

This approach simplifies cluster management by eliminating the need to manually distribute and synchronize configuration files across nodes. It ensures consistency, reduces operational overhead, and makes it easier to scale or redeploy nodes. In containerized environments (where instances may be frequently recreated) configless mode is especially useful because new nodes can automatically bootstrap themselves without manual intervention.

### `slurmrestd` and Extended Linux Capabilities

The `slurmrestd` container is configured with additional Linux capabilities using Docker's `cap_add` option. This is necessary because `slurmrestd` interacts closely with Slurm's control and execution subsystems, exposing APIs that can query and manipulate jobs, resources, and system state.

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


## Documentation

| Topic                                        | Description |
|----------------------------------------------|-------------|
| [Job Allocation](./docs/job-allocation.md)   | Interactive and batch job submission (`salloc`, `srun`, `sbatch`, `sbcast`) |
| [Job Enforcement](./docs/job-enforcement.md) | Resource enforcement with cgroups |
| [SSH Access Control](./docs/ssh-access.md)   | Restricting direct SSH to compute nodes with `pam_slurm_adopt` |
| [MPI with Slurm](./docs/mpi.md)              | Running MPI programs on the cluster |
| [REST API](./docs/rest-api.md)               | Using `slurmrestd` for HTTP/JSON access |
