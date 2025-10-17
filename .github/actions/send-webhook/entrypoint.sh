#!/bin/bash

set -o errtrace
trap 'echo "Error occurred on line ${BASH_LINENO[*]}"; exit 1' ERR

for var in "${!INPUT_@}"; do
  name="${var#INPUT_}"
  name_lower="${name,,}"
  value="${!var}"

  if [[ -z "${!name_lower+x}" ]]; then
    if [ "$fine" = true ]; then
      echo "INFO: Converting INPUT_${name}=$value to $name_lower=$value"
    fi
    export "$name_lower"="$value"
  else
    echo "WARN: Variable already exists with $(env | grep "${name_lower}=")"
  fi
done

if [ -n "$WEBHOOK_AUTH" ]; then
    webhook_auth=$WEBHOOK_AUTH
fi

if [ -n "$WEBHOOK_AUTH_TYPE" ]; then
    webhook_auth_type=$WEBHOOK_AUTH_TYPE
fi

if [ -n "$WEBHOOK_SECRET" ]; then
    webhook_secret=$WEBHOOK_SECRET
fi

if [ -n "$WEBHOOK_TYPE" ]; then
    webhook_type=$WEBHOOK_TYPE
fi

if [ -n "$WEBHOOK_URL" ]; then
    webhook_url=$WEBHOOK_URL
fi

if [ -n "$SILENT" ]; then
    silent=$SILENT
fi

if [ -n "$VERBOSE" ]; then
    verbose=$VERBOSE
fi

if [ -n "$VERIFY_SSL" ]; then
    verify_ssl=$VERIFY_SSL
fi

if [ -n "$TIMEOUT" ]; then
    timeout=$TIMEOUT
fi

if [ -n "$MAX_TIME" ]; then
    max_time=$MAX_TIME
fi

if [ -n "$CURL_OPTS" ]; then
    curl_opts=$CURL_OPTS
fi

if [ -n "$EVENT_NAME" ]; then
    event_name=$EVENT_NAME
fi

if [ -n "$DATA" ]; then
    data=$DATA
fi

urlencode() {
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "%s" "$c" ;;
            *) printf '%s' "$c" | xxd -p -c1 | while read -r ch; do printf '%%%s' "$ch"; done ;;
        esac
    done
}

urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

set -e

if [ -z "$webhook_url" ]; then
    echo "No webhook_url configured"
    exit 1
fi

if [ -z "$webhook_secret" ]; then
    webhook_secret=$webhook_url
fi

REQUEST_ID=$(uuidgen)

if [ "$silent" != true ]; then
    echo "Webhook Request ID: $REQUEST_ID"
fi

if [ -n "$event_name" ]; then
    EVENT_NAME=$event_name
else
    EVENT_NAME=$GITHUB_EVENT_NAME
fi

if [ -n "$webhook_type" ] && [ "$webhook_type" == "form-urlencoded" ]; then
    EVENT=$(urlencode "$EVENT_NAME")
    REPOSITORY=$(urlencode "$GITHUB_REPOSITORY")
    COMMIT=$(urlencode "$GITHUB_SHA")
    REF=$(urlencode "$GITHUB_REF")
    HEAD=$(urlencode "$GITHUB_HEAD_REF")
    WORKFLOW=$(urlencode "$GITHUB_WORKFLOW")

    CONTENT_TYPE="application/x-www-form-urlencoded"
    WEBHOOK_DATA="event=$EVENT&repository=$REPOSITORY&commit=$COMMIT&ref=$REF&head=$HEAD&workflow=$WORKFLOW&requestID=$REQUEST_ID"

    if [ -n "$data" ]; then
        WEBHOOK_DATA="${WEBHOOK_DATA}&${data}"
    fi
else
    CONTENT_TYPE="application/json"

    if [ -n "$webhook_type" ] && [ "$webhook_type" == "json-extended" ]; then
        RAW_FILE_DATA=$(cat "$GITHUB_EVENT_PATH")
        WEBHOOK_DATA=$(echo -n "$RAW_FILE_DATA" | jq -c '.')
    else
        WEBHOOK_DATA=$(jo event="$EVENT_NAME" repository="$GITHUB_REPOSITORY" commit="$GITHUB_SHA" ref="$GITHUB_REF" head="$GITHUB_HEAD_REF" workflow="$GITHUB_WORKFLOW")
    fi

    if [ -n "$data" ]; then
        CUSTOM_JSON_DATA=$(echo -n "$data" | jq -c '.')
        WEBHOOK_DATA=$(jq -s '.[0] * .[1]' <(echo "$WEBHOOK_DATA") <(jo requestID="$REQUEST_ID" data="$CUSTOM_JSON_DATA"))
    else
        WEBHOOK_DATA=$(jq -s '.[0] * .[1]' <(echo "$WEBHOOK_DATA") <(jo requestID="$REQUEST_ID"))
    fi
fi

WEBHOOK_SIGNATURE=$(echo -n "$WEBHOOK_DATA" | openssl dgst -sha1 -hmac "$webhook_secret" -binary | xxd -p)
WEBHOOK_SIGNATURE_256=$(echo -n "$WEBHOOK_DATA" | openssl dgst -sha256 -hmac "$webhook_secret" -binary | xxd -p | tr -d '\n')
WEBHOOK_ENDPOINT=$webhook_url

