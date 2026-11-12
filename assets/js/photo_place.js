// Add a photo (#1028, Web.MemberPhotoFormLive), and a team admin's check of a photo a
// member added (#1029, Web.MemberPhotoLive).
//
// PhotoPick: Take a photo and Select a photo open the page's one file input. Take a
// photo asks for a camera, which a phone honours and a computer ignores: the one facing
// the person (capture="user") for their own photo, or the one its button names
// (data-photo-capture="environment") for an activity's (#1032,
// Web.ActivityPhotoFormLive). Select a photo opens the phone's photos, or a file.
export const PhotoPick = {
  mounted() {
    this.el.addEventListener("click", event => {
      const button = event.target.closest("[data-photo-pick]")
      const input = this.el.querySelector("input[type=file]")
      if (!button || !input) return
      if (button.dataset.photoPick === "camera") input.setAttribute("capture", button.dataset.photoCapture || "user")
      else input.removeAttribute("capture")
      input.click()
    })
  },
}

// PhotoPlace: the photo in the square the ID card shows. Drag moves it, a pinch or the
// wheel zooms it, the buttons zoom and turn it a quarter, and from the keyboard the arrow
// keys move it and plus and minus zoom it. The photo always covers the square.
//
// What the server gets, in the form's hidden fields: `turns`, quarter turns clockwise,
// and the square in the turned photo: `x` and `y`, its centre as shares of the width and
// height, and `side`, as a share of the shorter side (Service.MemberPhoto.crop/3).
//
// Export for a post (#1032, part 9, Web.ActivityPhotoExportLive) places a box of the
// post's shape the same way: `data-ratio` is its width over its height, 1 for the
// square, and `side` is then a share of the largest box of that shape the photo holds
// (Service.PhotoExport.crop/3). It has no turns field and no Rotate.
export const PhotoPlace = {
  mounted() {
    this.frame = this.el.querySelector("[data-photo-frame]")
    this.img = this.frame.querySelector("img")
    this.minSide = parseFloat(this.el.dataset.minSide) || 0.2
    this.ratio = parseFloat(this.el.dataset.ratio) || 1
    this.state = this.startState()
    this.pointers = new Map()

    if (this.img.complete && this.img.naturalWidth) this.draw()
    else this.img.addEventListener("load", () => this.draw(), {once: true})

    this.resize = new ResizeObserver(() => this.draw())
    this.resize.observe(this.frame)

    this.frame.addEventListener("pointerdown", event => this.pointerDown(event))
    this.frame.addEventListener("pointermove", event => this.pointerMove(event))
    for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) {
      this.frame.addEventListener(name, event => this.pointers.delete(event.pointerId))
    }
    this.frame.addEventListener("wheel", event => {
      event.preventDefault()
      this.zoom(Math.exp(event.deltaY * 0.002))
    }, {passive: false})
    this.frame.addEventListener("keydown", event => this.keyDown(event))

    this.el.addEventListener("click", event => {
      const tool = event.target.closest("[data-photo-tool]")?.dataset.photoTool
      if (tool === "rotate") this.rotate()
      if (tool === "zoom-in") this.zoom(0.8)
      if (tool === "zoom-out") this.zoom(1.25)
    })
  },

  destroyed() {
    this.resize?.disconnect()
  },

  // Where the photo starts, from the hidden fields: the middle square, zoomed all the
  // way out, on Add a photo, or where the member placed it, for a team admin's check
  // (#1029). A field that is not a number takes the middle square's.
  startState() {
    const start = {turns: 0, x: 0.5, y: 0.5, side: 1}
    for (const name of Object.keys(start)) {
      const value = parseFloat(this.el.querySelector(`input[name="photo[${name}]"]`)?.value)
      if (Number.isFinite(value)) start[name] = value
    }
    start.turns = ((Math.round(start.turns) % 4) + 4) % 4
    return start
  },

  // The photo's size once turned.
  turned() {
    const {naturalWidth: width, naturalHeight: height} = this.img
    return this.state.turns % 2 === 1 ? {width: height, height: width} : {width, height}
  },

  // The largest box of the frame's shape the turned photo holds: for the square, the
  // shorter side.
  largest() {
    const {width, height} = this.turned()
    return width / height > this.ratio
      ? {width: height * this.ratio, height}
      : {width, height: width / this.ratio}
  },

  // Keeps the box inside the photo, and no closer than the closest zoom.
  clamp() {
    const state = this.state
    const {width, height} = this.turned()
    const largest = this.largest()
    state.side = Math.min(1, Math.max(this.minSide, state.side))
    const halfX = (state.side * largest.width) / 2 / width
    const halfY = (state.side * largest.height) / 2 / height
    state.x = Math.min(1 - halfX, Math.max(halfX, state.x))
    state.y = Math.min(1 - halfY, Math.max(halfY, state.y))
  },

  draw() {
    if (!this.img.naturalWidth) return
    this.clamp()
    const {turns, x, y, side} = this.state
    const {naturalWidth: w, naturalHeight: h} = this.img
    const {width, height} = this.turned()
    const largest = this.largest()
    const boxWidth = side * largest.width
    const boxHeight = side * largest.height
    // Screen px per photo px, and the box's corner in the turned photo.
    const scale = this.frame.clientWidth / boxWidth
    const left = x * width - boxWidth / 2
    const top = y * height - boxHeight / 2
    // Each quarter turn clockwise, moved back so the turned photo starts at 0, 0.
    const turn = [
      "",
      `translate(${h}px, 0) rotate(90deg)`,
      `translate(${w}px, ${h}px) rotate(180deg)`,
      `translate(0, ${w}px) rotate(270deg)`,
    ][turns]

    this.img.style.width = `${w}px`
    this.img.style.height = `${h}px`
    this.img.style.transform = `translate(${-left * scale}px, ${-top * scale}px) scale(${scale}) ${turn}`

    for (const [name, value] of Object.entries(this.state)) {
      const input = this.el.querySelector(`input[name="photo[${name}]"]`)
      if (input) input.value = value
    }
  },

  // Moves the photo by screen px: the square goes the other way over it.
  move(dx, dy) {
    const {width, height} = this.turned()
    const scale = this.frame.clientWidth / (this.state.side * this.largest().width)
    this.state.x -= dx / scale / width
    this.state.y -= dy / scale / height
    this.draw()
  },

  // Under 1 zooms in: the square takes less of the photo.
  zoom(factor) {
    this.state.side *= factor
    this.draw()
  },

  // A quarter turn clockwise, about the square's centre.
  rotate() {
    const {x, y} = this.state
    this.state.turns = (this.state.turns + 1) % 4
    this.state.x = 1 - y
    this.state.y = x
    this.draw()
  },

  pointerDown(event) {
    this.frame.setPointerCapture(event.pointerId)
    this.pointers.set(event.pointerId, {x: event.clientX, y: event.clientY})
  },

  pointerMove(event) {
    const last = this.pointers.get(event.pointerId)
    if (!last) return
    const now = {x: event.clientX, y: event.clientY}

    if (this.pointers.size === 1) {
      this.move(now.x - last.x, now.y - last.y)
    } else if (this.pointers.size === 2) {
      // A pinch: the distance to the other finger, before and after.
      const other = [...this.pointers.entries()].find(([id]) => id !== event.pointerId)[1]
      const before = Math.hypot(last.x - other.x, last.y - other.y)
      const after = Math.hypot(now.x - other.x, now.y - other.y)
      if (before > 0 && after > 0) this.zoom(before / after)
    }
    this.pointers.set(event.pointerId, now)
  },

  keyDown(event) {
    const step = (event.shiftKey ? 0.1 : 0.02) * this.frame.clientWidth
    const moves = {ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step]}
    if (moves[event.key]) this.move(...moves[event.key])
    else if (event.key === "+" || event.key === "=") this.zoom(0.8)
    else if (event.key === "-") this.zoom(1.25)
    else return
    event.preventDefault()
  },
}
