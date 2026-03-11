# Reply De-dup Guard

- Send only one user-visible reply per user turn.
- Before final send, verify no semantically duplicate draft was already sent.
- If a reply tag such as `[[reply_to_current]]` is used, it must be the first token of the only visible reply.
- Do not prepend a status sentence before the tagged reply body.
- On Telegram, compress first. Avoid multi-part replies unless the user explicitly wants the long version.
