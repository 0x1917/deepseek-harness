# DeepSeek Harness (DSH)

[![Version](https://img.shields.io/docker/v/0x1917/dsh)](https://hub.docker.com/r/0x1917/dsh)
[![Build](https://github.com/0x1917/deepseek-harness/actions/workflows/build.yml/badge.svg)](https://github.com/0x1917/deepseek-harness/actions/workflows/build.yml)
[![Lint](https://github.com/0x1917/deepseek-harness/actions/workflows/lint.yml/badge.svg)](https://github.com/0x1917/deepseek-harness/actions/workflows/lint.yml)
[![Pulls](https://img.shields.io/docker/pulls/0x1917/dsh)](https://hub.docker.com/r/0x1917/dsh)
[![Image size](https://img.shields.io/docker/image-size/0x1917/dsh)](https://hub.docker.com/r/0x1917/dsh)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64-blue?logo=linux&logoColor=white)](#command-sandbox)
[![License](https://img.shields.io/github/license/0x1917/deepseek-harness)](https://github.com/0x1917/deepseek-harness/blob/master/LICENSE)

The [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) web UI repackaged as a container for Unraid. To install it, search for it on the Community Applications plugin
or install it manually with the DSH template from [0x1917/unraid-templates](https://github.com/0x1917/unraid-templates/blob/master/templates/my-deepseek-harness.xml) (copy it to `/boot/config/plugins/dockerMan/templates-user/`).

## Build

```sh
docker build -t dsh .
```

## Run

Prebuilt on Docker Hub: `docker pull 0x1917/dsh:latest`.

```sh
docker run -d                        \
  --name dsh                         \
  --restart unless-stopped           \
  -p 3080:3080                       \
  -v /mnt/user/appdata/dsh:/data     \
  -v /mnt/user/workspace:/workspace  \
  0x1917/dsh

docker logs dsh   # prints the login URL
```

## Environment

| Variable            | Default                  | Meaning                                                                                 |
| ------------------- | ------------------------ | --------------------------------------------------------------------------------------- |
| `DSH_TRUSTED_HOSTS` | `localhost`              | Comma-separated host names that browsers use. Others get 403.                           |
| `DSH_PUBLIC_URL`    | `http://localhost:3080/` | The root of the printed login URL. Display only.                                        |
| `DSH_BIND`          | container IP             | The listen address.                                                                     |
| `PUID` / `PGID`     | `99` / `100`             | The user dsh runs as. `/data` is re-owned to it on start; `/workspace` only when empty. |
| `UMASK`             | `022`                    | Mask for the files dsh creates.                                                         |
| `DEEPSEEK_API_KEY`  | unset                    | Optional; the UI can store the key in `/data` instead.                                  |

## Command sandbox

dsh refuses to run agent commands without a sandbox. It tries bubblewrap, then Landlock.

- **Docker Desktop (macOS):** Landlock works; no extra flags.
- **Unraid:** the kernel has no Landlock, so bubblewrap is used, which needs
  `--security-opt seccomp=unconfined --security-opt systempaths=unconfined`.
