#!/bin/sh
set -eu

local_env="${SRCROOT}/.env"
if [ -f "$local_env" ]; then
    set -a
    . "$local_env"
    set +a
fi

# Generate the build's Info.plist without changing the checked-in template.
plist="${SCRIPT_OUTPUT_FILE_0}"
/bin/cp "${SCRIPT_INPUT_FILE_0}" "$plist"

api_url="${API_BASE_URL:-}"
hosted_api_url="${HOSTED_API_BASE_URL:-}"
api_token="${API_TOKEN:-}"

if [ "$CONFIGURATION" = "Debug" ]; then
    if [ "$PLATFORM_NAME" = "iphonesimulator" ] && [ -z "$api_url" ]; then
        # Match the backend's IPv4 listener; localhost may reach another IPv6 server.
        api_url="http://127.0.0.1:3010"
    fi

    if [ "$PLATFORM_NAME" = "iphoneos" ] && [ -z "$api_url" ]; then
        if [ -n "$hosted_api_url" ]; then
            api_url="$hosted_api_url"
        else
            # Bonjour hostnames keep working when the Mac's Wi-Fi IP changes.
            local_hostname="$(/usr/sbin/scutil --get LocalHostName)" || local_hostname=""
            if [ -z "$local_hostname" ]; then
                echo "error: Cannot determine this Mac's local hostname. Set API_BASE_URL or HOSTED_API_BASE_URL." >&2
                exit 1
            fi
            api_url="http://${local_hostname}.local:3010"
        fi
    fi
elif [ -z "$api_url" ] && [ -n "$hosted_api_url" ]; then
    api_url="$hosted_api_url"
fi

if [ -n "$api_url" ]; then
    /usr/bin/plutil -replace API_BASE_URL -string "$api_url" "$plist"
fi

if [ -n "$api_token" ]; then
    /usr/bin/plutil -replace API_TOKEN -string "$api_token" "$plist"
fi

configured_url="$(/usr/libexec/PlistBuddy -c 'Print :API_BASE_URL' "$plist")"

# iOS 17+ requires an explicit ATS exception for an HTTP IPv4 override.
if [ "$CONFIGURATION" = "Debug" ]; then
    case "$configured_url" in
        http://*)
            /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$plist"
            /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string Connect to the Finance Tracker development server on your Mac over Wi-Fi." "$plist"
            api_host="${configured_url#http://}"
            api_host="${api_host%%/*}"
            api_host="${api_host%%:*}"
            case "$api_host" in
                [0-9]*.[0-9]*.[0-9]*.[0-9]*)
                    escaped_host="$(printf '%s' "$api_host" | /usr/bin/sed 's/\./\\./g')"
                    /usr/bin/plutil -replace "NSAppTransportSecurity.NSExceptionDomains.${escaped_host}" \
                        -json '{"NSExceptionAllowsInsecureHTTPLoads":true}' "$plist"
                    ;;
            esac
            ;;
    esac
fi

echo "Finance Tracker API ($CONFIGURATION / $PLATFORM_NAME): $configured_url"
