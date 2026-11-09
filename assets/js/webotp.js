// Chrome on Android fills a texted code only when the page asks for it (WebOTP). The
// text's last line, "@sarduty.com #48291375", says which site the code is for. Safari
// doesn't have WebOTP: iOS reads that same line itself. The code is filled, not sent,
// so the person still picks "Remember me" and taps Log in, as on an iPhone.
export const WebOTP = {
  mounted() {
    if (!("OTPCredential" in window)) return
    this.abort = new AbortController()
    navigator.credentials
      .get({otp: {transport: ["sms"]}, signal: this.abort.signal})
      .then((otp) => {
        const input = this.el.closest("form").querySelector('input[autocomplete="one-time-code"]')
        input.value = otp.code
        input.dispatchEvent(new Event("input", {bubbles: true}))
      })
      .catch(() => {})
  },
  destroyed() {
    this.abort?.abort()
  },
}
