const CharCounter = {
  mounted() {
    this.update()
    this.el.addEventListener("input", () => this.update())
  },
  update() {
    const max = parseInt(this.el.getAttribute("maxlength") || "2000", 10)
    const len = this.el.value.length
    const targetId = this.el.dataset.counterTarget
    const counter = targetId && document.getElementById(targetId)
    if (counter) counter.textContent = `${len} / ${max}`
  }
}

export default CharCounter
