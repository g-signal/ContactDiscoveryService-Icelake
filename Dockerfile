FROM amd64/debian:bookworm@sha256:e83f38eb264420870d48bccc73f04df5fffc710c66528ad424f857eeff269915

LABEL description="linux build environment for sgx."

COPY docker/apt.conf docker/sources.list /etc/apt/
RUN rm -rf /etc/apt/sources.list.d/*
COPY docker/sgx_runtime_libraries.sh /tmp/
RUN /tmp/sgx_runtime_libraries.sh

ARG OPENENCLAVE_VERSION=0.19.13
ARG OPENENCLAVE_HASH=10a74d365c1add73b95388f22dad89cd62cbac701dbe935aae39ecf07f29c510
ADD --checksum=sha256:${OPENENCLAVE_HASH} \
    https://github.com/openenclave/openenclave/releases/download/v${OPENENCLAVE_VERSION}/Ubuntu_2204_open-enclave_${OPENENCLAVE_VERSION}_amd64.deb ./
RUN dpkg -i Ubuntu_2204_open-enclave_${OPENENCLAVE_VERSION}_amd64.deb



ADD https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb
RUN dpkg -i jdk-21_linux-x64_bin.deb


RUN apt-get update && apt-get install -y \
    libsgx-dcap-default-qpl=1.22.100.3-jammy1 \
    libsgx-dcap-default-qpl-dev=1.22.100.3-jammy1 \
    libcurl4 && apt-get clean



WORKDIR /home/app
COPY target/classes /home/app/classes
COPY target/dependency/* /home/app/libs/
COPY target/classes/sgx_default_qcnl_azure.conf /etc/sgx_default_qcnl.conf



ENTRYPOINT ["java", "-cp", "/home/app/libs/*:/home/app/classes/", "org.signal.cdsi.Application"]
