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
    ps)
        [[ "${FAKE_PS_EXIT:-0}" == 0 ]] || exit "$FAKE_PS_EXIT"
        containers="${FAKE_PS_LINES:-}"
        if [[ -f "$FAKE_DIR/run-container" ]]; then
            containers+=$'\n'"$(cat "$FAKE_DIR/run-container")"
        fi
        while IFS=$'\t' read -r name state; do
            [[ -n "$name" ]] || continue
            [[ "$state" == running || " $* " == *' -a '* ]] || continue
            case "${!#}" in
                '{{.Names}}') printf '%s\n' "$name" ;;
                '{{.Names}}\t{{.State}}') printf '%s\t%s\n' "$name" "$state" ;;
                'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Size}}')
                    [[ "$4" != "name=^$name\$" ]] || printf '%s\t%s\t%s:magpie\t0B\n' "$name" "$state" "$name"
                    ;;
                *) exit 98 ;;
            esac
        done <<< "$containers"
        ;;
    context)
        context="${DOCKER_CONTEXT:-fake-context}"
        if [[ -n "${DOCKER_HOST:-}" ]]; then context=default; fi
        case "$2" in
            show) printf '%s\n' "$context" ;;
            inspect)
                [[ "$5" == "$context" ]] || exit 98
                printf '%s\n' "${DOCKER_HOST:-${FAKE_ENDPOINT:-unix:///var/run/docker.sock}}"
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
        if [[ -n "${FAKE_RUN_CONTAINER:-}" ]]; then
            printf '%s\texited\n' "$FAKE_RUN_CONTAINER" > "$FAKE_DIR/run-container"
        fi
        exit "${FAKE_RUN_EXIT:-0}"
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
run_returns() {
    local expected="$1" rc=0
    shift
    "$root/sandbox" "$@" > "$case_dir/output" 2>&1 || rc=$?
    [[ "$rc" == "$expected" ]] || fail "expected sandbox $* to exit $expected, got $rc"
}
has_line() { grep -Fxq -- "$2" "$case_dir/$1" || fail "missing '$2' in $1"; }
no_line() { if grep -Fxq -- "$2" "$case_dir/$1"; then fail "unexpected '$2' in $1"; fi; }

reject bogus
grep -Fq 'Unknown command: bogus' "$case_dir/output" || fail 'unknown command should name the command'
has_line output "       Run 'sandbox help' for usage."
if grep -Fq '\n' "$case_dir/output"; then fail 'unknown command printed a literal newline escape'; fi
reject list extra
grep -Fq 'Usage: sandbox list' "$case_dir/output" || fail 'list extra should report usage'
reject ls extra
grep -Fq 'Usage: sandbox list' "$case_dir/output" || fail 'ls extra should report usage'
reject status omp extra
grep -Fq 'Usage: sandbox status [agent]' "$case_dir/output" || fail 'status extra should report usage'
reject status --extra
grep -Fq 'Unknown option: --extra' "$case_dir/output" || fail 'status should report unknown options'
[[ ! -e "$case_dir/calls" ]] || fail 'invalid commands contacted Docker or GitHub'

reject up omp
reject up codex
reject up claude-code
[[ ! -e "$case_dir/calls" ]] || fail 'missing key contacted Docker or GitHub'
export OPENAI_API_KEY="$FAKE_KEY"
for url in '' 'file://localhost/v1' 'http://user:pass@gateway/v1' 'http://localhost:65536/v1' \
    'http://[::g]/v1' 'http://[1::2::3]/v1' 'http://999.1.1.1/v1' 'http://bad label/v1' \
    'http://gateway/bad%zz' 'http://gateway/v1?key=test' 'https://gateway/v1#fragment' \
    $'http://gateway\n:3425/v1'; do
    OPENAI_BASE_URL="$url" reject up omp
    grep -q 'OPENAI_BASE_URL' "$case_dir/output" || fail 'invalid URL should report OPENAI_BASE_URL'
