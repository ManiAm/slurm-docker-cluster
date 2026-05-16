# Restricting Direct SSH Access to Compute Nodes

By default, Slurm handles resource allocation and job scheduling, but it does not manage system-level network access. If a user has valid login credentials (such as an SSH key) for the compute nodes, they could potentially bypass Slurm entirely, SSH directly into an idle node (e.g., `compute3`), and run unauthorized workloads. This defeats the purpose of the scheduler and causes resource contention. To solve this, we must bridge the gap between the system's SSH service and Slurm. This is achieved using **PAM (Pluggable Authentication Modules)** and a specific Slurm module called `pam_slurm_adopt`.

## How `pam_slurm_adopt` Works

Linux relies on PAM to authorize logins. By configuring the compute nodes' PAM stack to include `pam_slurm_adopt.so`, we force the SSH daemon to check with Slurm before allowing a user to log in. The workflow looks like this:

1. A user attempts to SSH into a compute node.
2. The SSH service delegates authentication to PAM.
3. The `pam_slurm_adopt` module queries the local Slurm daemon (`slurmd`).
4. It asks: *"Does this user currently have an active, allocated job running on this exact node?"*
    * **If Yes:** The SSH connection is permitted.
    * **If No:** The SSH connection is immediately rejected ("Access denied").

## Cgroup Integration

`pam_slurm_adopt` provides an additional layer of resource enforcement. When it permits an SSH connection, it does not just let the user roam free on the node. Instead, it adopts the SSH session and places it directly into the Linux `cgroup` of the user's currently running job. If a user uses `salloc` to request 1 CPU and 2GB of RAM, and then SSHs into that allocated node to run commands manually, their entire SSH session is strictly bound by that 1 CPU and 2GB RAM limit. This ensures that interactive debugging or manual tasks cannot accidentally consume resources meant for other jobs on the same node.
