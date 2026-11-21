# Run the full case set on any Linux host with one command:
#   docker build -t cs340-asan .
#   docker run --rm --cap-add=SYS_PTRACE cs340-asan
FROM gcc:13-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends make bash clang python3 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace

CMD ["bash", "-lc", "make && bash scripts/run_all.sh"]
