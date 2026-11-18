#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
case_dir=$(mktemp -d)
trap 'rm -rf -- "$case_dir"' EXIT
export HOME="$case_dir/home" DOCKER_CONFIG="$case_dir/docker"
export PATH="$case_dir/bin:$PATH" FAKE_DIR="$case_dir" FAKE_KEY='test-magpie-key-not-for-argv'
unset OPENAI_API_KEY OPENAI_BASE_URL MAGPIE_API_KEY MAGPIE_MODEL PROXY_PORT NPM_CONFIG_REGISTRY DOCKER_HOST DOCKER_CONTEXT COLIMA_HOME
mkdir -p "$case_dir/bin" "$case_dir/project with spaces" "$DOCKER_CONFIG" \
    "$HOME/.omp/agent" "$HOME/.claude" "$HOME/.codex"
for path in .omp/agent/agent.db .omp/agent/config.yml .claude/.credentials .codex/auth.json; do
    printf 'host-decoy\n' > "$HOME/$path"
done
cat > "$DOCKER_CONFIG/config.json" <<'EOF'
{"proxies":{"default":{"httpProxy":"http://proxy.invalid:7890","httpsProxy":"http://proxy.invalid:7890","allProxy":"socks5://proxy.invalid:7890","noProxy":"decoy.invalid"}}}
EOF

cat > "$case_dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FAKE_DIR/calls"
[[ "$*" != *"$FAKE_KEY"* && -z "${OPENAI_API_KEY+x}" ]] || exit 97
case "$1" in
    info) printf '%s\n' "${FAKE_OS:-OrbStack}" ;;
    ps) [[ -z "${FAKE_CONTAINER:-}" ]] || printf '%s\n' "$FAKE_CONTAINER" ;;
    context)
        case "$2" in
            show) printf '%s\n' "${DOCKER_CONTEXT:-fake-context}" ;;
            inspect)
                [[ "$5" == "${DOCKER_CONTEXT:-fake-context}" ]] || exit 98
                printf '%s\n' "${FAKE_ENDPOINT:-unix:///var/run/docker.sock}"
                ;;
            *) exit 98 ;;
        esac
        ;;
    image)
        case "$2" in
            inspect) [[ "${FAKE_IMAGE:-present}" == present && "$3" == *:magpie ]] ;;
            rm) printf '%s\n' "$@" > "$FAKE_DIR/removed-image" ;;
            *) exit 98 ;;
        esac
        ;;
    build)
        [[ -z "${MAGPIE_API_KEY:-}" && "${!#}" == - ]] || exit 99
        printf '%s\n' "$@" > "$FAKE_DIR/build"
        mkdir -p "$FAKE_DIR/context"
        archive="$FAKE_DIR/context.tar"
        cat > "$archive"
        [[ $(dd if="$archive" bs=1 count=10 2>/dev/null) == Dockerfile ]] || exit 99
        [[ $(dd if="$archive" bs=1 skip=257 count=5 2>/dev/null) == ustar ]] || exit 99
        tar -xf "$archive" -C "$FAKE_DIR/context"
        ;;
    run)
        [[ "${MAGPIE_API_KEY:-}" == "$FAKE_KEY" ]] || exit 100
        printf '%s\n' "$@" > "$FAKE_DIR/run"
        ;;
    rm) printf '%s\n' "$@" > "$FAKE_DIR/removed-container" ;;
    *) exit 101 ;;
esac
EOF
cat > "$case_dir/bin/colima" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DIR/colima-calls"
[[ "$*" == '--profile dev ssh -- ip route show default' ]] || exit 1
printf 'default via 192.168.64.1 dev eth0\n'
EOF
cat > "$case_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected gh call\n' >> "$FAKE_DIR/calls"
exit 1
EOF
chmod +x "$case_dir/bin/"*

fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$case_dir/output" >&2; exit 1; }
launch() { "$root/sandbox" "$@" > "$case_dir/output" 2>&1 || fail "sandbox $*"; }
reject() { if "$root/sandbox" "$@" > "$case_dir/output" 2>&1; then fail "expected sandbox $* to fail"; fi; }
has_line() { grep -Fxq -- "$2" "$case_dir/$1" || fail "missing '$2' in $1"; }
no_line() { if grep -Fxq -- "$2" "$case_dir/$1"; then fail "unexpected '$2' in $1"; fi; }

reject up omp
reject up codex
reject up claude-code
[[ ! -e "$case_dir/calls" ]] || fail 'missing key contacted Docker or GitHub'
export OPENAI_API_KEY="$FAKE_KEY"
for url in '' 'file://localhost/v1' 'http://user:pass@gateway/v1' 'http://localhost:65536/v1' \
    'http://[::g]/v1' 'http://[1::2::3]/v1' 'http://999.1.1.1/v1' 'http://bad label/v1' \
    'http://gateway/bad%zz' 'http://gateway/v1?key=test' 'https://gateway/v1#fragment'; do
    OPENAI_BASE_URL="$url" reject up omp
    grep -q 'OPENAI_BASE_URL' "$case_dir/output" || fail 'invalid URL should report OPENAI_BASE_URL'
