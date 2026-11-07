# 在任意 Linux 上用一条命令跑完全部用例：
#   docker build -t cs340-asan .
#   docker run --rm cs340-asan
FROM gcc:13-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends make bash \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace

# LeakSanitizer 在容器里需要 ptrace 能力，--privileged 或在宿主机上跑更省事
CMD ["bash", "-lc", "make && bash scripts/run_all.sh"]
