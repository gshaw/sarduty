// Save image under each side of an ID card on its page (#CARDPR). On a phone it opens
// the share sheet, whose Save Image puts the picture in Photos; a download would land in
// Files. Anywhere else the link downloads as it is. The picture is fetched when the page
// opens, because the share sheet opens only straight from a tap.
export const SaveImage = {
  mounted() {
    if (!window.matchMedia("(pointer: coarse)").matches || !navigator.canShare) return

    fetch(this.el.href)
      .then((response) => response.blob())
      .then((blob) => {
        const file = new File([blob], this.el.getAttribute("download"), {type: blob.type})
        if (navigator.canShare({files: [file]})) this.file = file
      })
      .catch(() => {
        // No picture to share: the link downloads it instead.
      })

    this.el.addEventListener("click", (event) => {
      if (!this.file) return
      event.preventDefault()
      navigator.share({files: [this.file]}).catch(() => {
        // Closing the share sheet rejects; nothing to do.
      })
    })
  },
}
