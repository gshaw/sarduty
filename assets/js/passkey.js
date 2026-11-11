// Passkeys (#129). Binary values travel as unpadded base64url, as App.Accounts.WebAuthn
// writes and reads them.
//
// Both hooks fetch their options before the click, so the browser's prompt opens in the
// click itself: Safari opens WebAuthn only from a tap or click.

const toBytes = text => Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0))

const toText = buffer =>
  btoa(String.fromCharCode(...new Uint8Array(buffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")

// A person closing the browser's prompt, or a request this page stopped itself.
const quiet = error => error?.name === "NotAllowedError" || error?.name === "AbortError"

// The login page: offers this site's passkeys in the email box (conditional mediation)
// where the browser can, and on Use a passkey. The answer goes to /login/passkey through
// the hidden form named by data-form, so the browser follows the redirect and keeps the
// session cookie. Both ways share one challenge from /login/passkey/options.
export const PasskeyLogin = {
  mounted() {
    if (!window.PublicKeyCredential) {
      this.el.hidden = true
      return
    }
    this.form = document.getElementById(this.el.dataset.form)
    this.button = this.el.querySelector("button")
    this.button.addEventListener("click", () => this.ask(false))
    this.options = this.fetchOptions()
    this.offerInBox()
  },

  destroyed() {
    this.abort?.abort()
  },

  fetchOptions() {
    const token = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    return fetch("/login/passkey/options", {method: "POST", headers: {"x-csrf-token": token}})
      .then(response => (response.ok ? response.json() : Promise.reject(new Error("options"))))
      .then(options => ({...options, challenge: toBytes(options.challenge)}))
  },

  async offerInBox() {
    const ok = await PublicKeyCredential.isConditionalMediationAvailable?.().catch(() => false)
    if (ok) this.ask(true)
  },

  async ask(inBox) {
    this.abort?.abort()
    const abort = new AbortController()
    this.abort = abort
    let publicKey
    try {
      publicKey = await this.options
    } catch {
      // Fetched again for the next click.
      this.options = this.fetchOptions()
      if (!inBox) this.pushEvent("passkey-failed", {})
      return
    }
    try {
      const credential = await navigator.credentials.get({
        publicKey,
        signal: abort.signal,
        ...(inBox ? {mediation: "conditional"} : {}),
      })
      if (credential) this.submit(credential)
    } catch (error) {
      if (abort.signal.aborted) return
      if (!quiet(error)) this.pushEvent("passkey-failed", {})
      // Closing the prompt from the button offers passkeys in the box again.
      if (!inBox) this.offerInBox()
    }
  },

  submit(credential) {
    const response = credential.response
    const fields = {
      credential_id: toText(credential.rawId),
      authenticator_data: toText(response.authenticatorData),
      client_data_json: toText(response.clientDataJSON),
      signature: toText(response.signature),
      user_handle: response.userHandle ? toText(response.userHandle) : "",
      attachment: credential.authenticatorAttachment || "",
    }
    for (const [name, value] of Object.entries(fields)) {
      this.form.elements[`passkey[${name}]`].value = value
    }
    this.button.disabled = true
    this.button.textContent = "Logging in…"
    this.form.submit()
  },
}

// Account settings' Add a passkey button. The LiveView makes the challenge and checks
// what the browser made (Web.AccountLive); this only runs the browser's prompt.
export const PasskeyAdd = {
  mounted() {
    if (!window.PublicKeyCredential) {
      this.el.hidden = true
      return
    }
    this.label = this.el.textContent
    this.el.addEventListener("click", () => this.add())
    this.load()
  },

  load() {
    this.options = null
    this.pushEvent("passkey-options", {}, options => {
      this.options = {
        ...options,
        challenge: toBytes(options.challenge),
        user: {...options.user, id: toBytes(options.user.id)},
        excludeCredentials: options.excludeCredentials.map(c => ({...c, id: toBytes(c.id)})),
      }
    })
  },

  async add() {
    if (!this.options) return
    try {
      const credential = await navigator.credentials.create({publicKey: this.options})
      this.el.disabled = true
      this.el.textContent = "Adding…"
      this.pushEvent(
        "passkey-created",
        {
          attestation_object: toText(credential.response.attestationObject),
          client_data_json: toText(credential.response.clientDataJSON),
        },
        () => this.done(),
      )
    } catch (error) {
      if (!quiet(error)) this.pushEvent("passkey-failed", {name: error?.name || ""})
      this.done()
    }
  },

  done() {
    this.el.disabled = false
    this.el.textContent = this.label
    this.load()
  },
}
