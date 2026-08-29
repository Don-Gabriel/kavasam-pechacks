# n8n guardian SMS setup

Kavasam uses n8n as the provider-neutral boundary between the consent gateway and a two-way SMS service. The Android app never contains an SMS-provider credential.

## Outbound workflow

1. Create an n8n **Webhook** node using `POST` and header authentication.
2. Use `X-Kavasam-Webhook-Secret` as the required header and the same value as the gateway's `N8N_WEBHOOK_SECRET` environment secret.
3. Add a **Switch** node on `{{$json.event}}`. Supported values are `guardian_enrollment` and `guardian_approval`.
4. Pass `{{$json.to}}` and `{{$json.message}}` to the selected two-way SMS provider's node or HTTP API.
5. Return HTTP `202` only after the provider accepts the message. Return a non-2xx response on failure so Kavasam can fail closed.
6. Copy the workflow's production webhook URL into the gateway's `N8N_WEBHOOK_URL` secret.

Kavasam also sends `reference`, `replyWebhookUrl`, and—for approval messages—`expiresInSeconds`. Do not add phone numbers or message bodies to n8n execution logs in production.

## Inbound reply workflow

1. Configure the SMS provider's inbound-message webhook to a second n8n **Webhook** node.
2. Normalize the provider payload into:

```json
{
  "senderPhone": "+919876543210",
  "message": "ACCEPT #4821"
}
```

3. POST the normalized JSON to the `replyWebhookUrl` received by the outbound workflow.
4. Add `X-Kavasam-Webhook-Secret` with the same secret value.
5. Return the Kavasam response to the SMS provider. An `unrecognized` response can be used for one corrective SMS; do not retry indefinitely.

## Production checks

- Use a dedicated two-way SMS number or sender approved by the provider.
- Complete TRAI DLT sender and template registration before sending production SMS in India.
- Disable or redact n8n execution-data retention for phone numbers and message bodies.
- Apply edge rate limits to guardian enrollment and approval endpoints.
- Keep `N8N_WEBHOOK_SECRET`, SMS credentials, and provider signing secrets only in n8n/hosting secret stores.
- Test opt-in, accept, reject, malformed reply, duplicate request, delivery failure, and five-minute timeout paths before a demo or release.
