# Variables for the app module
#
# TODO: Define the following variables with appropriate types, descriptions,
#       and default values where noted.

# app_name   — (string, required) Name of the application

# namespace  — (string, required) Kubernetes namespace

# image      — (string, required) Container image to deploy

# replicas   — (number, default: 1) Number of pod replicas

# port       — (number, default: 8080) Container port

# env_vars   — (map(string), default: {}) Environment variables for the container

# enable_ingress — (bool, default: false) Whether to create a Traefik IngressRoute

# host       — (string, default: "") Hostname for the IngressRoute
