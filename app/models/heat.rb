class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry
  validates_associated :entry

  has_many :scores, dependent: :destroy
  has_one :solo, dependent: :destroy
  has_many :recordings, dependent: :destroy

  attr_accessor :child_dance_name

  def number
    return @number if @number
    value = super
    value = 0 if value.nil?
    @number = value.to_i == value ? value.to_i : value
  end

  def number= value
    @number = nil
    super value
  end

  def dance_category
    cat = if dance.heat_length or category == 'Multi'
      entry.pro ? dance.pro_multi_category || dance.multi_category : dance.multi_category
    elsif category == "Open"
      entry.pro ? dance.pro_open_category || dance.open_category : dance.open_category
    elsif category == "Solo"
      solo.category_override || (entry.pro ? dance.pro_solo_category || dance.solo_category : dance.solo_category)
    else
      dance.closed_category
    end

    return unless cat
    return cat if cat.split.blank?

    extensions = cat.extensions.order(:start_heat)
    if extensions.empty?
      cat
    elsif extensions.first.start_heat == nil or number == nil
      cat
    elsif number < extensions.first.start_heat
      cat
    else
      extensions.reverse.find { |ext| number >= ext.start_heat } || cat
    end
  end

  def lead
    entry.lead
  end

  def follow
    entry.follow
  end

  def partner(person)
    entry.partner(person)
  end

  def partners(person)
    return [ entry.partner(person) ].compact if category != "Solo"

    people = [ entry.lead, entry.follow ] + solo.formations.includes(:person).to_a.flat_map(&:person)
    people -= [ person ]
    people.compact.uniq.sort_by { |p| p.name }
  end

  def subject
    entry.subject
  end

  def level
    entry.level
  end

  def studio
    subject.studio
  end

  def back
    entry.lead.back
  end

  # scrutineering: https://www.dancepartner.com/articles/dancesport-skating-system.asp

  # Rule 1: callbacks
  def self.rank_callbacks(number, slots=nil)
    scores = Score.joins(heat: :entry).where(heats: {number: number.to_f}, slot: slots, value: 1..).group(:entry_id).count.
      sort_by { |entry_id, count| count }.reverse.map { |entry_id, count| [Entry.find(entry_id), count] }.to_h
  end

  # Rules 2 through 4 apply to the judges, not to the evaluation of the scores

  # Rules 5-8: placement.  Note: optional parameters are for Rule 11 purposes
  def self.rank_placement(number, slots, majority, entries=nil, examine=nil, with_explanations: false, entry_map: nil)
    number = number.is_a?(Enumerable) ? number.map(&:to_f) : number.to_f
    explanations = with_explanations ? [] : nil

    # extract all scores for the given heat, grouped by entry_id
    scores = Score.joins(heat: :entry).where(heats: {number: number}, slot: slots, value: 1..).
      group_by { |score| score.heat.entry_id }.map { |entry_id, scores| [entry_id, scores.map {|score| score.value.to_i}] }.to_h

    scores.slice!(*entries.map(&:id)) if entries

    max_score = examine&.last || scores.values.flatten.max
    entry_map ||= Entry.includes(:lead, :follow).where(id: scores.keys).index_by(&:id)
    rankings = {}
    rank = 1
    
    if explanations
      explanations << "Starting single dance placement calculation (Rules 5-8)"
      explanations << "Found #{scores.count} competitors with marks"
      explanations << "Majority required: #{majority} marks"
    end

    # in each iteration or focused runoff, try to identify the next entry to be ranked
    runoff = lambda do |entries, examining, focused = false|
      if explanations && !focused
        explanations << "\nExamining place #{examining}:"
      end
      
      # find all entries that have a majority of scores less than or equal to the current place we are examining
      places = scores.select { |entry_id, scores| entries.include? entry_id }.
        map { |entry_id, scores| [entry_id, scores.count {|score| score <= examining}] }.
        select { |entry_id, count| count >= majority }
        
      if explanations
        if places.empty?
          explanations << "  - No competitors have a majority (#{majority} marks) at place #{examining}"
        else
          places.each do |entry_id, count|
            entry = entry_map[entry_id]
            explanations << "  - ##{entry.lead.back}: #{count} marks for place #{examining} or better"
          end
        end
      end

      # sort the entries by the number of scores that are less than or equal to the current place
      groups = places.group_by { |entry_id, count| count }.sort_by { |count, entries| count }.
        map { |count, entries| [count, entries.map(&:first)] }.reverse

      # Rules 5 (only one entry) and 8 (no entries) fall out naturally and need no special handling
      
      if explanations && groups.empty?
        explanations << "  Rule 8: No action taken - continuing to next place"
      end

      groups.each do |count, entries|
        if entries.length == 1
          # if there is only one entry in this group, we can assign it a rank (Rule 6)
          entry_id = entries.first
          entry = entry_map[entry_id]
          if explanations
            explanations << "  Rule 6: ##{entry.lead.back} has clear majority (#{count} marks) - assigned rank #{rank}"
          end
          rankings[entry] = rank
          scores.delete entry_id
          rank += 1
        else
          # if two or more couples have an equal majority of scores, add together the place marks 
          subscores = entries.map { |entry_id| [entry_id, scores[entry_id]] }.to_h
          totals = subscores.
            map {|entry_id, scores| [entry_id, scores.select {|score| score <= examining}.sum]}.
            group_by {|entry_id, score| score}.sort_by {|score, entries| score}.
            map { |score, entries| [score, entries.map(&:first)] }

          totals.each do |score, entries|
            # if there is only one entry in this group, we can assign it a rank (Rule 7 part 1)
            if entries.length == 1
              entry_id = entries.first
              entry = entry_map[entry_id]
              if explanations
                explanations << "  Rule 7(a): ##{entry.lead.back} has lowest sum (#{score}) - assigned rank #{rank}"
              end
              rankings[entry] = rank
              scores.delete entry_id
              rank += 1
            elsif examining < max_score
              # if there are two or more entries in this group, we need to focus only on these entries
              # and examine the next place mark (Rule 7 part 2)
              if explanations
                entry_backs = entries.map { |id| "##{entry_map[id].lead.back}" }.join(", ")
                explanations << "  Rule 7(b): Tie between #{entry_backs} (sum=#{score}) - examining next place"
              end
              runoff.call(entries, examining + 1, true)
            else
              # We have a tie, so we need to assign the same rank to all entries in this group
              # (rule 7 part 3)
              if explanations
                entry_backs = entries.map { |id| "##{entry_map[id].lead.back}" }.join(", ")
                tied_rank = rank + (entries.length-1) / 2.0
                explanations << "  Rule 7(c): Unbreakable tie between #{entry_backs} - all assigned rank #{tied_rank}"
              end
              entries.each do |entry_id|
                rankings[entry_map[entry_id]] = rank + (entries.length-1) / 2.0
                scores.delete entry_id
              end
              rank += entries.length
            end
          end
        end
      end
    end

    # Iterate over the rankings, attempting to identify the next entry to be ranked
    # * Rules 5, 6, 7 (part 1) will identify exactly one entry to be ranked
    # * Rule 7 (part 2 and 3) will identify two or more entries to be ranked
    # * Rule 8 will identify no entries to be ranked
    (examine || (1..max_score)).each do |examining|
      break if scores.empty?
      runoff.call(scores.keys, examining)
    end

    # return the final rankings
    if explanations
      explanations << "\nFinal single dance rankings determined"
      return [rankings, explanations]
    else
      rankings
    end
  end

  def self.rank_summaries(places, heats=[], slots=nil, majority=1, with_explanations: false)
    explanations = with_explanations ? [] : nil
    
    if explanations
      explanations << "Starting multi-dance compilation (Rules 9-11)"
      explanations << "Processing #{places.count} finalists across #{places.values.first&.count || 0} dances"
    end
    
    # Rule 9: sort by minimum total place marks
    initial_rankings = places.map {|couple, results| [couple, results.values.sum]}.
      group_by {|couple, total| total}.
      map {|total, couples| [total, couples.map(&:first)]}.
      sort_by {|total, couples| total}
      
    if explanations
      explanations << "\nRule 9: Initial ranking by sum of placements:"
      initial_rankings.each do |total, couples|
        couple_list = couples.map { |c| "##{c}" }.join(", ")
        explanations << "  Sum #{total}: #{couple_list}"
      end
    end

    # Rule 10: break ties by the number of place marks
    place = 0
    runoff = lambda do |couples, examining, tie_level = 0|
      if explanations && tie_level == 0
        couple_list = couples.map { |c| "##{c}" }.join(", ")
        explanations << "\nRule 10: Breaking tie between #{couple_list} at place #{examining}"
      end
      
      # find all entries that have a majority of scores less than or equal to the current place we are examining
      counts = couples.map { |couple| [couple, places[couple].values.count {|score| score <= examining}] }.
        group_by { |couple, count| count }.sort_by { |count, entries| count }.
        map { |count, entries| [count, entries.map(&:first)] }.reverse

      if explanations
        counts.each do |count, group_couples|
          couple_list = group_couples.map { |c| "##{c}" }.join(", ")
          explanations << "  #{count} marks at place #{examining} or better: #{couple_list}"
        end
      end
      
      top = counts.first.last

      entries =
        if top.length == 1
          if explanations
            explanations << "  Winner: ##{top.first} (most marks at place #{examining})"
          end
          top
        elsif examining < place
          if explanations
            explanations << "  Continuing tie-break at next place level"
          end
          runoff.call(top, examining + (counts.length == 1 ? 1 : 0), tie_level + 1)
        else
          # Rule 11
          if explanations
            explanations << "  Rule 11: Head-to-head comparison needed for #{top.map{|c| "##{c}"}.join(", ")}"
          end
          entries = Entry.joins(:heats, :lead).where(heats: {number: heats}, lead: {back: top}).all.uniq
          examine = (examining - top.length + 1.. examining)
          placement = rank_placement(heats, slots, majority, entries, examine).
            select { |entry, rank| rank == 1 }

          if placement.length == 1
            winner_back = placement.first.first.lead.back
            if explanations
              explanations << "    Head-to-head winner: ##{winner_back}"
            end
            winner_back
          else
            if explanations
              explanations << "    Unbreakable tie - all tied at this position"
            end
            Set.new(top)
          end
        end

      entries = [ entries ] unless entries.is_a?(Enumerable)

      remaining = couples - entries.to_a

      if remaining.empty?
        entries
      else
        [entries, runoff.call(remaining, examining + 1)].flatten
      end
    end

    place = 0
    revised_rankings = initial_rankings.map do |total, couples|
      examining = place + 1
      place += couples.length
      if couples.length == 1
        couples.first
      else
        runoff.call(couples, examining)
      end
    end.flatten

    # Identify the placement of each couple, handling ties
    place = 1
    result = []
    revised_rankings.map do |couples|
      if couples.is_a?(Set)
        couples.each {|couple| result << [couple, place] }
        place += couples.length
      else
        result << [couples, place]
        place += 1
      end
    end

    final_result = result.to_h
    
    if explanations
      explanations << "\nFinal multi-dance rankings:"
      final_result.each do |couple, rank|
        explanations << "  ##{couple}: #{rank}"
      end
      return [final_result, explanations]
    else
      final_result
    end
  end

  def display_dance_name
    if child_dance_name
      "#{dance.name} - #{child_dance_name}"
    else
      dance.name
    end
  end
end
