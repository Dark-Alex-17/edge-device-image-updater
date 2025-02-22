# edge-device-image-updater
This repository serves as an example of how to use [diun](https://github.com/crazy-max/diun) with [Docker Swarm](https://docs.docker.com/engine/swarm/)
to automatically detect image updates on edge devices, apply them, and have rollback functionality in the event of a failed update.

This works as follows:

1. A custom [diun image](https://hub.docker.com/repository/docker/darkalex17/diun-docker/general) was created to have the `docker` CLI installed ([Dockerfile](./diun-docker.Dockerfile)). This allows scripts run by the diun container to interact with the Docker daemon on the host machine.
2. A [simple script](./swarm-update.sh) was created to list all containers in the Docker Swarm and update them.
3. Whatever service(s) you're looking to run on your edge device, add them to a `docker-stack` file that also has `diun` configured so it can monitor all the images in the stack. In this instance, I simply bundled my [radarr-mock](https://hub.docker.com/repository/docker/darkalex17/radarr-mock/general) image with the [diun image](https://hub.docker.com/repository/docker/darkalex17/diun-docker/general).
4. Deploy the stack using `docker stack deploy -c docker-stack.yml test-stack`

## Prerequisites
### System Initialization
In order to use Docker Swarm on your device, you must first initialize it via `docker swarm init`.

### Docker Credentials
In order to allow the `diun` container to monitor images in private repositories, you must update the following line in the [docker-stack.yml](./docker-stack.yml):

```yaml
---
services:
  diun:
    ...
    volumes:
      ...
      - "/path/to/docker/config.json:/root/.docker/config.json:ro"
```

## Deploying
To deploy this stack, simply run `docker stack deploy -c docker-stack.yml test-stack`.

## Detailed Explanation
### What is Diun?
**D**ocker **I**mage **U**pdate **N**otifier ([diun](https://crazymax.dev/diun)) is a CLI application to receive notifications when a Docker image is updated on a Docker registry.
It allows us to execute a script whenever it detects a new image version, which we can use to automatically update our services.

### What's Happening in the Docker Compose file?
In the [docker-stack.yml](./docker-stack.yml), I have listed two services: `diun` and `radarr-mock`. The former is for monitoring and notifying on new image versions, and the latter is an example of an application image that we want to keep updated.

#### Diun Service
There's a few points to note in the `diun` service configuration:

##### Volumes
We mount the following volumes into the `diun` container:

| Volume | Description |
|--------|-------------|
| `/var/run/docker.sock:/var/run/docker.sock` | This is how the `diun` container interacts with the Docker daemon on the host machine. It allows the `diun` container to list all the images, containers, etc. |
| `./swarm-update.sh:/swarm-update.sh` | Mount the script that will be executed on image updates. |
| `/path/to/docker/config.json:/root/.docker/config.json:ro` | Mount the Docker configuration file so that `diun` can monitor images in private repositories. |

##### Environment Variables
The `diun` service is configured using environment variables. The most important ones are:

| Variable | Description |
|----------|-------------|
| `DIUN_WATCH_SCHEDULE='*/1 * * * *'` | This variable is used to set the schedule for checking for new image versions. In this case, it is set to check once every minute. |
| `DIUN_PROVIDERS_SWARM=true` | This variable instructs `diun` to use Docker Swarm to detect running services to detect their images and to monitor them (see [Diun Providers](https://crazymax.dev/diun/providers/swarm/))|
| `DIUN_NOTIF_SCRIPT_CMD=sh` | Tell `diun` that it needs to execute a `sh` script when a new image is detected. This is considered a [script notification](https://crazymax.dev/diun/notif/script/) |
| `DIUN_NOTIF_SCRIPT_ARGS=/swarm-update.sh` | Indicate to `diun` that we want to run the script `/swarm-update.sh` when a new image is detected (see [this discussion](https://github.com/crazy-max/diun/discussions/863) to understand why we're calling it like this)|

#### Radarr-Mock Service
In the Radarr Mock service, there's only a couple of points of interest that may differ from your standard Docker Compose service definition.

##### Configure Rollbacks for Failed Updates
Whenever an update fails, we want to ensure continued service. To achieve this, we use Docker Swarm's rollback capabilities on the service. It is configured as follows:

```yaml
radarr-mock:
  deploy:
    update_config:
      order: start-first
      failure_action: rollback
      delay: 10s
      parallelism: 1
```

This ensures that if ever an update to this service fails, Docker Swarm will rollback to the previous version. Additionally, `order: start-first` ensures the new version is healthy before stopping the old one.

##### Configure the Restart Policy to Prevent Boot Loops
Additionally, there's occasionally situations where a service will fail to start, causing Docker Swarm to restart the service, which in turn fails again. To prevent this, we configure the service to only try a max of 3 times to start the service before giving up:

```yaml
radarr-mock:
  deploy:
    restart_policy:
      condition: on-failure
      max_attempts: 3
      delay: 5s
```

##### Specify the Health Check to Ensure Service is Healthy
We also want to ensure that Docker Swarm knows that our service is healthy. This is achieved by using the `healthcheck` directive in the service definition:

```yaml
radarr-mock:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:7878"]
    interval: 10s
    timeout: 3s
    retries: 2
    start_period: 10s
```

##### Label the Service for Diun Monitoring
And finally, to ensure that `diun` monitors this service, we add the following label to the service definition:

```yaml
radarr-mock:
  deploy:
    labels:
      - "diun.enable=true"
```
