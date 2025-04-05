class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry
  validates_associated :entry

  has_many :scores, dependent: :destroy
  has_one :solo, dependent: :destroy

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
  def self.rank_callbacks(number)
    scores = Score.joins(heat: :entry).where(heats: {number: number.to_f}, value: 1..).group(:entry_id).count.
      sort_by { |entry_id, count| count }.reverse.map { |entry_id, count| [Entry.find(entry_id), count] }.to_h
  end

  # Rules 2 through 4 apply to the judges, not to the evaluation of the scores

  # Rules 5-8: placement.  Note: optional parameters are for Rule 11 purposes
  def self.rank_placement(number, majority, entries=nil, max_score=nil)
    number = number.is_a?(Enumerable) ? number.map(&:to_f) : number.to_f

    # extract all scores for the given heat, grouped by entry_id
    scores = Score.joins(heat: :entry).where(heats: {number: number}, value: 1..).
      group_by { |score| score.heat.entry_id }.map { |entry_id, scores| [entry_id, scores.map {|score| score.value.to_i}] }.to_h

    scores.slice!(*entries.map(&:id)) if entries

    max_score ||= scores.values.flatten.max
    entry_map = Entry.includes(:lead, :follow).where(id: scores.keys).index_by(&:id)
    rankings = {}
    rank = 1

    # in each iteration or focused runoff, try to identify the next entry to be ranked
    runoff = lambda do |entries, examining|
      # find all entries that have a majority of scores less than or equal to the current place we are examining
      places = scores.select { |entry_id, scores| entries.include? entry_id }.
        map { |entry_id, scores| [entry_id, scores.count {|score| score <= examining}] }.
        select { |entry_id, count| count >= majority }

      # sort the entries by the number of scores that are less than or equal to the current place
      groups = places.group_by { |entry_id, count| count }.sort_by { |count, entries| count }.
        map { |count, entries| [count, entries.map(&:first)] }.reverse

      # Rules 5 (only one entry) and 8 (no entries) fall out naturally and need no special handling

      groups.each do |count, entries|
        if entries.length == 1
          # if there is only one entry in this group, we can assign it a rank (Rule 6)
          entry_id = entries.first
          rankings[entry_map[entry_id]] = rank
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
              rankings[entry_map[entry_id]] = rank
              scores.delete entry_id
              rank += 1
            elsif examining < max_score
              # if there are two or more entries in this group, we need to focus only on these entries
              # and examine the next place mark (Rule 7 part 2)
              runoff.call(entries, examining + 1)
            else
              # We have a tie, so we need to assign the same rank to all entries in this group
              # (rule 7 part 3)
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
    (1..max_score).each do |examining|
      break if scores.empty?
      runoff.call(scores.keys, examining)
    end

    # return the final rankings
    rankings
  end

  def self.rank_summaries(places, heats=[], majority=1)
    # Rule 9: sort by minimum total place marks
    initial_rankings = places.map {|couple, results| [couple, results.values.sum]}.
      group_by {|couple, total| total}.
      map {|total, couples| [total, couples.map(&:first)]}.
      sort_by {|total, couples| total}

    # Rule 10: break ties by the number of place marks
    place = 0
    runoff = lambda do |couples, examining|
      # find all entries that have a majority of scores less than or equal to the current place we are examining
      counts = couples.map { |couple| [couple, places[couple].values.count {|score| score <= examining}] }.
        group_by { |couple, count| count }.sort_by { |count, entries| count }.
        map { |count, entries| [count, entries.map(&:first)] }.reverse

      top = counts.first.last

      entries =
        if top.length == 1
          top
        elsif examining < place
          runoff.call(top, examining + 1)
        else
          # Rule 11
          entries = Entry.joins(:heats, :lead).where(heats: {number: heats}, lead: {back: top})
          placement = rank_placement(heats, majority, entries, examining - top.length + 1).
            select { |entry, rank| rank == 1 }

          if placement.length == 1
            placement.first.first.lead.back
          else
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

    result.to_h
  end
end