done
for registry in 'http://user:pass@registry.example' 'https://registry.example/npm/?key=test' \
    'https://registry.example/npm/#fragment' 'ftp://registry.example/npm/' \
    'https://bad host/npm/' 'https://registry.example:65536/npm/' $'https://registry.example\n'; do
    NPM_CONFIG_REGISTRY="$registry" reject up omp
    grep -Fq 'NPM_CONFIG_REGISTRY' "$case_dir/output" || fail 'invalid registry should report NPM_CONFIG_REGISTRY'
done
PROXY_PORT=0 reject up omp
MAGPIE_MODEL='model"' reject up codex
reject up omp "$case_dir/missing-project"
grep -Fq 'Workspace directory is not accessible.' "$case_dir/output" || fail 'missing workspace should report an error'
if grep -Fq 'cd:' "$case_dir/output"; then fail 'workspace error leaked raw cd stderr'; fi
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
FAKE_IMAGE=absent NPM_CONFIG_REGISTRY=https://registry.example/npm/ launch up claude-code
has_line build 'NPM_CONFIG_REGISTRY=https://registry.example/npm/'
no_line run 'NPM_CONFIG_REGISTRY=https://registry.example/npm/'
has_line run 'OPENAI_BASE_URL=http://host.docker.internal:3425/v1'

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

FAKE_OS='Ubuntu' FAKE_ENDPOINT="unix://$HOME/.colima/dev/docker.sock" DOCKER_CONTEXT=colima-dev launch up claude-code
has_line run 'host.docker.internal:192.168.64.1'
has_line colima-calls '--profile dev ssh -- ip route show default'
: > "$case_dir/colima-calls"
: > "$case_dir/calls"
FAKE_OS='Ubuntu' FAKE_ENDPOINT="unix://$HOME/.colima/dev/docker.sock" DOCKER_CONTEXT=colima-dev \
    DOCKER_HOST='ssh://other-machine' launch up claude-code
has_line run 'host.docker.internal:host-gateway'
[[ ! -s "$case_dir/colima-calls" ]] || fail 'DOCKER_HOST should override the Colima context'
if grep -q '^context ' "$case_dir/calls"; then fail 'DOCKER_HOST should skip Docker context lookups'; fi
DOCKER_HOST="unix://$HOME/.colima/dev/docker.sock" DOCKER_CONTEXT=other-context FAKE_OS='Ubuntu' launch up claude-code
has_line run 'host.docker.internal:192.168.64.1'
has_line colima-calls '--profile dev ssh -- ip route show default'

OPENAI_BASE_URL='https://Host.Docker.Internal.:4000/v1' FAKE_OS='Debian GNU/Linux' launch up codex
has_line run 'OPENAI_BASE_URL=https://Host.Docker.Internal.:4000/v1'
has_line run 'host.docker.internal:host-gateway'

if grep -Eq 'sandbox-auth|host-decoy|GH_TOKEN|unexpected gh call' "$case_dir/calls"; then fail 'host auth leaked'; fi
: > "$case_dir/calls"
FAKE_PS_LINES=$'sandbox-omp\texited' reject up omp
grep -q 'docker start -ai sandbox-omp' "$case_dir/output" || fail 'existing container must offer resume'
grep -q 'sandbox down omp' "$case_dir/output" || fail 'existing container must offer explicit removal'
if grep -Eq '^((image|container) )?(build|create|run|rm|rmi|prune)( |$)' "$case_dir/calls"; then
    fail 'up modified Docker state when the container already existed'
fi

FAKE_RUN_EXIT=125 run_returns 125 up omp
if grep -Fq 'Container preserved' "$case_dir/output"; then fail 'up claimed a missing container was preserved'; fi
FAKE_RUN_EXIT=42 FAKE_RUN_CONTAINER=sandbox-omp run_returns 42 up omp
grep -Fq "Container preserved as 'sandbox-omp'" "$case_dir/output" || fail 'up lost the container preservation footer on failure'
tail -n 2 "$case_dir/output" | grep -Fxq '  Resume:  docker start -ai sandbox-omp' || fail 'up footer must offer resume'
rm "$case_dir/run-container"

