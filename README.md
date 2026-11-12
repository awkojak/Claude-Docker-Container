# Claude Code with Docker

This mirrors the sibling `Codex` container: Alpine 3.24.4, a private Docker daemon, a non-root CLI user (UID 1000), persistent CLI state, and a host directory mounted at `/workspace`. It includes Git, the GitHub CLI (`gh`), Bash, ripgrep, jq, make, GNU coreutils/findutils/grep/sed/awk/diff, Node.js/npm, Python/pip, the .NET 10 SDK, PowerShell 7.6.9, Docker with Buildx and Compose, bubblewrap and socat for Claude Code's sandbox, and the same limited passwordless `sudo apk add --no-cache ...` access for anything else.

The image targets **linux/amd64**. On Windows, use Docker Desktop with Linux containers. The container runs without `--privileged`; see [Container privileges](#container-privileges) for the narrower options it uses instead. The host scripts work with Windows PowerShell 5.1 and PowerShell 7.

## Build from Windows PowerShell

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, so you can run it from any directory. Like the Codex build, it pulls the base image, disables build caching, and creates `claude-alpine-docker:latest` plus `akolodziejczak1128/claude-alpine-docker:latest`. Additional positional arguments add tags; nothing is pushed:

```powershell
.\build.ps1 'myregistry/claude:dev'
```

The `CLAUDE_VERSION` Docker build argument defaults to `latest`. To pin a version, set `$env:CLAUDE_VERSION = '<version>'` before running `build.ps1`. Rebuild to update Claude Code; automatic background updates are disabled because the CLI is installed globally in the image.

## Log in and run

Run from the host directory you want Claude to work in:

```powershell
. 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\ClaudeDockerArgs.ps1'

# Log in once; open the displayed URL in your Windows browser and follow the prompts.
docker run -i @claudeDockerArgs auth login

# Start an interactive session using the same credentials and settings.
docker run -it @claudeDockerArgs

# Run a non-interactive task. Omit -i unless you pipe input, or print mode waits for stdin.
docker run @claudeDockerArgs -p 'refactor unit tests'
Get-Content .\build.log | docker run -i @claudeDockerArgs -p 'why did this fail?'
```

Claude uses `auth login` rather than Codex's `login --device-auth`, and `-p` rather than `exec`. All arguments after the image name are passed unchanged to Claude Code.

Set `$CLAUDE_IMAGE` and/or `$BIND_MOUNT_DIRECTORY` before dot-sourcing to override defaults, or pass the image and an absolute host directory as positional arguments:

```powershell
. .\ClaudeDockerArgs.ps1 'claude-alpine-docker:latest' 'C:\Users\akolo\My Projects'
```

As in the Codex helper, existing variables take precedence over positional arguments, and the generated array retains its selected directory until you load it again. To select a new directory, set `$BIND_MOUNT_DIRECTORY` and dot-source the helper again.

For the equivalent convenience function, dot-source `Claude.ps1` (or add this to your PowerShell profile):

```powershell
. 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\Claude.ps1'
claude auth login
claude
claude --continue
```

The function uses `$claudeDockerArgs` if already defined; otherwise it loads the adjacent helper with the current directory as the default workspace, so `cd` to another project and run `claude` again. It picks terminal options automatically:

- `claude auth login ...` uses `-i` so you can paste the browser's auth code without pseudo-terminal issues.
- Piped input (`Get-Content log.txt | claude -p 'summarize'`) uses `-i` and streams the input to the container.
- `claude -p ...` without piped input, or output piped onward (`claude -p 'list TODOs' | Out-File todo.txt`), runs without stdin or a TTY, so output is clean.
- Everything else uses `-it`.

### Environment passthrough

The argument array forwards these host variables when they are set (only the names appear on the command line):

| Variable | Purpose |
| --- | --- |
| `ANTHROPIC_API_KEY` | API-key authentication instead of `auth login`. |
| `CLAUDE_CODE_OAUTH_TOKEN` | Long-lived token from `claude setup-token`, useful for scripted runs. |
| `CLAUDE_PERMISSION_MODE` | Permission mode for the session (see below). |

## Storage and execution

- `claude-state` is mounted at `/home/claude/.claude`. `CLAUDE_CONFIG_DIR` points there so credentials, settings, session history, and `.claude.json` persist together. Reuse this volume for login and later runs; it is separate from `codex-state`.
- The bind mount exposes the selected host directory at `/workspace`. Its permissions must allow UID 1000 to write when changes are needed.
- An anonymous volume at `/var/lib/docker` holds the private daemon's images and containers and is removed with the container. Use a named volume there if Docker data should persist.

The entrypoint makes the container's cgroup filesystem writable and, with cgroup v2, moves its own processes into a child cgroup (as the official `docker:dind` image does), so nested containers can use resource limits such as `--memory`. It then starts `dockerd`, waits up to 60 seconds for readiness, checks that the Claude state directory is writable by UID 1000, then launches Claude as that user with umask `022`, so files Claude creates in `/workspace` are not restricted to mode `600`. Git is configured with `safe.directory = *` because Docker Desktop bind mounts often report a different owner, which otherwise makes Git refuse to work ("detected dubious ownership"). It forces the local Docker socket and ignores inherited `DOCKER_HOST` and `DOCKER_CONTEXT` values. It never mounts the host Docker socket.

By default Claude uses the permission mode configured in `settings.json` inside `claude-state` (`permissions.defaultMode`), so a choice made there persists. To pick a mode for one run, set `CLAUDE_PERMISSION_MODE` (for example `bypassPermissions`, `acceptEdits`, `plan`, or `default`); the entrypoint passes it as `--permission-mode`:

```powershell
docker run -it -e CLAUDE_PERMISSION_MODE=bypassPermissions @claudeDockerArgs
# or, with the claude function:
$env:CLAUDE_PERMISSION_MODE = 'bypassPermissions'; claude
```

This environment variable selects a Claude permission mode, not a Codex sandbox mode.

The Dockerfile normalizes Windows CRLF line endings in `claude-init.sh`. PowerShell installation uses the same pinned musl x64 archive and SHA256 checksum as the source image. Claude Code is installed from `@anthropic-ai/claude-code`; Alpine uses the installed system ripgrep via `USE_BUILTIN_RIPGREP=0`. `PIP_BREAK_SYSTEM_PACKAGES=1` lets `pip install` work without Alpine's externally-managed-environment error; packages go to `~/.local` (on `PATH`) and disappear with the container.

Claude-specific behavior follows the official [installation guide](https://code.claude.com/docs/en/setup), [CLI reference](https://code.claude.com/docs/en/cli-reference), [configuration directory documentation](https://code.claude.com/docs/en/claude-directory), and [environment variables reference](https://code.claude.com/docs/en/env-vars).

## Container privileges

The container does not use `--privileged`. Its private Docker daemon and bubblewrap sandboxes need only these options, which `ClaudeDockerArgs.ps1` passes:

| Option | Needed for |
| --- | --- |
| `--cap-add SYS_ADMIN` | Mounts, namespaces, overlay storage, and cgroups for nested containers and sandboxes. |
| `--cap-add NET_ADMIN` | Bridge networks, published ports, and iptables rules. |
| `--security-opt seccomp=unconfined` | runc and bubblewrap call `pivot_root` and `keyctl`, which Docker's default seccomp profile blocks. |
| `--security-opt apparmor=unconfined` | AppArmor hosts such as Ubuntu, where the default profile blocks mounts. No effect on Docker Desktop. |
| `--security-opt systempaths=unconfined` | Per-interface network settings under `/proc/sys/net` for nested containers, and an unmasked `/proc` for sandboxes on older kernels. |
| `--cgroupns private` | A cgroup tree of the container's own for nested containers (the default with cgroup v2). |

Compared with `--privileged`, the container no longer sees host devices (such as the Docker VM's disks, `/dev/mem`, and `/dev/kvm`), gets no other added capabilities, and keeps `/sys` read-only apart from its own cgroups. Nested containers are limited to the same capabilities: `docker run --privileged` inside still works but receives only those, and adding any other capability (for example `docker run --cap-add SYS_PTRACE`) fails. If a task needs one, add it to the outer command, for example `docker run -it --cap-add SYS_PTRACE @claudeDockerArgs`. The image also still works with `--privileged`.

`SYS_ADMIN` without seccomp filtering is still powerful, so this setup is not a strong security boundary. Only mount directories and run tasks you trust.
