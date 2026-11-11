# Passkeys

A passkey is a second way to log in (#129), beside a code by email or text. Nobody has to
add one, and codes keep working for everyone. A passkey proves who someone is; what
they reach still comes from D4H, so a passkey login needs the same current member as a
code (`App.Accounts.may_log_in?/2`).

SAR Duty site admins try passkeys first: only they see Passkeys in account settings
(`App.Accounts.UserPasskey.allowed?/1`). The login page offers passkeys to everyone,
since it can't tell who is there. Opening passkeys to every account is that one function.
The follow-ups, an offer after a code login, Passkeys only, and a passkey login for
Adminland, wait on #1002.

## How it fits together

- **WebAuthn** is the wax_ library, wrapped by `App.Accounts.WebAuthn`. The relying party
  is the endpoint's host, `sarduty.com` in production, so a passkey made there works
  nowhere else. Every passkey is discoverable and needs the device unlocked.
- **Adding one** happens in account settings (`Web.AccountLive`). The `PasskeyAdd` hook
  (`assets/js/passkey.js`) asks the LiveView for options as the page mounts, so the
  browser's prompt opens in the click itself, as Safari needs.
  `App.Operation.AddPasskey` checks what the browser made, saves it, and emails the
  owner. The email is the alarm for a passkey someone else added.
- **Logging in** starts on the login page. The `PasskeyLogin` hook fetches a challenge
  from `POST /login/passkey/options`, which keeps it in the session. It offers passkeys
  in the email box (`autocomplete="username webauthn"`) and on Use a passkey, then posts
  the answer to `POST /login/passkey` through a hidden form, so the browser follows the
  redirect like any login. `Web.PasskeySessionController` takes the challenge out of the
  session before checking it, so each works once.
- **How long a login lasts** follows where the passkey is. One on the device itself
  (`authenticatorAttachment` "platform") keeps the login 60 days, like Remember me. One
  from a phone at another computer, or a security key, lasts until the browser closes,
  so a hall computer forgets you. There is no Remember me box for passkeys.
- **Events**: a passkey login is a Logged in event with `via: passkey`. Passkey added
  and Passkey removed are kept two years, like other changes to who can log in.

## Trying it in development

WebAuthn needs HTTPS or `localhost`, and the page's host must be the relying party. The
dev server at `https://sarduty.test` works on this Mac. A phone needs a host it trusts
over HTTPS, such as the Tailscale name, with the endpoint's `url` host set to match.
