#!/bin/bash
services=$(docker stack services test-stack --format '{{.Name}}')

for service in $services; do
  echo "Updating $service"
  docker service update --force "$service"
done
