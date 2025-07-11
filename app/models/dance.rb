class Dance < ApplicationRecord
  normalizes :name, with: -> name { name.strip }

  belongs_to :open_category, class_name: 'Category', optional: true
  belongs_to :closed_category, class_name: 'Category', optional: true
  belongs_to :solo_category, class_name: 'Category', optional: true
  belongs_to :multi_category, class_name: 'Category', optional: true

  belongs_to :pro_open_category, class_name: 'Category', optional: true
  belongs_to :pro_closed_category, class_name: 'Category', optional: true
  belongs_to :pro_solo_category, class_name: 'Category', optional: true
  belongs_to :pro_multi_category, class_name: 'Category', optional: true

  has_many :heats, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :multi_children, dependent: :destroy, class_name: 'Multi', foreign_key: :parent_id
  has_many :multi_dances, dependent: :destroy, class_name: 'Multi', foreign_key: :dance_id

  validates :name, presence: true # , uniqueness: true
  validates :order, presence: true, uniqueness: true

  validate :name_unique

  def name_unique
    return if order < 0
    return unless name.present?
    return unless Dance.where(name: name, order: 0...).where.not(id: id).exists?
    errors.add(:name, 'already exists')
  end

  def freestyle_category
    open_category || closed_category || multi_category ||
    pro_open_category || pro_closed_category || pro_multi_category
  end

  def scrutineering
    scores = Score.where(heat: heats)
    slots = scores.distinct.order(:slot).pluck(:slot)
    judges = scores.distinct.order(:judge_id).pluck(:judge_id)
    dances = multi_children.includes(:dance).map { |m| [m.dance.name, m.slot] }.to_h
    entries = heats.includes(entry: :lead)
    numbers = heats.where.not(number: ..0).distinct.pluck(:number)

    if heats.length > 8 && heat_length
      slots = slots.select { |slot| slot > heat_length }
      dances = dances.select { |name, slot| slot > heat_length }
    elsif heat_length
      slots = slots.select { |slot| slot <= heat_length }
    end

    summary = {}
    entries.each do |heat|
      summary[heat.entry.lead.back] ||= {}
    end
    
    dances.each do |dance, slot|
      Heat.rank_placement(numbers, slot, judges.length/2+1).each do |entry, rank|
        summary[entry.lead.back][dance] = rank
      end
    end

    majority = judges.length * dances.length / 2 + 1

    ranks = Heat.rank_summaries(summary, numbers, slots, majority).to_a.sort.to_h

    # Convert back numbers to entry IDs for the return value
    entry_by_back = {}
    entries.each do |heat|
      entry_by_back[heat.entry.lead.back] = heat.entry_id
    end
    
    summary_by_entry_id = {}
    ranks_by_entry_id = {}
    
    summary.each do |back, dances|
      summary_by_entry_id[entry_by_back[back]] = dances
    end
    
    ranks.each do |back, rank|
      ranks_by_entry_id[entry_by_back[back]] = rank
    end

    return [summary_by_entry_id, ranks_by_entry_id]
  end
end