unset OPENAI_API_KEY
: > "$case_dir/calls"
ps_lines=$'sandbox-omp\trunning\nsandbox-claude-code\tpaused\nsandbox-codex-old\texited'
FAKE_PS_LINES="$ps_lines" launch list
[[ $(grep -c '^ps ' "$case_dir/calls") == 1 ]] || fail 'list should call docker ps exactly once'
has_line output '  NAME           STATUS       CONTAINER'
has_line output '  omp            running      sandbox-omp'
has_line output '  claude-code    stopped      sandbox-claude-code'
has_line output "$(printf '  %-14s %-12s %s' codex '—' sandbox-codex)"
cp "$case_dir/output" "$case_dir/list-output"
FAKE_PS_LINES="$ps_lines" launch status
cmp -s "$case_dir/list-output" "$case_dir/output" || fail 'status without arguments must match list'
FAKE_PS_LINES=$'sandbox-omp\texited' launch status omp
has_line output $'sandbox-omp\texited\tsandbox-omp:magpie\t0B'
FAKE_PS_EXIT=1 reject list
grep -Fq 'Could not list Docker containers.' "$case_dir/output" || fail 'list must report a Docker listing failure'

FAKE_PS_LINES=$'sandbox-omp\texited' launch down omp --purge
has_line removed-container sandbox-omp
has_line removed-image sandbox-omp:magpie
if grep -q 'prune' "$case_dir/calls"; then fail 'down --purge pruned unrelated images'; fi
(
    source "$root/lib/common.sh"
    GATEWAY_URL='https://gateway.example/v1' GATEWAY_HOST='gateway.example'
    parse_http_url 'hTTps://[::FFFF:127.1.2.3]:4343/npm/' || fail 'parse_http_url rejected a valid IPv6 URL'
    [[ "$URL_SCHEME" == 'hTTps://' && "$URL_HOST" == '::ffff:127.1.2.3' && "$URL_PORT" == 4343 &&
       "$URL_PATH" == '/npm/' && "$URL_LOOPBACK" == true ]] || fail 'parse_http_url returned incorrect IPv6 URL components'
    parse_http_url 'http://Registry.EXAMPLE' || fail 'parse_http_url rejected a valid DNS URL'
    [[ "$URL_HOST" == 'registry.example' && -z "$URL_PORT" && -z "$URL_PATH" && "$URL_LOOPBACK" == false ]] \
        || fail 'parse_http_url returned incorrect DNS URL components'
    [[ "$GATEWAY_URL" == 'https://gateway.example/v1' && "$GATEWAY_HOST" == 'gateway.example' ]] \
        || fail 'parse_http_url changed the gateway URL or host'
    [[ $(strip_v1_suffix 'http://x/v1//') == 'http://x' ]] || fail 'strip_v1_suffix must remove trailing slashes and /v1'
    [[ $(strip_v1_suffix 'http://x/v1/v1/') == 'http://x/v1' ]] || fail 'strip_v1_suffix must remove only one /v1'
)
printf 'Fake Docker CLI tests passed.\n'

export HOME="$case_dir/container-home" OPENAI_BASE_URL="$url" MAGPIE_MODEL='custom/model-id' MAGPIE_API_KEY="$FAKE_KEY"
entry="$case_dir/context/sandbox-entry"
if command -v jq >/dev/null 2>&1; then
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
else
    printf 'OMP and Codex entrypoint tests skipped (jq is not installed on the test host).\n'
fi

bash "$entry" claude-code -c '
    [[ "$ANTHROPIC_BASE_URL" == "https://gateway.example:4343/nested/with%20space" &&
       "$ANTHROPIC_AUTH_TOKEN" == "$FAKE_KEY" && "$ANTHROPIC_MODEL" == "custom/model-id" &&
       "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" == 1 ]]
' || fail 'Claude Code environment'
OPENAI_BASE_URL='https://gateway.example:4343/nested/v1///' bash "$entry" claude-code -c '
    [[ "$ANTHROPIC_BASE_URL" == "https://gateway.example:4343/nested" ]]
' || fail 'Claude Code must strip all trailing slashes before /v1'
if bash "$entry" unknown -c 'exit 0' 2> "$case_dir/output"; then
    fail 'unknown entrypoint agent should fail'
fi
has_line output 'Unknown agent: unknown'
printf 'Container entrypoint tests passed.\n'
