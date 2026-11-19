// AI writing's box (Web.Components.AIWriting): Enter sends the ask and Shift+Enter starts
// a new line, as in a chat. On a touch screen, return starts a new line and Ask sends,
// since a phone's keyboard has no Shift.
export const AskEnter = {
  mounted() {
    this.el.addEventListener("keydown", event => {
      if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
      if (window.matchMedia("(pointer: coarse)").matches) return
      event.preventDefault()
      this.el.form.requestSubmit()
    })
  },
}
