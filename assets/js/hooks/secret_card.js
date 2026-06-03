// Alt+click on the ? card secretly votes 🎵 instead
const SecretCard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      if (!e.altKey && !e.optionKey) return

      const btn = e.target.closest("button[data-secret='true']")
      if (!btn) return

      e.preventDefault()
      e.stopImmediatePropagation()

      this.pushEvent("vote", { card: "🎵" })

      // Brief visual hint — a tiny music note floats up from the card
      const note = document.createElement("span")
      note.textContent = "🎵"
      note.style.cssText = `
        position: fixed;
        left: ${e.clientX}px; top: ${e.clientY}px;
        font-size: 24px; pointer-events: none; z-index: 9999;
        animation: secret-float 1s ease-out forwards;
      `

      const style = document.createElement("style")
      style.textContent = `
        @keyframes secret-float {
          from { opacity: 1; transform: translateY(0) scale(1); }
          to   { opacity: 0; transform: translateY(-60px) scale(1.5); }
        }
      `
      document.head.appendChild(style)
      document.body.appendChild(note)
      setTimeout(() => { note.remove(); style.remove() }, 1000)
    }, true)
  }
}

export default SecretCard
