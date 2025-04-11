#!/bin/bash

# entrypoint.sh

echo "[ENTRYPOINT] Role: $ROLE"

echo "Starting munge..."
su -s /bin/bash slurm -c "/usr/sbin/munged --log-file=/var/log/munge/munged.log"
sleep 4

case "$ROLE" in
  controller)
    echo "Generating signing key..."
    su -s /bin/bash slurm -c "openssl rand -hex 32 > /etc/slurm/jwt_hs256.key"
    su -s /bin/bash slurm -c "chmod 600 /etc/slurm/jwt_hs256.key"

    echo "Starting slurmctld..."
    su -s /bin/bash slurm -c "/usr/sbin/slurmctld -D -vvvv"
    ;;
  compute)
    echo "Starting slurmd..."
    /usr/sbin/slurmd -D -vvvv --conf-server=slurm-controller
    ;;
  slurmdbd)
    echo "Starting slurmdbd..."
    su -s /bin/bash slurm -c "/usr/sbin/slurmdbd -D -vvvv"
    ;;
  rest)
    # Set the default JWT user
    export SLURM_JWT=restadmin

    echo "Starting slurmrestd..."
    su -s /bin/bash restuser -c "/usr/sbin/slurmrestd -a rest_auth/jwt 0.0.0.0:6820 -vvvv"
    ;;
  *)
    echo "Unknown role: $ROLE"
    exec "$@"
    ;;
esac
