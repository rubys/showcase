module ScoresHelper
  def heat_dance_slot_display(heat, slot, final)
    return unless heat.dance.heat_length
    
    slot_text = if !heat.dance.semi_finals
      "Dance #{slot} of #{heat.dance.heat_length}:"
    elsif !final
      "Semi-final #{slot} of #{heat.dance.heat_length}:"
    else
      slot_number = slot > heat.dance.heat_length ? slot - heat.dance.heat_length : slot
      "Final #{slot_number} of #{heat.dance.heat_length}:"
    end
    
    slot_text
  end

  def heat_multi_dance_names(heat, slot)
    slots = heat.dance.multi_children.group_by(&:slot)
    
    if slots.length > 1 && slots[slot]
      slots[slot].sort_by { |multi| multi.dance.order }.map { |multi| multi.dance.name }.join(' / ')
    elsif slots.values.last&.length == heat.dance.heat_length
      multi = slots.values.last.sort_by { |multi| multi.dance.order }[(slot - 1) % heat.dance.heat_length]
      multi&.dance&.name
    elsif slots.values.last
      slots.values.last.sort_by { |multi| multi.dance.order }.map { |multi| multi.dance.name }.join(' / ')
    end
  end

  def judge_backs_display(heats, unassigned, early)
    heats.map do |heat|
      color = if unassigned.include?(heat)
        "text-red-400"
      elsif early.include?(heat)
        "text-gray-400"
      else
        "text-black"
      end
      "<a href='##{dom_id heat}' class='#{color}'>#{heat.entry.lead.back}</a>"
    end.join(' ').html_safe
  end

  def scoring_instruction_text(heat, style, event)
    if heat.category == 'Solo'
      "Tab to or click on comments or score to edit.  Press escape or click elsewhere to save."
    elsif style != 'radio'
      scoring_drag_drop_instructions
    elsif event.open_scoring == '#'
      "Enter scores in the right most column.  Tab to move to the next entry."
    elsif event.open_scoring == '+'
      scoring_feedback_instructions
    else
      "Click on the <em>radio</em> buttons on the right to score a couple.  The last column, with a dash (<code>-</code>), means the couple hasn't been scored / didn't participate."
    end
  end

  def navigation_instruction_text(heat, event)
    base_text = "Clicking on the arrows at the bottom corners will advance you to the next or previous heats. Left and right arrows on the keyboard may also be used"
    
    suffix = if heat.category == 'Solo'
      " when not editing comments or score"
    elsif event.open_scoring == '#'
      " when not entering scores"
    else
      ""
    end
    
    "#{base_text}#{suffix}. Swiping left and right on mobile devices and tablets also work."
  end

  private

  def scoring_drag_drop_instructions
    <<~HTML.strip
      Scoring can be done multiple ways:
      <ul class="list-disc ml-4">
        <li>Drag and drop: Drag an entry box to the desired score.</li>
        <li>Point and click: Clicking on a entry back and then clicking on score.  Clicking on the back number again unselects it.</li>
        <li>Keyboard: tab to the desired entry back, then move it up and down using the keyboard.  Clicking on escape unselects the back.</li>
      </ul>
    HTML
  end

  def scoring_feedback_instructions
    <<~HTML.strip
      Buttons on the left are used to indicated areas where the couple did well and will show up as <span class="good mx-0"><span class="open-fb selected px-2 mx-0">green</span></span> when selected.</li>
      <li>Buttons on the right are used to indicate areas where the couple need improvement and will show up as <span class="bad mx-0"><span class="open-fb selected px-2 mx-0">red</span></span> when selected.
    HTML
  end
end