done
PROXY_PORT=0 reject up omp
MAGPIE_MODEL='model"' reject up codex
[[ ! -e "$case_dir/calls" ]] || fail 'invalid input contacted Docker or GitHub'

for agent in omp claude-code codex; do
    rm -rf "$case_dir/context"
    FAKE_IMAGE=absent launch up "$agent"
    has_line run "sandbox-$agent:magpie"
    has_line build "sandbox-$agent:magpie"
    no_line build NPM_CONFIG_REGISTRY
    has_line run MAGPIE_API_KEY
    has_line run 'OPENAI_BASE_URL=http://host.docker.internal:3425/v1'
    has_line run --network
    has_line run bridge
    no_line run --add-host
    for flag in -v --volume --mount -p --publish --privileged --cap-add seccomp=unconfined; do no_line run "$flag"; done
    if [[ "$agent" == codex ]]; then
        has_line run --security-opt
        has_line run "seccomp=$root/agents/codex/seccomp.json"
    else
        no_line run --security-opt
    fi
    no_line run OPENAI_API_KEY
    has_line run 'NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal'
    has_line run 'no_proxy=localhost,127.0.0.1,::1,host.docker.internal'
    for key in HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy FTP_PROXY ftp_proxy; do
        has_line run "$key="
        has_line build "$key="
    done
    find "$case_dir/context" -type f -exec basename {} \; | sort > "$case_dir/files"
    printf 'Dockerfile\nsandbox-entry\n' | cmp -s - "$case_dir/files" || fail 'build context contains extra files'
    cmp -s "$root/agents/$agent/Dockerfile" "$case_dir/context/Dockerfile" || fail 'wrong Dockerfile transferred'
    cmp -s "$root/lib/sandbox-entry" "$case_dir/context/sandbox-entry" || fail 'wrong entrypoint transferred'
    case "$agent" in
        claude-code) has_line run 'MAGPIE_MODEL=auto/claude-opus-4-8' ;;
        *) has_line run 'MAGPIE_MODEL=auto/gpt-6.1-sol' ;;
    esac
done
[[ ! -e "$case_dir/colima-calls" ]] || fail 'OrbStack must not query an installed Colima CLI'
FAKE_IMAGE=absent NPM_CONFIG_REGISTRY=https://registry.example launch up claude-code
has_line build 'NPM_CONFIG_REGISTRY=https://registry.example'
no_line run 'NPM_CONFIG_REGISTRY=https://registry.example'

workspace=$(cd "$case_dir/project with spaces" && pwd -P)
url='https://gateway.example:4343/nested/with%20space/v1/'
OPENAI_BASE_URL="$url" MAGPIE_MODEL='custom/model-id' FAKE_OS='Docker Desktop' PROXY_PORT=8888 launch up codex "$workspace"
has_line run "OPENAI_BASE_URL=$url"
has_line run 'MAGPIE_MODEL=custom/model-id'
has_line run "$workspace:/workspace:rw"
[[ $(grep -Fxc -- -v "$case_dir/run") == 1 ]] || fail 'unexpected mounts'
has_line run 'NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal,gateway.example'
has_line run 'no_proxy=localhost,127.0.0.1,::1,host.docker.internal,gateway.example'
for key in HTTP_PROXY http_proxy HTTPS_PROXY https_proxy; do
    has_line run "$key=http://host.docker.internal:8888"
done
no_line run --add-host

OPENAI_BASE_URL="$url" FAKE_OS='Debian GNU/Linux' FAKE_ENDPOINT='ssh://other-machine' PROXY_PORT=8888 launch up codex --no-proxy
has_line run "OPENAI_BASE_URL=$url"
has_line run 'HTTP_PROXY='
no_line run --add-host
[[ ! -e "$case_dir/colima-calls" ]] || fail 'remote URL and --no-proxy must not query Colima'

for loopback in LOCALHOST. 127.9.8.7 '[::1]' '[0:0:00:000:0000:0:0:0001]' '[::FFFF:127.1.2.3]'; do
    OPENAI_BASE_URL="https://$loopback:4455/nested/v1" FAKE_OS='Debian GNU/Linux' \
        FAKE_ENDPOINT='unix:///var/run/docker.sock' launch up omp
    has_line run 'OPENAI_BASE_URL=https://host.docker.internal:4455/nested/v1'
    has_line run 'host.docker.internal:host-gateway'
done

OPENAI_BASE_URL='https://[2001:db8::1]:4000/v1' launch up codex
has_line run 'OPENAI_BASE_URL=https://[2001:db8::1]:4000/v1'
has_line run 'NO_PROXY=localhost,127.0.0.1,::1,host.docker.internal,2001:db8::1,[2001:db8::1]'
no_line run --add-host

