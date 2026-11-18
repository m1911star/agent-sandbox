#!/usr/bin/env bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()   { printf '%b[✓]%b %s\n' "$GREEN" "$NC" "$*"; }
warn()   { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*"; }
error()  { printf '%b[✗]%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
header() { printf '\n%b═══ %s ═══%b\n\n' "$BOLD$CYAN" "$*" "$NC"; }

require_docker() {
    command -v docker >/dev/null 2>&1 || error "Docker not found. Install Docker, Colima, or OrbStack."
    DOCKER_OS=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null) || error "Docker daemon not running."
}

valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ipv4() {
    local octet='(0|[1-9][0-9]{0,2})' a b c d
    [[ "$1" =~ ^$octet(\.$octet){3}$ ]] || return 1
    IFS=. read -r a b c d <<< "$1"
    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 ))
}

expand_ipv6() {
    local address="$1" hex='[0-9A-Fa-f]{1,4}' head tail compact colons zeros a b c d
    if [[ "$address" == *:*.* ]]; then
        valid_ipv4 "${address##*:}" || return 1
        IFS=. read -r a b c d <<< "${address##*:}"
        printf -v tail '%x:%x' "$((a * 256 + b))" "$((c * 256 + d))"
        address="${address%:*}:$tail"
    fi

    if [[ "$address" == *::* ]]; then
        head="${address%%::*}"
        tail="${address#*::}"
        [[ -z "$head" || "$head" =~ ^$hex(:$hex)*$ ]] || return 1
        [[ -z "$tail" || "$tail" =~ ^$hex(:$hex)*$ ]] || return 1
        compact="$head${head:+${tail:+:}}$tail"
        colons="${compact//[^:]}"
        zeros=8
        [[ -z "$compact" ]] || zeros=$((7 - ${#colons}))
        (( zeros >= 1 )) || return 1
        address="$head"
        while (( zeros > 0 )); do
            address="${address}${address:+:}0"
            zeros=$((zeros - 1))
        done
        address="$address${tail:+:$tail}"
    fi

    [[ "$address" =~ ^$hex(:$hex){7}$ ]] || return 1
    printf '%s\n' "$address"
}

HOST_GATEWAY=host.docker.internal

parse_gateway_url() {
    local url="$1" LC_ALL=C scheme host port path expanded loopback=false
    local path_chars="[A-Za-z0-9._~!\$&'()*+,;=:@/-]"
    local pattern="^([Hh][Tt][Tt][Pp][Ss]?://)(\[[A-Fa-f0-9:.]+\]|[^/:]+)(:([0-9]{1,5}))?(/($path_chars|%[A-Fa-f0-9]{2})*)?$"
    local label='[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    [[ "$url" =~ $pattern ]] || return 1
    scheme="${BASH_REMATCH[1]}" host="${BASH_REMATCH[2]}" port="${BASH_REMATCH[4]}" path="${BASH_REMATCH[5]}"
    [[ -z "$port" ]] || valid_port "$port" || return 1

    GATEWAY_URL="$url"
    GATEWAY_HOST=$(printf '%s' "$host" | LC_ALL=C tr '[:upper:]' '[:lower:]') || return 1
    if [[ "$GATEWAY_HOST" == \[*\] ]]; then
        GATEWAY_HOST="${GATEWAY_HOST:1:${#GATEWAY_HOST}-2}"
        expanded=$(expand_ipv6 "$GATEWAY_HOST") || return 1
        if [[ "$expanded" =~ ^(0{1,4}:){7}0{0,3}1$ || "$expanded" =~ ^(0{1,4}:){5}ffff:7f[0-9a-f]{2}: ]]; then
            loopback=true
        fi
    else
        host="${GATEWAY_HOST%.}"
        if [[ "$host" =~ ^[0-9.]+$ ]]; then
            valid_ipv4 "$host" || return 1
            [[ "$host" != 127.* ]] || loopback=true
        else
            [[ ${#host} -le 253 && "$host" =~ ^$label(\.$label)*$ ]] || return 1
            case "$host" in
                localhost|*.localhost) loopback=true ;;
            esac
        fi
    fi

    if [[ "$loopback" == true ]]; then
        GATEWAY_HOST="$HOST_GATEWAY"
        GATEWAY_URL="$scheme$HOST_GATEWAY${port:+:$port}$path"
    fi
}

host_mapping() {
    case "$DOCKER_OS" in
        *Docker\ Desktop*|*[Oo]rb[Ss]tack*) return ;;
    esac

    local endpoint="${DOCKER_HOST:-}" colima_home="${COLIMA_HOME:-$HOME/.colima}" profile gw
    local colima_socket="unix://${colima_home%/}/"
    if [[ -z "$endpoint" || -n "${DOCKER_CONTEXT:-}" ]]; then
        endpoint=$(docker context show 2>/dev/null) && \
            endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}' "$endpoint" 2>/dev/null) || endpoint=""
    fi
    case "$endpoint" in
        "${colima_socket}docker.sock") profile=default ;;
        "$colima_socket"*/docker.sock)
            profile="${endpoint#"$colima_socket"}"
            profile="${profile%/docker.sock}"
            ;;
        *) profile="" ;;
    esac
    if [[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] && command -v colima >/dev/null 2>&1; then
        gw=$(colima --profile "$profile" ssh -- ip route show default 2>/dev/null | awk '/^default via / && !found++ {print $3}') || gw=""
        if valid_ipv4 "$gw"; then
            printf '%s\n' "$HOST_GATEWAY:$gw"
            return
        fi
    fi
    printf '%s\n' "$HOST_GATEWAY:host-gateway"
}

http_proxy_keys=(HTTP_PROXY http_proxy HTTPS_PROXY https_proxy)
other_proxy_keys=(ALL_PROXY all_proxy FTP_PROXY ftp_proxy)

network_args() {
    local proxy_port="$1" mapping proxy="" key no_proxy="localhost,127.0.0.1,::1,$HOST_GATEWAY"
    if [[ -n "$proxy_port" || "${GATEWAY_HOST%.}" == "$HOST_GATEWAY" ]]; then
        mapping=$(host_mapping)
        [[ -z "$mapping" ]] || SANDBOX_ARGS+=(--add-host "$mapping")
    fi
    if [[ -n "$proxy_port" ]]; then
        proxy="http://$HOST_GATEWAY:$proxy_port"
        info "Proxy: $proxy"
    fi
    if [[ "$GATEWAY_HOST" != "$HOST_GATEWAY" ]]; then
        no_proxy="$no_proxy,$GATEWAY_HOST"
        [[ "$GATEWAY_HOST" != *:* ]] || no_proxy="$no_proxy,[$GATEWAY_HOST]"
    fi

    # Explicit values override proxy defaults from the Docker client config.
    for key in "${http_proxy_keys[@]}"; do
        SANDBOX_ARGS+=(-e "$key=$proxy")
    done
    for key in "${other_proxy_keys[@]}"; do
        SANDBOX_ARGS+=(-e "$key=")
    done
    SANDBOX_ARGS+=(-e "NO_PROXY=$no_proxy" -e "no_proxy=$no_proxy")
}

container_exists() {
    local name="$1" names
    shift
    names=$(docker ps "$@" --format '{{.Names}}') || error "Could not list Docker containers."
    grep -Fxq -- "$name" <<< "$names"
}

build_image_if_needed() {
    if docker image inspect "$AGENT_IMAGE" >/dev/null 2>&1; then
        info "Image ready: $AGENT_IMAGE"
        return
    fi

    local key build_args=(--build-arg NO_PROXY= --build-arg no_proxy=)
    for key in "${http_proxy_keys[@]}" "${other_proxy_keys[@]}"; do
        build_args+=(--build-arg "$key=")
    done
    if [[ -n "${NPM_CONFIG_REGISTRY:-}" ]]; then
        build_args+=(--build-arg "NPM_CONFIG_REGISTRY=$NPM_CONFIG_REGISTRY")
    fi
    info "Building image and installing the agent..."
    COPYFILE_DISABLE=1 tar --format ustar -cf - -C "$AGENT_DIR" Dockerfile -C "$SANDBOX_ROOT/lib" sandbox-entry \
        | docker build "${build_args[@]}" -t "$AGENT_IMAGE" -
    info "Image built: $AGENT_IMAGE"
}

remove_container() {
    local name="$1"
    if container_exists "$name" -a; then
        docker rm -f "$name" >/dev/null
        info "Container removed: $name"
    else
        warn "No container found: $name"
    fi
}

remove_image() {
    local image="$1"
    if docker image inspect "$image" >/dev/null 2>&1; then
        docker image rm "$image" >/dev/null
        info "Image removed: $image"
    fi
}
