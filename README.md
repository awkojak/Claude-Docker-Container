# Claude Code in Alpine

This mirrors the sibling `Codex` container: Alpine 3.24.4, a non-root CLI user (UID 1000), persistent CLI state, and a host directory mounted at `/workspace`. It includes Git, the GitHub CLI (`gh`), Bash, ripgrep, jq, make, GNU coreutils/findutils/grep/sed/awk/diff, Node.js/npm, Python/pip, the .NET 10 SDK, PowerShell 7.6.9, bubblewrap and socat for Claude Code's sandbox, and the same limited passwordless `sudo apk add --no-cache ...` access for anything else.

The image targets **linux/amd64**. On Windows, use Docker Desktop with Linux containers. The CLI and entrypoint run as UID 1000 with the default container permissions. The host scripts work with Windows PowerShell 5.1 and PowerShell 7.

## Build from Windows PowerShell

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Claude\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, so you can run it from any directory. Like the Codex build, it pulls the base image, disables build caching, and creates `$CLAUDE_IMAGE` from `image.env` plus `akolodziejczak1128/$CLAUDE_IMAGE`. Additional positional arguments add tags; nothing is pushed:

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
. .\ClaudeDockerArgs.ps1 'myregistry/agent:dev' 'C:\Users\akolo\My Projects'
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

The entrypoint checks that `CLAUDE_CONFIG_DIR` is writable and launches Claude as UID 1000 with umask `022`. No Docker daemon or client is installed in this image. Git accepts bind-mounted repositories with different ownership.

By default Claude uses the permission mode configured in `settings.json` inside `claude-state` (`permissions.defaultMode`), so a choice made there persists. To pick a mode for one run, set `CLAUDE_PERMISSION_MODE` (for example `bypassPermissions`, `acceptEdits`, `plan`, or `default`); the entrypoint passes it as `--permission-mode`:

```powershell
docker run -it -e CLAUDE_PERMISSION_MODE=bypassPermissions @claudeDockerArgs
# or, with the claude function:
$env:CLAUDE_PERMISSION_MODE = 'bypassPermissions'; claude
```

This environment variable selects a Claude permission mode, not a Codex sandbox mode.

The Dockerfile normalizes Windows CRLF line endings in `claude-init.sh`. PowerShell installation uses the same pinned musl x64 archive and SHA256 checksum as the source image. Claude Code is installed from `@anthropic-ai/claude-code`; Alpine uses the installed system ripgrep via `USE_BUILTIN_RIPGREP=0`. `PIP_BREAK_SYSTEM_PACKAGES=1` lets `pip install` work without Alpine's externally-managed-environment error; packages go to `~/.local` (on `PATH`) and disappear with the container.

Claude-specific behavior follows the official [installation guide](https://code.claude.com/docs/en/setup), [CLI reference](https://code.claude.com/docs/en/cli-reference), [configuration directory documentation](https://code.claude.com/docs/en/claude-directory), and [environment variables reference](https://code.claude.com/docs/en/env-vars).

## Branch and image selection

`image.env` is the single source of the default `CLAUDE_IMAGE`. Both `build.ps1`
and the run helper load it through `ImageConfig.ps1`. Set `$CLAUDE_IMAGE` before
invoking either script to override it; build positional arguments remain extra tags.
The `main` branch contains the CLI without Docker installed inside the image;
the `*-dockerd` branch contains a rootful daemon, and `*-rootless` contains a
rootless daemon. Each branch has its own image tag. Build and run from the same checkout.

After changing branches, start a fresh PowerShell session or clear cached settings
before loading the helper again:

```powershell
Remove-Variable CLAUDE_IMAGE, BIND_MOUNT_DIRECTORY, claudeDockerArgs -ErrorAction SilentlyContinue
. .\ClaudeDockerArgs.ps1
```
