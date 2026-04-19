# ─────────────────────────────────────────────────────────────────────
# Android Build Tools (AAPT2, d8) are x86_64-only binaries.
# This image MUST run on an amd64 host. Do NOT build/run under
# QEMU emulation on Apple Silicon — it will be extremely slow.
#
# MITM proxy: drop CA .crt files into certs/ before building.
# ─────────────────────────────────────────────────────────────────────
FROM --platform=linux/amd64 ubuntu:24.04

ARG ANDROID_SDK_VERSION=13114758
ARG NDK_VERSION=28.2.13676358
ARG BUILD_TOOLS_VERSION=36.1.0
ARG PLATFORM_VERSION=android-36.1
ARG JAVA_VERSION=21
ARG GO_VERSION=1.26.2

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV NDK_HOME=${ANDROID_HOME}/ndk/${NDK_VERSION}
ENV ANDROID_NDK_HOME=${NDK_HOME}
ENV GOROOT=/usr/local/go
ENV GOPATH=/root/go
ENV GRADLE_USER_HOME=/root/.gradle
ENV JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64
ENV PATH="${GOPATH}/bin:${GOROOT}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# ── System dependencies ──────────────────────────────────────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends --allow-unauthenticated \
        openjdk-${JAVA_VERSION}-jdk-headless \
        ca-certificates \
        git \
        curl \
        unzip \
        wget \
        jq \
        make \
    && rm -rf /var/lib/apt/lists/*

# ── Import CA certs into system + Java truststores ───────────────────
RUN update-ca-certificates \
    && for cert in /usr/local/share/ca-certificates/custom/*.crt; do \
         [ -f "$cert" ] || continue; \
         echo "==> Importing CA: $(basename $cert)" && \
         keytool -import -trustcacerts -noprompt \
           -keystore "${JAVA_HOME}/lib/security/cacerts" \
           -storepass changeit \
           -alias "custom-$(basename $cert .crt)" \
           -file "$cert"; \
       done

# ── Go ───────────────────────────────────────────────────────────────
RUN curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

# ── Android SDK ──────────────────────────────────────────────────────
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && cd ${ANDROID_HOME}/cmdline-tools \
    && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" -o cmdline-tools.zip \
    && unzip -q cmdline-tools.zip \
    && mv cmdline-tools latest \
    && rm cmdline-tools.zip

RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true
RUN sdkmanager --install \
        "platforms;${PLATFORM_VERSION}" \
        "platforms;android-24" \
        "build-tools;${BUILD_TOOLS_VERSION}" \
        "platform-tools" \
        "ndk;${NDK_VERSION}"

# ── gomobile (after SDK + NDK are ready) ─────────────────────────────
RUN go install golang.org/x/mobile/cmd/gomobile@latest \
    && gomobile init

# ── Gradle wrapper (pre-download into image) ─────────────────────────
COPY V2rayNG/gradlew /tmp/gradlew-setup/gradlew
COPY V2rayNG/gradle/wrapper/ /tmp/gradlew-setup/gradle/wrapper/
RUN cd /tmp/gradlew-setup \
    && chmod 755 gradlew \
    && ./gradlew --version \
    && rm -rf /tmp/gradlew-setup

WORKDIR /project
