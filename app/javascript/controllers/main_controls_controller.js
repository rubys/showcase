import { Controller } from "@hotwired/stimulus"

let mediaRecorder;

// Connects to data-controller="main-controls"
export default class extends Controller {
  disconnect() {
    console.log("MainControlsController disconnected");
  }
  
  connect() {
    // Set up basic variables for app
    const token = document.querySelector('meta[name="csrf-token"]').content;
    const record = document.querySelector(".record");
    const stop = document.querySelector(".stop");
    const soundClips = document.querySelector(".sound-clips");
    const canvas = document.querySelector(".visualizer");
    const mainSection = document.querySelector(".main-controls");

    // Disable stop button while not recording
    if (!mediaRecorder) stop.disabled = true;

    // Visualiser setup - create web audio api context and canvas
    let audioCtx;
    const canvasCtx = canvas.getContext("2d");

    // Main block for doing the audio recording
    if (navigator.mediaDevices.getUserMedia) {
      console.log("The mediaDevices.getUserMedia() method is supported.");

      const constraints = { audio: true };
      let chunks = [];

      let onSuccess = stream => {
        if (mediaRecorder) return;
        mediaRecorder ||= new MediaRecorder(stream, {
          mimeType: MediaRecorder.isTypeSupported("audio/mp4")
            ? "audio/mp4"
            : "audio/webm; codecs=opus",
        });

        visualize(stream);

        record.onclick = function () {
          const subjectSelect = document.querySelector("#subject-select");
          if (!subjectSelect.value) {
            alert("Please select a couple to record first.");
            return;
          }
          
          mediaRecorder.start();
          console.log(mediaRecorder.state);
          console.log("Recorder started.");
          record.style.background = "red";

          stop.disabled = false;
          record.disabled = true;
        };

        stop.onclick = function () {
          console.log("stop clicked");
          mediaRecorder.stop();
          console.log(mediaRecorder.state);
          console.log("Recorder stopped.");
          record.style.background = "";
          record.style.color = "";

          stop.disabled = true;
          record.disabled = false;
        };

        mediaRecorder.onstop = async function (e) {
          console.log("Last data to read (after MediaRecorder.stop() called).");

          // Get selected subject info
          const subjectSelect = document.querySelector("#subject-select");
          const selectedOption = subjectSelect.options[subjectSelect.selectedIndex];
          const subjectName = selectedOption.text;
          const heatInfo = document.querySelector('h1').textContent.trim();
          
          const clipName = prompt(
            "Enter a name for your recording?",
            `${subjectName} - ${heatInfo}`
          );

          const clipContainer = document.createElement("article");
          const clipLabel = document.createElement("p");
          const audio = document.createElement("audio");
          const deleteButton = document.createElement("button");

          clipContainer.classList.add("clip");
          audio.setAttribute("controls", "");
          deleteButton.textContent = "Delete";
          deleteButton.className = "delete";

          if (clipName === null) {
            clipLabel.textContent = `${subjectName} - ${heatInfo}`;
          } else {
            clipLabel.textContent = clipName;
          }

          clipContainer.appendChild(audio);
          clipContainer.appendChild(clipLabel);
          clipContainer.appendChild(deleteButton);
          clipContainer.style.opacity = 0.5;
          soundClips.appendChild(clipContainer);

          audio.controls = true;
          const blob = new Blob(chunks, { type: mediaRecorder.mimeType });
          chunks = [];
          const audioURL = window.URL.createObjectURL(blob);
          audio.src = audioURL;
          console.log("recorder stopped");

          try {
            let response = await fetch("/recordings/", {
              method: "POST",
              body: blob,
              headers: {
                "X-CSRF-Token": token,
                "Content-Type": mediaRecorder.mimeType,
                "Content-Disposition": "attachment; filename=\"" + encodeURIComponent(clipLabel.textContent) + "\""
              }
            });

            if (response.ok) {
              clipContainer.style.opacity = 1;
              audio.preload = "none";
              audio.type = mediaRecorder.mimeType;
              audio.src = response.url;
            } else {
              console.error("Failed to save recording");
              clipContainer.remove();
            }
          } catch (error) {
            console.error("Error saving recording:", error);
            clipContainer.remove();
          }

          window.URL.revokeObjectURL(audioURL);
        };

        mediaRecorder.ondataavailable = function (e) {
          chunks.push(e.data);
        };
      };

      let onError = function (err) {
        console.log("The following error occured: " + err);
        alert("Error accessing microphone: " + err);
      };

      navigator.mediaDevices.getUserMedia(constraints).then(onSuccess, onError);
    } else {
      console.log("MediaDevices.getUserMedia() not supported on your browser!");
      alert("Audio recording not supported in this browser!");
    }

    function visualize(stream) {
      if (!audioCtx) {
        audioCtx = new AudioContext();
      }

      const source = audioCtx.createMediaStreamSource(stream);

      const analyser = audioCtx.createAnalyser();
      analyser.fftSize = 2048;
      const bufferLength = analyser.frequencyBinCount;
      const dataArray = new Uint8Array(bufferLength);

      source.connect(analyser);

      draw();

      function draw() {
        const WIDTH = canvas.width;
        const HEIGHT = canvas.height;

        requestAnimationFrame(draw);

        analyser.getByteTimeDomainData(dataArray);

        canvasCtx.fillStyle = "rgb(200, 200, 200)";
        canvasCtx.fillRect(0, 0, WIDTH, HEIGHT);

        canvasCtx.lineWidth = 2;
        canvasCtx.strokeStyle = "rgb(0, 0, 0)";

        canvasCtx.beginPath();

        let sliceWidth = (WIDTH * 1.0) / bufferLength;
        let x = 0;

        for (let i = 0; i < bufferLength; i++) {
          let v = dataArray[i] / 128.0;
          let y = (v * HEIGHT) / 2;

          if (i === 0) {
            canvasCtx.moveTo(x, y);
          } else {
            canvasCtx.lineTo(x, y);
          }

          x += sliceWidth;
        }

        canvasCtx.lineTo(canvas.width, canvas.height / 2);
        canvasCtx.stroke();
      }
    }

    window.onresize = function () {
      canvas.width = mainSection.offsetWidth;
    };

    window.onresize();
  }
}