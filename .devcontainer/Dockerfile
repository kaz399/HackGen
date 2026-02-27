FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies:
#   fontforge   - font editor/scripting engine used by .pe scripts
#   ttfautohint - TrueType hinting tool (README specifies 1.8.3; Ubuntu 22.04 ships 1.8.3)
#   python3/pip - runtime for fonttools (provides ttx and pyftmerge)
#   perl        - used in copyright.sh and cmap_patch.sh for text substitution
RUN apt-get update && apt-get install -y \
        fontforge \
        ttfautohint \
        python3 \
        python3-pip \
        perl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install fonttools which provides the ttx and pyftmerge commands.
# README originally specified 3.44.0 via pip2; modern fonttools (4.x) works on
# Linux and resolves the macOS post-table issue noted in the README.
# Pin to a specific version here if you need strict reproducibility, e.g.:
#   RUN pip3 install "fonttools==4.55.0"
RUN pip3 install fonttools

# Create a non-root user that matches the host user by default
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME}

USER ${USERNAME}
WORKDIR /workspace
