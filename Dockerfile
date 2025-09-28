FROM amd64/debian:bookworm@sha256:e83f38eb264420870d48bccc73f04df5fffc710c66528ad424f857eeff269915

LABEL description="linux build environment for sgx."

COPY docker/apt.conf docker/sources.list /etc/apt/
RUN rm -rf /etc/apt/sources.list.d/*


RUN mkdir /src && \
    apt-get update && \
    apt-get -y install \
    gpg \
    gnupg2 \
    wget \
    software-properties-common \
    libssl-dev \
    gdb \
    libprotobuf32 \
    libtool \
    bison \
    automake \
    flex \
    libcurl4 \
    afl++ \
    afl++-clang \
    valgrind \
    pkg-config \
    xz-utils

RUN apt-get -y install pipx pip python3-venv
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin
RUN pipx install pbtools==0.47.0 && echo "done"



COPY docker/sgx_runtime_libraries.sh /tmp/
RUN /tmp/sgx_runtime_libraries.sh

ARG OPENENCLAVE_VERSION=0.19.13
ARG OPENENCLAVE_HASH=10a74d365c1add73b95388f22dad89cd62cbac701dbe935aae39ecf07f29c510
ADD --checksum=sha256:${OPENENCLAVE_HASH} \
    https://github.com/openenclave/openenclave/releases/download/v${OPENENCLAVE_VERSION}/Ubuntu_2204_open-enclave_${OPENENCLAVE_VERSION}_amd64.deb ./
RUN dpkg -i Ubuntu_2204_open-enclave_${OPENENCLAVE_VERSION}_amd64.deb

# 安装 Java 21 并自动设置路径
RUN wget -O jdk-21.deb https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb && \
    dpkg -i jdk-21.deb && \
    rm jdk-21.deb && \
    echo "JAVA_HOME=$(find /usr/lib/jvm -name 'jdk-21*oracle*' -type d | head -1)" >> /etc/environment


# Rather than ADD --checksum=xxx this file, we wget it within a RUN so the file itself,
# which is quite large, doesn't show up in any intermediate layers.
COPY docker/clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10.tar.xz.sha256 /tmp
RUN cd /tmp && \
    wget -nv https://github.com/llvm/llvm-project/releases/download/llvmorg-11.1.0/clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10.tar.xz && \
    sha256sum -c clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10.tar.xz.sha256 && \
    tar xvf clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10.tar.xz \
        clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10/bin/clang-11 \
        clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10/lib/clang/11.1.0/include && \
    mv clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10 /opt/clang && \
    ln -s /opt/clang/bin/clang-11 /opt/clang/bin/clang++-11 && \
    rm -fv clang+llvm-11.1.0-x86_64-linux-gnu-ubuntu-20.10.tar.xz



RUN apt-get update && apt-get install -y \
    libsgx-dcap-default-qpl=1.22.100.3-jammy1 \
    libsgx-dcap-default-qpl-dev=1.22.100.3-jammy1 \
    libcurl4 && apt-get clean


# 动态设置 JAVA_HOME 和 PATH
RUN JAVA_HOME_DIR=$(find /usr/lib/jvm -name 'jdk-21*oracle*' -type d | head -1)

ENV JAVA_HOME=${JAVA_HOME_DIR}
ENV PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/opt/openenclave/share/pkgconfig"
ENV PATH="${JAVA_HOME_DIR}/bin:/opt/openenclave/bin:/opt/clang/bin:${PATH}"



WORKDIR /home/app
COPY target/classes /home/app/classes
COPY target/dependency/* /home/app/libs/
COPY target/classes/sgx_default_qcnl_azure.conf /etc/sgx_default_qcnl.conf



ENTRYPOINT ["java", "-cp", "/home/app/libs/*:/home/app/classes/", "org.signal.cdsi.Application"]
