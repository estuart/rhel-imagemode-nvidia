ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG BASE_URL='https://us.download.nvidia.com/tesla'

ARG VENDOR
ARG INSTRUCTLAB_IMAGE
LABEL vendor=${VENDOR} \
      org.opencontainers.image.vendor=${VENDOR} \
      INSTRUCTLAB_IMAGE=${INSTRUCTLAB_IMAGE}

ARG DRIVER_TYPE=passthrough
ENV NVIDIA_DRIVER_TYPE=${DRIVER_TYPE}

ARG DRIVER_VERSION
ENV NVIDIA_DRIVER_VERSION=${DRIVER_VERSION}
ARG CUDA_VERSION='12.4.1'

ARG TARGET_ARCH=''
ENV TARGETARCH=${TARGET_ARCH}

ARG EXTRA_RPM_PACKAGES=''

# Disable vGPU version compatibility check by default
ARG DISABLE_VGPU_VERSION_CHECK=true
ENV DISABLE_VGPU_VERSION_CHECK=$DISABLE_VGPU_VERSION_CHECK

USER root

COPY repos/redhat.repo /etc/yum.repos.d/redhat.repo
COPY repos/rhelai-1.2.repo /etc/yum.repos.d/rhelai-1.2.repo

COPY repos/cuda-rhel9.repo /etc/yum.repos.d/cuda-rhel9.repo
COPY repos/RPM-GPG-KEY-NVIDIA-CUDA-9 /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA-CUDA-9

COPY nvidia-toolkit-firstboot.service /usr/lib/systemd/system/nvidia-toolkit-firstboot.service
COPY usr /usr

ARG IMAGE_VERSION_ID

