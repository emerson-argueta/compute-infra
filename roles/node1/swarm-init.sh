#!/bin/bash
MY_IP=$(hostname -I | awk '{print $1}')
docker swarm init --advertise-addr $MY_IP
docker swarm join-token worker > /tmp/swarm-token
