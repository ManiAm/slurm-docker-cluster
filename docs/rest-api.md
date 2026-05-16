# Slurm REST API

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
    -H "Authorization: Bearer <your-token>"

To get a list of all endpoints:

    curl http://localhost:6820/openapi/v3 \
    -H "Authorization: Bearer <your-token>"
