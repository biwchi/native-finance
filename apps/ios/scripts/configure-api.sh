#!/bin/sh
set -eu

# Generate the build's Info.plist without changing the checked-in template.
plist="${SCRIPT_OUTPUT_FILE_0}"
/bin/cp "${SCRIPT_INPUT_FILE_0}" "$plist"

api_url="${API_BASE_URL:-}"

if [ "$CONFIGURATION" = "Debug" ]; then
    # Allow local HTTP and explain the iPhone's local-network permission prompt.
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string Connect to the Finance Tracker development server on your Mac over Wi-Fi." "$plist"

    if [ "$PLATFORM_NAME" = "iphonesimulator" ] && [ -z "$api_url" ]; then
        # Match the backend's IPv4 listener; localhost may reach another IPv6 server.
        api_url="http://127.0.0.1:3000"
    fi

    if [ "$PLATFORM_NAME" = "iphoneos" ] && [ -z "$api_url" ]; then
        # Bonjour hostnames keep working when the Mac's Wi-Fi IP changes.
        local_hostname="$(/usr/sbin/scutil --get LocalHostName)" || local_hostname=""
        if [ -z "$local_hostname" ]; then
            echo "error: Cannot determine this Mac's local hostname. Set the API_BASE_URL build setting to your Mac's reachable API URL." >&2
            exit 1
        fi
        api_url="http://${local_hostname}.local:3000"
    fi
fi

if [ -n "$api_url" ]; then
    /usr/bin/plutil -replace API_BASE_URL -string "$api_url" "$plist"
fi

configured_url="$(/usr/libexec/PlistBuddy -c 'Print :API_BASE_URL' "$plist")"

# iOS 17+ requires an explicit ATS exception for an HTTP IPv4 override.
if [ "$CONFIGURATION" = "Debug" ]; then
    case "$configured_url" in
        http://*)
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
