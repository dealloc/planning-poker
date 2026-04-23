const EmojiThrow = {
  mounted() {
    this.handleEvent("download_file", ({ filename, content, mime_type }) => {
      const blob = new Blob([content], { type: mime_type })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = filename
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
    })

    this.handleEvent("emoji_thrown", ({ from, to, emoji, target_el }) => {
      const fromEl = document.getElementById(`participant-${from}`)
      const toEl = document.getElementById(target_el)
      if (!fromEl || !toEl) return

      const fromRect = fromEl.getBoundingClientRect()
      const toRect = toEl.getBoundingClientRect()

      const el = document.createElement("div")
      el.textContent = emoji
      el.style.cssText = [
        "position:fixed",
        `left:${fromRect.left + fromRect.width / 2}px`,
        `top:${fromRect.top + fromRect.height / 2}px`,
        "font-size:2rem",
        "pointer-events:none",
        "z-index:9999",
        "transform:translate(-50%,-50%)",
        "transition:left 0.8s ease-in-out, top 0.8s ease-in-out, opacity 0.2s ease 0.7s",
        "will-change:left,top,opacity"
      ].join(";")

      document.body.appendChild(el)

      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          el.style.left = `${toRect.left + toRect.width / 2}px`
          el.style.top = `${toRect.top + toRect.height / 2}px`
          el.style.opacity = "0"
        })
      })

      setTimeout(() => el.remove(), 1100)
    })
  }
}

export default EmojiThrow
