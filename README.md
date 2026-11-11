# Claude Code with Docker

This mirrors the sibling `Codex` container: Alpine 3.24.4, a private Docker daemon, a non-root CLI user (UID 1000), persistent CLI state, and a host directory mounted at `/workspace`. It includes Git, Bash, ripgrep, Node.js/npm, Python/pip, the .NET 10 SDK, PowerShell 7.6.9, and the same limited passwordless `sudo apk add --no-cache ...` access.

The image targets **linux/amd64**. On Windows, use Docker Desktop with Linux containers and support for privileged containers. The host scripts work with Windows PowerShell 5.1 and PowerShell 7.

## Build from Windows PowerShell

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, so you can run it from any directory. Like the Codex build, it pulls the base image, disables build caching, and creates `claude-alpine-docker:latest` plus `akolodziejczak1128/claude-alpine-docker:latest`. Additional positional arguments add tags; nothing is pushed:

```powershell
.\build.ps1 'myregistry/claude:dev'
```

The `CLAUDE_VERSION` Docker build argument defaults to `latest`. To pin a version, run `docker build --build-arg CLAUDE_VERSION=<version> -f claude.dockerfile -t claude-alpine-docker:latest .` from this directory. Rebuild to update Claude Code; automatic background updates are disabled because the CLI is installed globally in the image.

## Log in and run

Run from the host directory you want Claude to work in:

```powershell
. 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\ClaudeDockerArgs.ps1'

# Log in once; open the displayed URL in your Windows browser and follow the prompts.
docker run -i @claudeDockerArgs auth login

# Start an interactive session using the same credentials and settings.
docker run -it @claudeDockerArgs

# Run a non-interactive task without allocating a terminal.
docker run -i @claudeDockerArgs -p 'refactor unit tests'
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

The function uses `$claudeDockerArgs` if already defined; otherwise it loads the adjacent helper with the current directory as the default workspace. For `claude auth login` (including additional login options), it uses `docker run -i` so you can paste the browser's auth code without pseudo-terminal issues. Other invocations use `docker run -it` for interactive sessions. Use `docker run -i` directly for pipelines and automated tasks.

## Storage and execution

- `claude-state` is mounted at `/home/claude/.claude`. `CLAUDE_CONFIG_DIR` points there so credentials, settings, session history, and `.claude.json` persist together. Reuse this volume for login and later runs; it is separate from `codex-state`.
- The bind mount exposes the selected host directory at `/workspace`. Its permissions must allow UID 1000 to write when changes are needed.
- An anonymous volume at `/var/lib/docker` holds the private daemon's images and containers and is removed with the container. Use a named volume there if Docker data should persist.

The entrypoint starts `dockerd`, waits up to 60 seconds for readiness, checks that the Claude state directory is writable by UID 1000, then launches Claude as that user. It forces the local Docker socket and ignores inherited `DOCKER_HOST` and `DOCKER_CONTEXT` values. It never mounts the host Docker socket.

To match the source container's unrestricted execution, Claude starts with `--permission-mode bypassPermissions`. To restore ordinary Claude permission prompts:

```powershell
docker run -it -e CLAUDE_PERMISSION_MODE=default @claudeDockerArgs
```

This environment variable is implemented by the entrypoint; it selects a Claude permission mode, not a Codex sandbox mode. The privileged Docker configuration has the same broad host access implications as the source setup and is not a strong security boundary.

The Dockerfile normalizes Windows CRLF line endings in `claude-init.sh`. PowerShell installation uses the same pinned musl x64 archive and SHA256 checksum as the source image. Claude Code is installed from `@anthropic-ai/claude-code`; Alpine uses the installed system ripgrep via `USE_BUILTIN_RIPGREP=0`.

Claude-specific behavior follows the official [installation guide](https://code.claude.com/docs/en/setup), [CLI reference](https://code.claude.com/docs/en/cli-reference), [configuration directory documentation](https://code.claude.com/docs/en/claude-directory), and [environment variables reference](https://code.claude.com/docs/en/env-vars).
