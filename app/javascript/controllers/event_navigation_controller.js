import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="event-navigation"
export default class extends Controller {
  connect() {
    document.body.addEventListener("keydown", this.keydown);
    document.body.addEventListener("touchstart", this.touchstart);
    document.body.addEventListener("touchend", this.touchend);
  }

  disconnect() {
    document.body.removeEventListener("keydown", this.keydown);
    document.body.removeEventListener("touchstart", this.touchstart);
    document.body.removeEventListener("touchend", this.touchend);
  }

  keydown = event => {
    if (event.key == "ArrowRight") {
      let link = document.querySelector("a[rel=next]");
      if (link) link.click();
    } else if (event.key == "ArrowLeft") {
      let link = document.querySelector("a[rel=prev]");
      if (link) link.click();
    } else if (event.key == "ArrowUp") {
      let link = document.querySelector("a[rel=up]");
      if (link) link.click();
    } else if (event.key == "?") {
      let home = document.querySelector("a[rel=home]");
      if (!home) return;
      Turbo.visit(home.href + "env");
    }
    console.log("Key pressed:", event.key);
  };

  touchstart = event => {
    this.touchStart = event.touches[0];
  };

  touchend = event => {
    let direction = this.swipe(event);

    if (direction == "right") {
      let link = document.querySelector("a[rel=prev]");
      if (link) link.click();
    } else if (direction == "left") {
      let link = document.querySelector("a[rel=next]");
      if (link) link.click();
    } else if (direction == "up") {
      let link = document.querySelector("a[rel=up]");
      if (link) link.click();
    }
  };

  swipe(event) {
    if (!this.touchStart) return false;
    let stop = event.changedTouches[0];
    if (stop.identifier != this.touchStart.identifier) return false;

    let deltaX = stop.clientX - this.touchStart.clientX;
    let deltaY = stop.clientY - this.touchStart.clientY;

    let height = document.documentElement.clientHeight;
    let width = document.documentElement.clientWidth;

    if (Math.abs(deltaX) > width/2 && Math.abs(deltaY) < height/4) {
      return deltaX > 0 ? "right" : "left"; 
    } else if (Math.abs(deltaY) > height/2 && Math.abs(deltaX) < width/4) {
      return deltaY > 0 ? "down" : "up";
    } else {
      return false;
    }
  }

}
