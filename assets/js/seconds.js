// The seconds an AI writing ask has run, after Thinking… (Web.Components.AIWriting), so a
// long first draft shows it's still going. It counts from when the line appears.
export const Seconds = {
  mounted() {
    const start = Date.now()
    this.timer = setInterval(() => {
      this.el.textContent = `${Math.floor((Date.now() - start) / 1000)}s`
    }, 1000)
  },
  destroyed() {
    clearInterval(this.timer)
  },
}
