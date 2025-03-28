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

    extensions = cat.extensions.order(:start_heat)
    if !cat or cat.split == nil or extensions.empty?
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
    entries = Entry.includes(:lead, :follow).where(id: scores.keys).index_by(&:id)
    rankings = {}
    rank = 1
    
    while !scores.empty?
      places = scores.map { |entry_id, scores| [entry_id, scores.count {|score| score <= rank}] }.
        select { |entry_id, count| count >= majority }
      places.sort_by { |entry_id, count| count }.reverse.each do |entry_id, count|
        rankings[entries[entry_id]] = rank
        scores.delete entry_id
        rank += 1
      end
    end

    rankings
  end
end
