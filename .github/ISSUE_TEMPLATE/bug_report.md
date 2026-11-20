---
name: Bug report
about: Report a problem with the image, its entrypoint, or the command sandbox
title: ""
labels: bug
assignees: ""
---

**What fails**
<!-- One sentence: what does not work, and what you expected instead. -->

**How the container runs**

- Image and tag: <!-- 0x1917/deepseek-harness:<version> or 0x1917/deepseek-harness:latest -->
- Deployed with: <!-- Unraid template, docker run, or docker compose -->
- Unraid version, or host distribution, kernel and Docker version:
- CPU architecture: <!-- this image is built for x86_64 only -->
- Extra Parameters: <!-- the two --security-opt flags present? any others? -->
- Data path: <!-- new install or an existing /data directory -->

**Settings in use**
<!-- Fill in the ones you changed. Delete the rest. -->

- DSH_TRUSTED_HOSTS:
- DSH_PUBLIC_URL:
- DSH_BIND:
- PUID / PGID:
- Workspace mount: <!-- empty folder, or an existing share; its owner -->
- Reverse proxy in front: <!-- yes/no, and which one -->

**Steps to reproduce**

1.
2.
3.

**Logs**
<!-- docker logs <container>, or Docker tab > Logs. Keep the failing start.
Remove the token=... value from the login URL before pasting: it is a credential. -->

```text

```

**Does it fail on another tag?**
<!-- If you run :latest, try the same steps on the previous version tag. That
separates a packaging regression from an upstream one. -->

**Additional context**
<!-- Anything else that helps.

Two kinds of report belong elsewhere, not here:
- the Unraid template, its fields, its defaults, or the artwork:
  https://github.com/0x1917/unraid-templates/issues
- a bug inside DeepSeek Harness itself (the agent, models, tools, the web UI):
  https://github.com/deepseek-ai/deepseek-harness/discussions -->