FAKE_OS='Ubuntu' FAKE_ENDPOINT="unix://$HOME/.colima/dev/docker.sock" DOCKER_CONTEXT=colima-dev \
    DOCKER_HOST='ssh://other-machine' launch up claude-code
has_line run 'host.docker.internal:192.168.64.1'
has_line colima-calls '--profile dev ssh -- ip route show default'
DOCKER_HOST="unix://$HOME/.colima/dev/docker.sock" FAKE_OS='Ubuntu' launch up claude-code
has_line run 'host.docker.internal:192.168.64.1'

OPENAI_BASE_URL='https://Host.Docker.Internal.:4000/v1' FAKE_OS='Debian GNU/Linux' launch up codex
has_line run 'OPENAI_BASE_URL=https://Host.Docker.Internal.:4000/v1'
has_line run 'host.docker.internal:host-gateway'

if grep -Eq 'sandbox-auth|host-decoy|GH_TOKEN|unexpected gh call' "$case_dir/calls"; then fail 'host auth leaked'; fi
: > "$case_dir/calls"
FAKE_CONTAINER=sandbox-omp reject up omp
grep -q 'docker start -ai sandbox-omp' "$case_dir/output" || fail 'existing container must offer resume'
grep -q 'sandbox down omp' "$case_dir/output" || fail 'existing container must offer explicit removal'
if grep -Eq '^((image|container) )?(build|create|run|rm|rmi|prune)( |$)' "$case_dir/calls"; then
    fail 'up modified Docker state when the container already existed'
fi
unset OPENAI_API_KEY
FAKE_CONTAINER=sandbox-omp launch down omp --purge
has_line removed-container sandbox-omp
has_line removed-image sandbox-omp:magpie
if grep -q 'prune' "$case_dir/calls"; then fail 'down --purge pruned unrelated images'; fi
printf 'Fake Docker CLI tests passed.\n'

if command -v jq >/dev/null 2>&1; then
    export HOME="$case_dir/container-home" OPENAI_BASE_URL="$url" MAGPIE_MODEL='custom/model-id' MAGPIE_API_KEY="$FAKE_KEY"
    entry="$case_dir/context/sandbox-entry"
    for agent in omp codex; do
        bash "$entry" "$agent" -c 'exit' || fail "$agent entrypoint"
    done
    has_line 'container-home/.omp/agent/models.yml' "    baseUrl: \"$url\""
    has_line 'container-home/.omp/agent/models.yml' '    apiKey: MAGPIE_API_KEY'
    has_line 'container-home/.omp/agent/models.yml' '    api: openai-responses'
    has_line 'container-home/.omp/agent/models.yml' '      - id: "custom/model-id"'
    has_line 'container-home/.omp/agent/models.yml' '        reasoning: false'
    has_line 'container-home/.omp/agent/config.yml' '  default: "magpie/custom/model-id"'
    has_line 'container-home/.codex/config.toml' 'model = "custom/model-id"'
    has_line 'container-home/.codex/config.toml' 'model_provider = "magpie"'
    has_line 'container-home/.codex/config.toml' 'sandbox_mode = "workspace-write"'
    has_line 'container-home/.codex/config.toml' '[sandbox_workspace_write]'
    has_line 'container-home/.codex/config.toml' 'network_access = true'
    has_line 'container-home/.codex/config.toml' "base_url = \"$url\""
    has_line 'container-home/.codex/config.toml' 'wire_api = "responses"'
    has_line 'container-home/.codex/config.toml' 'env_key = "MAGPIE_API_KEY"'
    if grep -Fq "$FAKE_KEY" "$HOME"/.omp/agent/*.yml "$HOME/.codex/config.toml"; then fail 'credential written to config'; fi

    for path in .omp/agent/models.yml .omp/agent/config.yml .codex/config.toml; do
        printf 'container-edit\n' > "$HOME/$path"
    done
    for agent in omp codex; do
        bash "$entry" "$agent" -c 'exit' || fail "$agent entrypoint restart"
    done
    for path in .omp/agent/models.yml .omp/agent/config.yml .codex/config.toml; do
        [[ $(cat "$HOME/$path") == container-edit ]] || fail "restart overwrote $path"
    done

    rm "$HOME/.omp/agent/models.yml"
    bash "$entry" omp -c 'exit' || fail 'OMP partial config restart'
    has_line 'container-home/.omp/agent/models.yml' '    apiKey: MAGPIE_API_KEY'
    has_line 'container-home/.omp/agent/config.yml' 'container-edit'

    bash "$entry" claude-code -c '
        [[ "$ANTHROPIC_BASE_URL" == "https://gateway.example:4343/nested/with%20space" &&
           "$ANTHROPIC_AUTH_TOKEN" == "$FAKE_KEY" && "$ANTHROPIC_MODEL" == "custom/model-id" &&
           "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" == 1 ]]
    ' || fail 'Claude Code environment'
    printf 'Container entrypoint tests passed.\n'
else
    printf 'Container entrypoint tests skipped (jq is not installed on the test host).\n'
fi
