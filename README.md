# NVIDIA Bootc Container Image

## Dev tips

* `BASE_IMAGE` in `argfile.conf` must remain consistent with the base image of `DRIVER_TOOLKIT_IMAGE`
* `INSTRUCTLAB_IMAGE_PULL_SECRET` in `argfile.conf` must remain consistent with `ADDITIONAL_SECRET` in `build-container` step in both `.tekton/nvidia-bootc-*.yaml`
