// Target size for raster images (px). WebP at 48px is ~300-600 bytes base64,
// small enough to survive a signed session cookie.
const SIZE = 48;

const AvatarUpload = {
  mounted() {
    const input = this.el.querySelector("[data-avatar-file-input]");
    const grid = this.el.querySelector("[data-avatar-grid]");
    if (!input || !grid) return;

    // Shift+click any avatar button in the grid to trigger the file picker
    grid.addEventListener("click", (e) => {
      if (!e.shiftKey) return;
      const btn = e.target.closest("button");
      if (!btn) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      input.click();
    }, true);

    input.addEventListener("change", () => {
      const file = input.files[0];
      if (!file) return;
      input.value = "";

      // GIFs must bypass canvas — drawing to canvas collapses all frames into
      // one, killing the animation. Pass the raw data URI straight through.
      if (file.type === "image/gif") {
        const reader = new FileReader();
        reader.onload = (ev) => {
          this.pushEvent("avatar_image_selected", { data_uri: ev.target.result });
        };
        reader.readAsDataURL(file);
        return;
      }

      // All other image types: resize via canvas and re-encode as WebP.
      const reader = new FileReader();
      reader.onload = (ev) => {
        const img = new Image();
        img.onload = () => {
          const scale = Math.min(SIZE / img.width, SIZE / img.height, 1);
          const w = Math.round(img.width * scale);
          const h = Math.round(img.height * scale);
          const canvas = document.createElement("canvas");
          canvas.width = w;
          canvas.height = h;
          canvas.getContext("2d").drawImage(img, 0, 0, w, h);
          this.pushEvent("avatar_image_selected", {
            data_uri: canvas.toDataURL("image/webp", 0.75),
          });
        };
        img.src = ev.target.result;
      };
      reader.readAsDataURL(file);
    });
  },
};

export default AvatarUpload;
