# Experimental Linux toolchain for building the iOS target with xtool
# (https://github.com/xtool-org/xtool).
#
# Honest constraints (see docs/LIMITATIONS.md for the full story):
#  - xtool supports iOS ONLY. The watchOS companion cannot be built on Linux;
#    the primary pipeline uses GitHub's free hosted macOS runners instead.
#  - The Apple/Darwin SDK cannot be redistributed, so this image contains no
#    SDK. At runtime you must supply XCODE_XIP_URL pointing at a Xcode .xip
#    you downloaded with your own Apple ID; Build.sh feeds it to `xtool setup`.

FROM swift:6.1-noble

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    zip \
    libssl-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Build xtool from source (no prebuilt Linux binaries are guaranteed across
# releases, and building pins us to a known-good ref).
RUN git clone --depth 1 https://github.com/xtool-org/xtool /opt/xtool-src \
    && cd /opt/xtool-src \
    && swift build -c release \
    && cp .build/release/xtool /usr/local/bin/xtool \
    && rm -rf /opt/xtool-src/.build

WORKDIR /workspace
COPY . .

CMD ["./Build.sh"]
