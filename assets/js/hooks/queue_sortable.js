const QueueSortable = {
  mounted() {
    this._sortable = new window.Sortable(this.el, {
      animation: 150,
      ghostClass: "opacity-40",
      handle: ".drag-handle",
      onEnd: ({ oldIndex, newIndex }) => {
        if (oldIndex === newIndex) return
        const ids = Array.from(this.el.children).map(el => el.dataset.id)
        this.pushEvent("reorder_queue", { ids })
      }
    })
  },
  updated() {},
  destroyed() {
    this._sortable.destroy()
  }
}

export default QueueSortable
