import { Controller } from "@hotwired/stimulus"

let mediaRecorder;

// Connects to data-controller="recordings"
export default class extends Controller {
  disconnect() {
  }

  async deleteRecording(event) {
    event.preventDefault();
    
    const button = event.target;
    const form = button.closest('form');
    const clipContainer = button.closest('.clip');
    
    if (!confirm('Are you sure you want to delete this recording?')) {
      return;
    }
    
    try {
      const token = document.querySelector('meta[name="csrf-token"]').content;
      const response = await fetch(form.action, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': token,
          'Accept': 'application/json'
        }
      });
      
      if (response.ok) {
        clipContainer.remove();
      } else {
        console.error('Failed to delete recording');
        alert('Failed to delete recording. Please try again.');
      }
    } catch (error) {
      console.error('Error deleting recording:', error);
      alert('Error deleting recording. Please try again.');
    }
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
          record.style.background = "red";

          stop.disabled = false;
          record.disabled = true;
        };

        stop.onclick = function () {
          mediaRecorder.stop();
          record.style.background = "";
          record.style.color = "";

          stop.disabled = true;
          record.disabled = false;
        };

        mediaRecorder.onstop = async function () {

          // Get selected subject info
          const subjectSelect = document.querySelector("#subject-select");
          const selectedOption = subjectSelect.options[subjectSelect.selectedIndex];
          const subjectName = selectedOption.text;
          
          const clipContainer = document.createElement("article");
          const clipLabel = document.createElement("p");
          const audio = document.createElement("audio");
          const deleteButton = document.createElement("button");

          clipContainer.classList.add("clip");
          audio.setAttribute("controls", "");
          deleteButton.textContent = "Delete";
          deleteButton.className = "delete";
          deleteButton.onclick = () => {
            if (confirm('Are you sure you want to delete this recording?')) {
              clipContainer.remove();
            }
          };

          clipLabel.textContent = subjectName;

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

          try {
            // Get upload path from selected subject option
            const subjectSelect = document.querySelector("#subject-select");
            const selectedOption = subjectSelect.options[subjectSelect.selectedIndex];
            const uploadPath = selectedOption.dataset.uploadPath;
            
            if (!uploadPath) {
              throw new Error("Upload path not found for selected subject");
            }
            
            let response = await fetch(uploadPath, {
              method: "POST",
              body: blob,
              headers: {
                "X-CSRF-Token": token,
                "Content-Type": mediaRecorder.mimeType
              }
            });

            if (response.ok) {
              const result = await response.json();
              clipContainer.style.opacity = 1;
              audio.preload = "none";
              audio.type = mediaRecorder.mimeType;
              if (result.url) {
                audio.src = result.url;
              }
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
        console.error("The following error occured: " + err);
        alert("Error accessing microphone: " + err);
      };

      navigator.mediaDevices.getUserMedia(constraints).then(onSuccess, onError);
    } else {
      console.error("MediaDevices.getUserMedia() not supported on your browser!");
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