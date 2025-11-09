FROM alpine:latest AS zig-base

ENV ZIG_VERSION=0.15.2

RUN apk add --no-cache curl xz ca-certificates git && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then ZIG_ARCH="aarch64"; \
    elif [ "$ARCH" = "x86_64" ]; then ZIG_ARCH="x86_64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    echo "Downloading Zig ${ZIG_VERSION} for ${ZIG_ARCH}..." && \
    curl -fSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz && \
    tar -xJf /tmp/zig.tar.xz -C /usr/local && \
    rm /tmp/zig.tar.xz && \
    ln -s "/usr/local/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig && \
    apk del curl xz && \
    zig version

WORKDIR /workspace

CMD ["zig", "version"]

FROM zig-base AS dev

RUN apk add --no-cache watchexec

WORKDIR /app

COPY build.zig build.zig.zon ./

RUN zig build || true

CMD ["watchexec", "-r", "-w", "src", "-w", "build.zig", "-e", "zig", "--", "zig", "build", "run"]

FROM zig-base AS builder

WORKDIR /app
COPY . .

RUN zig build -Doptimize=ReleaseFast

FROM alpine:latest AS deploy

COPY --from=builder /app/zig-out/bin/server /usr/local/bin/server

CMD ["server"]
