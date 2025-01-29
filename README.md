# NVIDIA Bootc Container Image

## Dev tips

* `BASE_IMAGE` in `argfile.conf` must remain consistent with the base image of `DRIVER_TOOLKIT_IMAGE`
* `INSTRUCTLAB_IMAGE_PULL_SECRET` in `argfile.conf` must remain consistent with `ADDITIONAL_SECRET` in `build-container` step in both `.tekton/nvidia-bootc-*.yaml`

## Build
Use the following command to build the NVIDIA drivers and libraries in
a bootable container.

    podman build --build-arg-file=argfile.conf -t 192.168.40.2:5000/bootc-nvidia .
