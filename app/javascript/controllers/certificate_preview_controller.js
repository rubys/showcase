import { Controller } from "@hotwired/stimulus";
import * as pdfjsLib from "pdfjs-dist";

// Connects to data-controller="certificate-preview"
export default class extends Controller {
  static targets = [
    "canvas", "fileInput", "x", "y", "width", "height",
    "fontSize", "fontColor", "sampleName"
  ];

  static values = {
    workerSrc: String
  };

  connect() {
    // Set up PDF.js worker
    pdfjsLib.GlobalWorkerOptions.workerSrc =
      "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.0.379/build/pdf.worker.min.mjs";

    this.pdfDoc = null;
    this.imageData = null;
    this.isImage = false;
    this.isDragging = false;
    this.isResizing = false;
    this.dragStart = { x: 0, y: 0 };
    this.scale = 1;

    // Bind event listeners
    this.canvasTarget.addEventListener("mousedown", this.onMouseDown.bind(this));
    this.canvasTarget.addEventListener("mousemove", this.onMouseMove.bind(this));
    this.canvasTarget.addEventListener("mouseup", this.onMouseUp.bind(this));
    this.canvasTarget.addEventListener("mouseleave", this.onMouseUp.bind(this));
  }

  async fileSelected(event) {
    const file = event.target.files[0];
    if (!file) return;

    if (file.type === "application/pdf") {
      const arrayBuffer = await file.arrayBuffer();
      this.pdfDoc = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;
      this.isImage = false;
      await this.renderPreview();
    } else if (file.type.startsWith("image/")) {
      // Handle image files
      const img = new Image();
      img.onload = () => {
        this.imageData = img;
        this.isImage = true;
        this.pdfDoc = null;
        this.renderImagePreview();
      };
      img.src = URL.createObjectURL(file);
    }
  }

  renderImagePreview() {
    if (!this.imageData) return;

    const canvas = this.canvasTarget;
    const context = canvas.getContext("2d");

    // Scale to fit in a reasonable viewport (max 1200px wide)
    const maxWidth = 1200;
    let scale = 1;
    if (this.imageData.width > maxWidth) {
      scale = maxWidth / this.imageData.width;
    }

    canvas.width = this.imageData.width * scale;
    canvas.height = this.imageData.height * scale;
    this.scale = scale;

    // Draw the image
    context.drawImage(this.imageData, 0, 0, canvas.width, canvas.height);

    // Draw the text box overlay
    this.drawOverlay();
  }

  async renderPreview() {
    if (!this.pdfDoc) return;

    const page = await this.pdfDoc.getPage(1);
    const viewport = page.getViewport({ scale: 1.5 });

    // Set canvas dimensions
    const canvas = this.canvasTarget;
    const context = canvas.getContext("2d");
    canvas.height = viewport.height;
    canvas.width = viewport.width;

    // Store scale for coordinate conversion
    this.scale = 1.5;

    // Render PDF page
    await page.render({
      canvasContext: context,
      viewport: viewport
    }).promise;

    // Store the page for re-rendering
    this.page = page;
    this.viewport = viewport;

    // Draw the text box overlay
    this.drawOverlay();
  }

  async drawOverlay() {
    const canvas = this.canvasTarget;
    const ctx = canvas.getContext("2d");

    // Re-render the base image/PDF first to clear previous overlay
    if (this.isImage && this.imageData) {
      ctx.drawImage(this.imageData, 0, 0, canvas.width, canvas.height);
    } else if (this.page && this.viewport) {
      await this.page.render({
        canvasContext: ctx,
        viewport: this.viewport
      }).promise;
    } else {
      return;
    }

    // Get current values
    const x = parseInt(this.xTarget.value) * this.scale;
    const y = parseInt(this.yTarget.value) * this.scale;
    const width = parseInt(this.widthTarget.value) * this.scale;
    const height = parseInt(this.heightTarget.value) * this.scale;
    const fontSize = parseInt(this.fontSizeTarget.value) * this.scale;
    const fontColor = this.fontColorTarget.value;
    const sampleName = this.sampleNameTarget.value || "Student Name";

    // Draw semi-transparent rectangle
    ctx.fillStyle = "rgba(255, 165, 0, 0.3)";
    ctx.fillRect(x, canvas.height - y - height, width, height);

    // Draw border
    ctx.strokeStyle = "orange";
    ctx.lineWidth = 2;
    ctx.strokeRect(x, canvas.height - y - height, width, height);

    // Draw sample text
    ctx.fillStyle = this.getRGBColor(fontColor);
    ctx.font = `bold ${fontSize}px Times New Roman`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(
      sampleName,
      x + width / 2,
      canvas.height - y - height / 2
    );

    // Draw resize handle (bottom-right corner)
    ctx.fillStyle = "orange";
    ctx.fillRect(
      x + width - 10,
      canvas.height - y - height + height - 10,
      10,
      10
    );
  }