# The need for the `cp /etc/dnf/dnf.conf` is a workaround for https://github.com/containers/bootc/issues/637
RUN mv /etc/selinux /etc/selinux.tmp \
    && export OS_VERSION_MAJOR=$(grep "^VERSION=" /etc/os-release | cut -d '=' -f 2 | sed 's/"//g' | cut -d '.' -f 1) \
    && export KERNEL_VERSION=$(rpm -q --qf "%{VERSION}" kernel-core) \
    && export KERNEL_RELEASE=$(rpm -q --qf "%{RELEASE}" kernel-core | sed 's/\.el.\(_.\)*$//') \
    && if [ "${TARGET_ARCH}" == "" ]; then \
        export TARGET_ARCH="$(arch)" ;\
    fi \
    && if [ "${TARGET_ARCH}" == "aarch64" ]; then CUDA_REPO_ARCH="sbsa"; fi \
    && export DRIVER_STREAM=$(echo ${DRIVER_VERSION} | cut -d '.' -f 1) \
        CUDA_VERSION_ARRAY=(${CUDA_VERSION//./ }) \
        CUDA_DASHED_VERSION=${CUDA_VERSION_ARRAY[0]}-${CUDA_VERSION_ARRAY[1]} \
        CUDA_REPO_ARCH=${TARGET_ARCH} \
    && cp -a /etc/dnf/dnf.conf{,.tmp} && mv /etc/dnf/dnf.conf{.tmp,} \
    && dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA-CUDA-9 \
    && dnf -y module enable nvidia-driver:${DRIVER_STREAM}/default \
    && dnf install -y \
        cloud-init \
        git \
        git-lfs \
        nvtop \
        pciutils \
        tmux \
        kmod-nvidia-${DRIVER_VERSION}-${KERNEL_VERSION}-${KERNEL_RELEASE} \
        nvidia-driver-${DRIVER_VERSION} \
        nvidia-driver-cuda-${DRIVER_VERSION} \
        nvidia-driver-libs-${DRIVER_VERSION} \
        nvidia-driver-NVML-${DRIVER_VERSION} \
        cuda-compat-${CUDA_DASHED_VERSION} \
        cuda-cudart-${CUDA_DASHED_VERSION} \
        nvidia-persistenced-${DRIVER_VERSION} \
        nvidia-container-toolkit \
        rsync \
	skopeo \
        ${EXTRA_RPM_PACKAGES} \
    && if [[ "$(rpm -qa | grep kernel-core | wc -l)" != "1" ]]; then \
        echo "ERROR - Multiple kernel-core packages detected"; \
        echo "This usually means that nvidia-drivers are built for a different kernel version than the one installed"; \
        exit 1; \
       fi \
    && if [ "$DRIVER_TYPE" != "vgpu" ] && [ "$TARGET_ARCH" != "arm64" ]; then \
        versionArray=(${DRIVER_VERSION//./ }); \
        DRIVER_BRANCH=${versionArray[0]}; \
        dnf module enable -y nvidia-driver:${DRIVER_BRANCH} && \
        dnf install -y nvidia-fabric-manager-${DRIVER_VERSION} libnvidia-nscq-${DRIVER_BRANCH}-${DRIVER_VERSION} ; \
    fi \
    && . /etc/os-release && if [ "${ID}" == "rhel" ]; then \
        # Install rhc connect for insights telemetry gathering
        dnf install -y rhc rhc-worker-playbook; \
        # Adding rhel ai identity to os-release file for insights usage
        sed -i -e "/^VARIANT=/ {s/^VARIANT=.*/VARIANT=\"RHEL AI\"/; t}" -e "\$aVARIANT=\"RHEL AI\"" /usr/lib/os-release; \
        sed -i -e "/^VARIANT_ID=/ {s/^VARIANT_ID=.*/VARIANT_ID=rhel_ai/; t}" -e "\$aVARIANT_ID=rhel_ai" /usr/lib/os-release; \
        sed -i -e "/^RHEL_AI_VERSION_ID=/ {s/^RHEL_AI_VERSION_ID=.*/RHEL_AI_VERSION_ID='${IMAGE_VERSION_ID}'/; t}" -e "\$aRHEL_AI_VERSION_ID='${IMAGE_VERSION_ID}'" /usr/lib/os-release; \
        # disable auto upgrade service
        rm -f /usr/lib/systemd/system/default.target.wants/bootc-fetch-apply-updates.timer; \
        fi \
    && dnf clean all \
    && ln -s ../cloud-init.target /usr/lib/systemd/system/default.target.wants \
    && mv /etc/selinux.tmp /etc/selinux \
    && ln -s /usr/lib/systemd/system/nvidia-toolkit-firstboot.service /usr/lib/systemd/system/basic.target.wants/nvidia-toolkit-firstboot.service \
    && echo "blacklist nouveau" > /etc/modprobe.d/blacklist_nouveau.conf \
    && sed -i '/\[Unit\]/a ConditionDirectoryNotEmpty=/proc/driver/nvidia-nvswitch/devices' /usr/lib/systemd/system/nvidia-fabricmanager.service \
    && ln -s /usr/lib/systemd/system/nvidia-fabricmanager.service /etc/systemd/system/multi-user.target.wants/nvidia-fabricmanager.service \
    && ln -s /usr/lib/systemd/system/nvidia-persistenced.service /etc/systemd/system/multi-user.target.wants/nvidia-persistenced.service

ARG SSHPUBKEY

# The --build-arg "SSHPUBKEY=$(cat ~/.ssh/id_rsa.pub)" option inserts your
# public key into the image, allowing root access via ssh.
RUN if [ -n "${SSHPUBKEY}" ]; then \
    set -eu; mkdir -p /usr/ssh && \
        echo 'AuthorizedKeysFile /usr/ssh/%u.keys .ssh/authorized_keys .ssh/authorized_keys2' >> /etc/ssh/sshd_config.d/30-auth-system.conf && \
	    echo ${SSHPUBKEY} > /usr/ssh/root.keys && chmod 0600 /usr/ssh/root.keys; \
fi

# Setup /usr/lib/containers/storage as an additional store for images.
# Remove once the base images have this set by default.
# Also make sure not to duplicate if a base image already has it specified.
RUN grep -q /usr/lib/containers/storage /etc/containers/storage.conf || \
    sed -i -e '/additionalimage.*/a "/usr/lib/containers/storage",' \
	/etc/containers/storage.conf

ARG INSTRUCTLAB_IMAGE_PULL_SECRET

RUN for i in /usr/bin/ilab*; do \
	sed -i 's/__REPLACE_TRAIN_DEVICE__/cuda/' $i;  \
	sed -i 's/__REPLACE_CONTAINER_DEVICE__/nvidia.com\/gpu=all/' $i; \
	sed -i "s%__REPLACE_IMAGE_NAME__%${INSTRUCTLAB_IMAGE}%" $i; \
    done

# Added for running as an OCI Container to prevent Overlay on Overlay issues.
VOLUME /var/lib/containers

RUN --mount=type=secret,id=${INSTRUCTLAB_IMAGE_PULL_SECRET}/.dockerconfigjson \
    if [ -f "/run/.input/instructlab-nvidia/oci-layout" ]; then \
         IID=$(podman --root /usr/lib/containers/storage pull oci:/run/.input/instructlab-nvidia) && \
         podman --root /usr/lib/containers/storage image tag ${IID} ${INSTRUCTLAB_IMAGE}; \
    elif [ -f "/run/secrets/${INSTRUCTLAB_IMAGE_PULL_SECRET}/.dockerconfigjson" ]; then \
         IID=$(sudo podman --root /usr/lib/containers/storage pull --authfile /run/secrets/${INSTRUCTLAB_IMAGE_PULL_SECRET}/.dockerconfigjson ${INSTRUCTLAB_IMAGE}); \
    else \
         IID=$(sudo podman --root /usr/lib/containers/storage pull ${INSTRUCTLAB_IMAGE}); \
    fi

RUN podman system reset --force 2>/dev/null

LABEL image_version_id="${IMAGE_VERSION_ID}"
