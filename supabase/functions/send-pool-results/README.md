# send-pool-results Edge Function

Versendet eine personalisierte HTML-Mail an alle Pool-Teilnehmer wenn ein Pool abgeschlossen wird.

## Setup (wenn du Mail-Versand aktivieren willst)

1. **Resend Account** erstellen: https://resend.com
2. **Sender-Domain verifizieren** (oder onboarding@resend.dev für Tests)
3. **API Key** erstellen
4. **Supabase Secrets** setzen:
   ```bash
   supabase secrets set RESEND_API_KEY=re_xxx
   supabase secrets set FROM_EMAIL='PGA Pool <pool@deine-domain.com>'
   ```
5. **Function deployen**:
   ```bash
   supabase functions deploy send-pool-results
   ```

## Trigger

Die App ruft die Function automatisch auf wenn ein Pool abgeschlossen wird:

```javascript
await sb.functions.invoke('send-pool-results', {
  body: { pool_id: '...' }
});
```

## Status

**Vorbereitet, nicht deployed.** Die App ruft die Function bereits auf — der Aufruf failt aktuell silent (try/catch). Sobald du die Function deployst, läuft alles automatisch.