auth_type="basic"
if [ -n "$webhook_auth_type" ]; then
    case "$webhook_auth_type" in
        bearer|header)
            auth_type=$webhook_auth_type
            ;;
        *)
            auth_type="basic"
            ;;
    esac
fi

if [ -n "$webhook_auth" ] && [ "$auth_type" == "basic" ]; then
    WEBHOOK_ENDPOINT="-u $webhook_auth $webhook_url"
fi

options="--http1.1 --fail-with-body"

if [ "$verbose" = true ]; then
    options="$options -v -sS"
elif [ "$silent" = true ]; then
    options="$options -s"
else
    options="$options -sS"
fi

if [ "$verify_ssl" = false ]; then
    options="$options -k"
fi

if [ -n "$timeout" ]; then
    options="$options --connect-timeout $timeout"
fi

if [ -n "$max_time" ]; then
    options="$options --max-time $max_time"
fi

if [ -n "$curl_opts" ]; then
    options="$options $curl_opts"
fi

if [ "$verbose" = true ]; then
    echo "curl $options \\\n-H 'Content-Type: $CONTENT_TYPE' \\\n-H 'User-Agent: GitHub-Hookshot/$REQUEST_ID' \\\n-H 'X-Hub-Signature: sha1=$WEBHOOK_SIGNATURE' \\\n-H 'X-Hub-Signature-256: sha256=$WEBHOOK_SIGNATURE_256' \\\n-H 'X-GitHub-Delivery: $REQUEST_ID' \\\n-H 'X-GitHub-Event: $EVENT_NAME' \\\n-H 'Connection: close' \\\n--data '$WEBHOOK_DATA'"
fi

set +e

if [ -n "$webhook_auth" ] && [ "$auth_type" == "bearer" ]; then
    response=$(curl $options \
    -H "Authorization: Bearer $webhook_auth" \
    -H "Content-Type: $CONTENT_TYPE" \
    -H "User-Agent: GitHub-Hookshot/$REQUEST_ID" \
    -H "X-Hub-Signature: sha1=$WEBHOOK_SIGNATURE" \
    -H "X-Hub-Signature-256: sha256=$WEBHOOK_SIGNATURE_256" \
    -H "X-GitHub-Delivery: $REQUEST_ID" \
    -H "X-GitHub-Event: $EVENT_NAME" \
    -H "Connection: close" \
    --data "$WEBHOOK_DATA" $WEBHOOK_ENDPOINT)
elif [ -n "$webhook_auth" ] && [ "$auth_type" == "header" ]; then
    header_name=$(echo "$webhook_auth" | cut -d':' -f1)
    header_value=$(echo "$webhook_auth" | cut -d':' -f2-)
    if [ -z "$header_value" ]; then
        response=$(curl $options \
        -H "Authorization: $webhook_auth" \
        -H "Content-Type: $CONTENT_TYPE" \
        -H "User-Agent: GitHub-Hookshot/$REQUEST_ID" \
        -H "X-Hub-Signature: sha1=$WEBHOOK_SIGNATURE" \
        -H "X-Hub-Signature-256: sha256=$WEBHOOK_SIGNATURE_256" \
        -H "X-GitHub-Delivery: $REQUEST_ID" \
        -H "X-GitHub-Event: $EVENT_NAME" \
        -H "Connection: close" \
        --data "$WEBHOOK_DATA" $WEBHOOK_ENDPOINT)
    else
        response=$(curl $options \
        -H "$header_name: $header_value" \
        -H "Content-Type: $CONTENT_TYPE" \
        -H "User-Agent: GitHub-Hookshot/$REQUEST_ID" \
        -H "X-Hub-Signature: sha1=$WEBHOOK_SIGNATURE" \
        -H "X-Hub-Signature-256: sha256=$WEBHOOK_SIGNATURE_256" \
        -H "X-GitHub-Delivery: $REQUEST_ID" \
        -H "X-GitHub-Event: $EVENT_NAME" \
        -H "Connection: close" \
        --data "$WEBHOOK_DATA" $WEBHOOK_ENDPOINT)
    fi
else
    response=$(curl $options \
    -H "Content-Type: $CONTENT_TYPE" \
    -H "User-Agent: GitHub-Hookshot/$REQUEST_ID" \
    -H "X-Hub-Signature: sha1=$WEBHOOK_SIGNATURE" \
    -H "X-Hub-Signature-256: sha256=$WEBHOOK_SIGNATURE_256" \
    -H "X-GitHub-Delivery: $REQUEST_ID" \
    -H "X-GitHub-Event: $EVENT_NAME" \
    -H "Connection: close" \
    --data "$WEBHOOK_DATA" $WEBHOOK_ENDPOINT)
fi

CURL_STATUS=$?

echo "response-body<<$REQUEST_ID" >> "$GITHUB_OUTPUT"
echo "$response" >> "$GITHUB_OUTPUT"
echo "$REQUEST_ID" >> "$GITHUB_OUTPUT"

if [ "$verbose" = true ]; then
    echo "Webhook Response [$CURL_STATUS]:"
    echo "$response"
fi

exit $CURL_STATUS
