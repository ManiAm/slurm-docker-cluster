# Slurm and MPI

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

## Example: A Simple MPI "Hello World"

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


## How the MPI Code Works

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