  getRGBColor(value) {
    const parts = value.split(' ').map(n => parseInt(n));
    return `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
  }

  onMouseDown(event) {
    if (!this.pdfDoc && !this.imageData) return;

    const rect = this.canvasTarget.getBoundingClientRect();
    // Account for CSS scaling - convert from displayed coordinates to canvas coordinates
    const scaleX = this.canvasTarget.width / rect.width;
    const scaleY = this.canvasTarget.height / rect.height;
    const mouseX = (event.clientX - rect.left) * scaleX;
    const mouseY = (event.clientY - rect.top) * scaleY;

    const x = parseInt(this.xTarget.value) * this.scale;
    const y = parseInt(this.yTarget.value) * this.scale;
    const width = parseInt(this.widthTarget.value) * this.scale;
    const height = parseInt(this.heightTarget.value) * this.scale;

    const boxY = this.canvasTarget.height - y - height;

    // Check if clicking on resize handle
    if (
      mouseX >= x + width - 10 &&
      mouseX <= x + width &&
      mouseY >= boxY + height - 10 &&
      mouseY <= boxY + height
    ) {
      this.isResizing = true;
      this.dragStart = { x: mouseX, y: mouseY };
      return;
    }

    // Check if clicking inside box for dragging
    if (
      mouseX >= x &&
      mouseX <= x + width &&
      mouseY >= boxY &&
      mouseY <= boxY + height
    ) {
      this.isDragging = true;
      this.dragStart = { x: mouseX - x, y: mouseY - boxY };
    }
  }

  onMouseMove(event) {
    if (!this.isDragging && !this.isResizing) {
      // Update cursor
      const rect = this.canvasTarget.getBoundingClientRect();
      const scaleX = this.canvasTarget.width / rect.width;
      const scaleY = this.canvasTarget.height / rect.height;
      const mouseX = (event.clientX - rect.left) * scaleX;
      const mouseY = (event.clientY - rect.top) * scaleY;

      const x = parseInt(this.xTarget.value) * this.scale;
      const y = parseInt(this.yTarget.value) * this.scale;
      const width = parseInt(this.widthTarget.value) * this.scale;
      const height = parseInt(this.heightTarget.value) * this.scale;
      const boxY = this.canvasTarget.height - y - height;

      if (
        mouseX >= x + width - 10 &&
        mouseX <= x + width &&
        mouseY >= boxY + height - 10 &&
        mouseY <= boxY + height
      ) {
        this.canvasTarget.style.cursor = "nwse-resize";
      } else if (
        mouseX >= x &&
        mouseX <= x + width &&
        mouseY >= boxY &&
        mouseY <= boxY + height
      ) {
        this.canvasTarget.style.cursor = "move";
      } else {
        this.canvasTarget.style.cursor = "default";
      }
      return;
    }

    const rect = this.canvasTarget.getBoundingClientRect();
    const scaleX = this.canvasTarget.width / rect.width;
    const scaleY = this.canvasTarget.height / rect.height;
    const mouseX = (event.clientX - rect.left) * scaleX;
    const mouseY = (event.clientY - rect.top) * scaleY;

    if (this.isDragging) {
      const newX = Math.max(0, mouseX - this.dragStart.x);
      const newY = this.canvasTarget.height - (mouseY - this.dragStart.y);

      this.xTarget.value = Math.round(newX / this.scale);
      this.yTarget.value = Math.round(newY / this.scale);
      this.drawOverlay();
    } else if (this.isResizing) {
      const x = parseInt(this.xTarget.value) * this.scale;
      const y = parseInt(this.yTarget.value) * this.scale;
      const boxY = this.canvasTarget.height - y;

      const newWidth = Math.max(50, mouseX - x);
      const newHeight = Math.max(20, boxY - mouseY);

      this.widthTarget.value = Math.round(newWidth / this.scale);
      this.heightTarget.value = Math.round(newHeight / this.scale);
      this.drawOverlay();
    }
  }

  onMouseUp(_event) {
    this.isDragging = false;
    this.isResizing = false;
  }

  updatePreview() {
    this.drawOverlay();
  }
}
