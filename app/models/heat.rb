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

  # scrutineering

  def self.rank_callbacks(number)
    scores = Score.joins(heat: :entry).where(heats: {number: number.to_f}, value: 1..).group(:entry_id).count.
      sort_by { |entry_id, count| count }.reverse.map { |entry_id, count| [Entry.find(entry_id), count] }.to_h
  end

  def self.rank_placement(number, majority)
    scores = Score.joins(heat: :entry).where(heats: {number: number.to_f}, value: 1..).
      group_by { |score| score.heat.entry_id }.map { |entry_id, scores| [entry_id, scores.map {|score| score.value.to_i}] }.to_h
    max_score = scores.values.flatten.max
    entry_map = Entry.includes(:lead, :follow).where(id: scores.keys).index_by(&:id)
    rankings = {}
    rank = 1
    examining = 1

    while !scores.empty? && examining <= max_score
      places = scores.map { |entry_id, scores| [entry_id, scores.count {|score| score <= examining}] }.
        select { |entry_id, count| count >= majority }

      groups = places.group_by { |entry_id, count| count }.sort_by { |count, entries| count }.
        map { |count, entries| [count, entries.map(&:first)] }.reverse

      groups.each do |count, entries|
        abort = false

        if entries.length == 1
          entry_id = entries.first
          rankings[entry_map[entry_id]] = rank
          scores.delete entry_id
          rank += 1
        else
          subscores = entries.map { |entry_id| [entry_id, scores[entry_id]] }.to_h
          totals = subscores.
            map {|entry_id, scores| [entry_id, scores.select {|score| score <= examining}.sum]}.
            group_by {|entry_id, score| score}.sort_by {|score, entries| score}.
            map { |score, entries| [score, entries.map(&:first)] }

          totals.each do |score, entries|
            if entries.length == 1
              entry_id = entries.first
              rankings[entry_map[entry_id]] = rank
              subscores.delete entry_id
              scores.delete entry_id
              rank += 1
            else
              max_score = subscores.values.flatten.max
              (examining..max_score).each do |column|
                focus = subscores.map { |entry_id, scores| [entry_id, scores.select {|score| score <= column}] }

                focus_places = focus.map { |entry_id, scores| [entry_id, scores.count] }.
                  group_by {|entry_id, count| count}.sort_by {|count, entries| count}.
                  map { |count, entries| [count, entries.map(&:first)] }.reverse

                focus_places.each do |count, entries|
                  if entries.length == 1
                    entry_id = entries.first
                    rankings[entry_map[entry_id]] = rank
                    subscores.delete entry_id
                    scores.delete entry_id
                    rank += 1
                  else
                    abort = true
                    break
                  end
                end

                break if subscores.empty?
              end
            end

            break if abort
          end

          break if abort
          next unless subscores.empty?
        end
      end

      examining += 1
    end

    rankings
  end
end
