module PeopleHelper
  def entry_row_classes(entry, event, person)
    active_heats = entry.active_heats
    
    if active_heats.empty?
      "group line-through opacity-50"
    elsif event.strict_scoring && entry_excluded_by_strict_scoring?(entry, person, event)
      "group bg-gray-200"
    else
      "group"
    end
  end

  def heat_row_classes(heat)
    if heat.number < 0
      "group line-through opacity-50"
    else
      "group"
    end
  end

  def show_lead_column?(person)
    person.role != 'Leader'
  end

  def show_follow_column?(person)
    person.role != 'Follower'
  end

  def show_action_buttons?(person, event)
    person.type == "Student" || (person.type == "Professional" && event.pro_heats)
  end

  def judge_assignments_enabled?(event)
    event.assign_judges > 0 && Person.where(type: 'Judge').count > 1
  end

  def show_ballroom_selector?(event)
    event.ballrooms > 1 || Category.maximum(:ballrooms).to_i > 1
  end

  private

  def entry_excluded_by_strict_scoring?(entry, person, event)
    entry.level_id != person.level_id || 
    (event.track_ages && entry.age_id != person.age_id)
  end
end
