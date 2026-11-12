# Claude Code with Docker

This mirrors the sibling `Codex` container: Alpine 3.24.4, a private rootless Docker daemon so Claude can build and test containerized applications, a non-root CLI user (UID 1000), persistent CLI state, and a host directory mounted at `/workspace`. It includes Git, the GitHub CLI (`gh`), Bash, ripgrep, jq, make, GNU coreutils/findutils/grep/sed/awk/diff, Node.js/npm, Python/pip, the .NET 10 SDK, PowerShell 7.6.9, Docker with Buildx and Compose, and bubblewrap and socat for Claude Code's sandbox. Nothing in the container runs as root; add other Alpine packages when you build the image.

The image targets **linux/amd64**. On Windows, use Docker Desktop with Linux containers. The container runs as an unprivileged user with Docker's default capabilities; see [Isolation](#isolation). The host scripts work with Windows PowerShell 5.1 and PowerShell 7.

## Build from Windows PowerShell

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, so you can run it from any directory. Like the Codex build, it pulls the base image, disables build caching, and creates `claude-alpine-docker:latest` plus `akolodziejczak1128/claude-alpine-docker:latest`. Additional positional arguments add tags; nothing is pushed:

```powershell
.\build.ps1 'myregistry/claude:dev'
```

The `CLAUDE_VERSION` Docker build argument defaults to `latest`. To pin a version, set `$env:CLAUDE_VERSION = '<version>'` before running `build.ps1`. Rebuild to update Claude Code; automatic background updates are disabled because the CLI is installed globally in the image.

The container has no `sudo`, so Claude cannot install system packages at runtime. To bake extra Alpine packages into the image, list them before building:

```powershell
$env:EXTRA_APK_PACKAGES = 'postgresql-client go'
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\build.ps1'
```

At runtime Claude can still use `pip install --user`, npm, and `dotnet tool`, or run a tool in a container.

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
- An anonymous volume at `/home/claude/.local/share/docker` holds the rootless daemon's images and containers and is removed with the container. Use a named volume there if Docker data should persist.

The entrypoint runs as `claude` (UID 1000). It checks that the Claude state directory is writable, starts a rootless Docker daemon, waits up to 60 seconds for it, then launches Claude with umask `022`, so files Claude creates in `/workspace` are not restricted to mode `600`. Git is configured with `safe.directory = *` because Docker Desktop bind mounts often report a different owner, which otherwise makes Git refuse to work ("detected dubious ownership"). It forces the rootless daemon's socket and ignores inherited `DOCKER_HOST` and `DOCKER_CONTEXT` values. It never mounts the host Docker socket.

By default Claude uses the permission mode configured in `settings.json` inside `claude-state` (`permissions.defaultMode`), so a choice made there persists. To pick a mode for one run, set `CLAUDE_PERMISSION_MODE` (for example `bypassPermissions`, `acceptEdits`, `plan`, or `default`); the entrypoint passes it as `--permission-mode`:

```powershell
docker run -it -e CLAUDE_PERMISSION_MODE=bypassPermissions @claudeDockerArgs
# or, with the claude function:
$env:CLAUDE_PERMISSION_MODE = 'bypassPermissions'; claude
```

This environment variable selects a Claude permission mode, not a Codex sandbox mode.

The Dockerfile normalizes Windows CRLF line endings in `claude-init.sh`. PowerShell installation uses the same pinned musl x64 archive and SHA256 checksum as the source image. Claude Code is installed from `@anthropic-ai/claude-code`; Alpine uses the installed system ripgrep via `USE_BUILTIN_RIPGREP=0`. `PIP_BREAK_SYSTEM_PACKAGES=1` lets `pip install` work without Alpine's externally-managed-environment error; packages go to `~/.local` (on `PATH`) and disappear with the container.

Claude-specific behavior follows the official [installation guide](https://code.claude.com/docs/en/setup), [CLI reference](https://code.claude.com/docs/en/cli-reference), [configuration directory documentation](https://code.claude.com/docs/en/claude-directory), and [environment variables reference](https://code.claude.com/docs/en/env-vars).

## Isolation

Nothing in the container runs as root. The entrypoint, Claude Code, and the Docker daemon all run as `claude` (UID 1000). Docker runs in [rootless mode](https://docs.docker.com/engine/security/rootless/) inside its own user namespace, so root in a nested container is UID 1000, or an unprivileged subordinate ID (100000-165535), everywhere else. There is no `sudo`, and the image has no setuid or setgid programs (the build checks this). The container keeps Docker's default capabilities, `/proc` masks, and read-only `/sys`, and gets no host devices other than `/dev/net/tun`.

Beyond a default `docker run`, it needs only two options, which `ClaudeDockerArgs.ps1` passes:

- `--security-opt seccomp=<this folder>/seccomp.json`: Docker's default seccomp profile blocks creating user namespaces and mounting inside them, which rootless Docker and Claude Code's bubblewrap sandbox need. This profile allows those, and blocks io_uring, kernel keyrings, BPF, perf events, userfaultfd, VM sockets, kernel modules, kexec, reboot, and clock changes. Unprivileged code can still use user namespaces, which is the same kernel attack surface as rootless containers on any Linux host.
- `--device /dev/net/tun`: slirp4netns uses it to connect rootless Docker's private network namespace to the outside. It can only create interfaces in network namespaces the container owns; the VM's own network is unaffected.

On a Linux host with AppArmor (for example Ubuntu; not Docker Desktop), also pass `--security-opt apparmor=unconfined`, because the default AppArmor profile blocks those mounts.

What this means for containers Claude starts:

- They work as usual for building and testing: `docker run`, `docker build`, Compose, networks, volumes, and bind mounts of `/workspace` (files keep UID 1000). Published ports (`-p 8080:80`) are reachable from inside this container at `localhost`.
- `docker run --privileged` works, but its privileges apply only inside rootless Docker's user namespace: it cannot change VM-wide kernel settings or files owned by root.
- Resource limits such as `--memory` are ignored, with a warning.
- Their network traffic, and image pulls and builds, go through slirp4netns (user-mode networking), which is slower than a bridge for large transfers. The entrypoint turns off RootlessKit's faster "detach-netns" mode because the daemon was intermittently killed in it.

Any container still shares the Docker VM's kernel, so a kernel vulnerability remains the residual risk. Only mount directories you are willing to let Claude change.
