# Run the full case set on any Linux host with one command:
#   docker build -t cs340-asan .
#   docker run --rm cs340-asan
FROM gcc:13-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends make bash \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace

# LeakSanitizer needs the ptrace capability inside a container; running on the
# host or with --privileged is simpler.
CMD ["bash", "-lc", "make && bash scripts/run_all.sh"]
