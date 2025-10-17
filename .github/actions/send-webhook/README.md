# Send Webhook Action

A GitHub Action for sending webhook notifications with HMAC signature validation, based on the [distributhor/workflow-webhook](https://github.com/distributhor/workflow-webhook) project.

## Features

- ✅ Multiple webhook types: JSON, form-urlencoded, or json-extended
- ✅ HMAC signature generation (SHA-1 and SHA-256)
- ✅ Multiple authentication methods: Basic, Bearer, Custom Headers
- ✅ Configurable timeouts and SSL verification
- ✅ Returns webhook response for downstream processing

## Usage

### Basic Example

```yaml
- name: Send webhook notification
  uses: MyCarrier-DevOps/admin/.github/actions/send-webhook@send-webhook/v1
  with:
    webhook_url: https://api.example.com/webhook
    webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
    data: |
      {
        "deployment": "production",
        "version": "${{ steps.version.outputs.tag }}"
      }
```

### Using Published Container Image

```yaml
- name: Send webhook notification
  uses: docker://ghcr.io/MyCarrier-DevOps/actions/send-webhook:v1
  with:
    webhook_url: https://api.example.com/webhook
    webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
    data: '{"status": "deployed"}'
```

### Advanced Example

```yaml
- name: Build webhook payload
  id: build-payload
  run: |
    payload=$(jq -n \
      --arg env "${{ inputs.environment }}" \
      --arg version "${{ steps.version.outputs.tag }}" \
      '{
        environment: $env,
        version: $version,
        timestamp: now
      }'
    )
    echo "payload=$payload" >> "$GITHUB_OUTPUT"

- name: Send authenticated webhook
  uses: MyCarrier-DevOps/admin/.github/actions/send-webhook@send-webhook/v1
  with:
    webhook_url: https://api.example.com/deployments
    webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
    webhook_auth: ${{ secrets.API_TOKEN }}
    webhook_auth_type: bearer
    timeout: 30
    max_time: 60
    data: ${{ steps.build-payload.outputs.payload }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `webhook_url` | The HTTP URI of the webhook endpoint | ✅ Yes | - |
| `webhook_secret` | Secret for HMAC signature generation | No | `webhook_url` |
| `webhook_auth` | Authentication credentials (username:password, token, or custom header) | No | - |
| `webhook_auth_type` | Authentication type: `basic`, `bearer`, or `header` | No | `basic` |
| `webhook_type` | Payload format: `json`, `form-urlencoded`, or `json-extended` | No | `json` |
| `data` | Additional JSON data to include in the webhook payload | No | - |
| `verbose` | Enable verbose curl output | No | `false` |
| `silent` | Suppress output (avoid IP leaking in public logs) | No | `false` |
| `timeout` | Connection timeout in seconds | No | - |
| `max_time` | Maximum request duration in seconds | No | - |
| `curl_opts` | Additional curl options | No | - |
| `verify_ssl` | Verify SSL certificates | No | `true` |
| `event_name` | Override default GitHub event name | No | `GITHUB_EVENT_NAME` |

## Outputs

| Output | Description |
|--------|-------------|
| `response-body` | The HTTP response body from the webhook endpoint |

## Authentication Methods

### Basic Authentication
```yaml
with:
  webhook_auth: "username:password"
  webhook_auth_type: basic
```

### Bearer Token
```yaml
with:
  webhook_auth: ${{ secrets.API_TOKEN }}
  webhook_auth_type: bearer
```

### Custom Header
```yaml
with:
  webhook_auth: "X-API-Key:${{ secrets.API_KEY }}"
  webhook_auth_type: header
```

## Webhook Payload Structure

### Default (JSON)
```json
{
  "event": "push",
  "repository": "owner/repo",
  "commit": "abc123...",
  "ref": "refs/heads/main",
  "head": "",
  "workflow": "Deploy",
  "requestID": "uuid-v4",
  "data": {
    // Your custom data here
  }
}
```

### Form URL Encoded
```
event=push&repository=owner/repo&commit=abc123&ref=refs/heads/main&requestID=uuid
```

### JSON Extended
Includes the complete GitHub event payload from `$GITHUB_EVENT_PATH`.

## Signature Headers

The action automatically generates and includes HMAC signatures:

- `X-Hub-Signature: sha1={signature}`
- `X-Hub-Signature-256: sha256={signature}`
- `X-GitHub-Delivery: {request-id}`
- `X-GitHub-Event: {event-name}`

## Version Pinning

### Recommended: Pin to Major Version
```yaml
uses: MyCarrier-DevOps/admin/.github/actions/send-webhook@send-webhook/v1
```

### Pin to Specific Version
```yaml
uses: MyCarrier-DevOps/admin/.github/actions/send-webhook@send-webhook/v1.2.3
```

### Use Latest (Not Recommended for Production)
```yaml
uses: MyCarrier-DevOps/admin/.github/actions/send-webhook@send-webhook/v1.0.5
```

## Development

### Building Locally
```bash
cd .github/actions/send-webhook
docker build -t send-webhook-action:local .
```

### Testing Locally
```bash
docker run --rm \
  -e GITHUB_EVENT_NAME=test \
  -e GITHUB_REPOSITORY=test/repo \
  -e GITHUB_SHA=abc123 \
  -e GITHUB_REF=refs/heads/main \
  -e GITHUB_HEAD_REF= \
  -e GITHUB_WORKFLOW=test \
  -e webhook_url=https://httpbin.org/post \
  -e webhook_secret=secret \
  -e data='{"test":"value"}' \
  send-webhook-action:local
```

## License

This action is based on [distributhor/workflow-webhook](https://github.com/distributhor/workflow-webhook).

## Changelog

See [Releases](../../releases?q=send-webhook) for version history.
