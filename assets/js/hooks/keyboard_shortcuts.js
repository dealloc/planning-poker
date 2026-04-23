const VOTE_KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "q", "w", "e"]

const KeyboardShortcuts = {
  mounted() {
    this._keydown = (e) => this.handleKey(e)
    window.addEventListener("keydown", this._keydown)
  },
  destroyed() {
    window.removeEventListener("keydown", this._keydown)
  },
  handleKey(e) {
    if (e.ctrlKey || e.altKey || e.metaKey) return
    const tag = document.activeElement?.tagName?.toLowerCase()
    if (tag === "input" || tag === "textarea" || tag === "select" || document.activeElement?.isContentEditable) return

    const key = e.key.toLowerCase()
    const ds = this.el.dataset
    const state = ds.state
    const isCreator = ds.isCreator === "true"
    const queueEmpty = ds.queueEmpty === "true"

    if (e.key === "?" || e.key === "/") {
      e.preventDefault()
      const modal = document.getElementById("shortcuts-modal")
      if (modal) modal.classList.toggle("hidden")
      return
    }

    if (e.key === "Escape") {
      const modal = document.getElementById("shortcuts-modal")
      if (modal && !modal.classList.contains("hidden")) {
        modal.classList.add("hidden")
        e.preventDefault()
      }
      return
    }

    if (state === "voting") {
      const idx = VOTE_KEYS.indexOf(key)
      if (idx !== -1) {
        e.preventDefault()
        const cardButtons = document.querySelectorAll("[id^='card-']")
        const btn = cardButtons[idx]
        if (btn) {
          const cardValue = btn.getAttribute("phx-value-card")
          if (cardValue) this.pushEvent("vote", { card: cardValue })
        }
        return
      }
    }

    if (!isCreator) return

    if ((key === " " || e.code === "Space" || key === "r") && state === "voting") {
      e.preventDefault()
      this.pushEvent("reveal", {})
      return
    }
    if (key === "v" && state === "revealed") {
      e.preventDefault()
      this.pushEvent("reset_round", {})
      return
    }
    if (key === "n" && state === "revealed" && !queueEmpty) {
      e.preventDefault()
      this.pushEvent("next_item", {})
      return
    }
    if (key === "a") {
      e.preventDefault()
      this.pushEvent("toggle_auto_reveal", {})
      return
    }
  }
}

export default KeyboardShortcuts
