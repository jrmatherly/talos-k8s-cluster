# Talos Patching

This directory contains Kustomization patches that are added to the talhelper configuration file.

<https://docs.siderolabs.com/talos/v1.11/configure-your-talos-cluster/system-configuration/patching>

## Patch Directories

Under this `patches` directory, there are several sub-directories that can contain patches that are added to the talhelper configuration file.
Each directory is optional and therefore might not created by default.

- `global/`: patches that are applied to both the controller and worker configurations
- `controller/`: patches that are applied to the controller configurations
- `worker/`: patches that are applied to the worker configurations
- `${node-hostname}/`: patches that are applied to the node with the specified name
