# Customize Feedback

There are a number of different options as to how heats are scored:

<div class="my-5 ml-10">
  <label for="event_open_scoring">Open scoring</label>
  <ul class="ml-6 list-none" style="list-style-type: none">
  <li class="my-2"><input type="radio" value="1" name="event[open_scoring]" id="event_open_scoring_1"> 1/2/3/F
  </li><li class="my-2"><input type="radio" value="G" name="event[open_scoring]" id="event_open_scoring_g"> GH/G/S/B
  </li><li class="my-2"><input type="radio" value="#" name="event[open_scoring]" id="event_open_scoring_"> Number (85, 95, ...)
  </li><li class="my-2"><input type="radio" value="+" name="event[open_scoring]" id="event_open_scoring_"> Feedback (Needs Work On / Great Job With)
  </li><li class="my-2"><input type="radio" value="&amp;" name="event[open_scoring]" id="event_open_scoring_"> Number (1-5) <b>and</b> Feedback
  </li><li class="my-2"><input type="radio" value="@" checked="checked" name="event[open_scoring]" id="event_open_scoring_"> GH/G/S/B <b>and</b> Feedback
  </li></ul>
</div>

And this results in the judge being presented with a page like the following:

<div class="ml-10">
      <div class="grid value w-full" data-value="G" style="grid-template-columns: 100px repeat(4, 1fr)">
        <div class="bg-gray-200 inline-flex justify-center items-center">Overall</div>
        <button class="open-fb"><abbr title="B">B</abbr><span>B</span></button>
        <button class="open-fb"><abbr title="S">S</abbr><span>S</span></button>
        <button class="open-fb selected"><abbr title="G">G</abbr><span>G</span></button>
        <button class="open-fb"><abbr title="GH">GH</abbr><span>GH</span></button>
      </div>
      <div class="grid good" data-value="T" style="grid-template-columns: 100px repeat(6, 1fr)">
        <div class="bg-gray-200 inline-flex justify-center items-center">Good</div>
        <button class="open-fb"><abbr title="Frame">F</abbr><span>Frame</span></button>
        <button class="open-fb"><abbr title="Posture">P</abbr><span>Posture</span></button>
        <button class="open-fb"><abbr title="Footwork">FW</abbr><span>Footwork</span></button>
        <button class="open-fb"><abbr title="Lead/​Follow">LF</abbr><span>Lead/​Follow</span></button>
        <button class="open-fb selected"><abbr title="Timing">T</abbr><span>Timing</span></button>
        <button class="open-fb"><abbr title="Styling">S</abbr><span>Styling</span></button>
      </div>
      <div class="grid bad" data-value="FW" style="grid-template-columns: 100px repeat(6, 1fr)">
        <div class="bg-gray-200 inline-flex justify-center items-center text-center">Needs Work</div>
        <button class="open-fb"><abbr title="Frame">F</abbr><span>Frame</span></button>
        <button class="open-fb"><abbr title="Posture">P</abbr><span>Posture</span></button>
        <button class="open-fb selected"><abbr title="Footwork">FW</abbr><span>Footwork</span></button>
        <button class="open-fb"><abbr title="Lead/​Follow">LF</abbr><span>Lead/​Follow</span></button>
        <button class="open-fb"><abbr title="Timing">T</abbr><span>Timing</span></button>
        <button class="open-fb"><abbr title="Styling">S</abbr><span>Styling</span></button>
      </div>
</div>

Up until now the buttons (Frame, Posture, Footwork, etc.) were determined by the program.  I've started work on providing the ability to chose add, reorder, and change what buttons will be shown, and therefore what feedback will be provided to students.  To configure buttons, go into settings and first select what type of scoring you would like (the top list above), and then select the advanced tab and if there is a _Feedback_ button you can click on it to make changes.  I'm working through the options one by one, so if there is an option you are interested in and it isn't yet supported, let me know.