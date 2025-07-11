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
    entries = heats.includes(entry: :lead)
    numbers = heats.where.not(number: ..0).distinct.pluck(:number)

    # Use actual score slots to determine dance mappings
    # For semi-finals, use slots 1 to heat_length for individual dances
    dance_slots = if heats.length > 8 && heat_length
      # Finals: use slots > heat_length
      slots.select { |slot| slot > heat_length }
    else
      # Semi-finals or direct finals: use slots 1 to heat_length
      slots.select { |slot| slot <= (heat_length || Float::INFINITY) }
    end
    
    # Create dance name mapping based on multi_children and actual slots
    dance_names = {}
    multi_children.includes(:dance).each_with_index do |child, index|
      # Map to actual slot if available, otherwise use sequential slots
      actual_slot = dance_slots[index] || (index + 1)
      dance_names[actual_slot] = child.dance.name
    end

    summary = {}
    entries.each do |heat|
      summary[heat.entry.lead.back] ||= {}
    end
    
    # Get rankings for each dance slot
    dance_slots.each do |slot|
      dance_name = dance_names[slot] || "Dance #{slot}"
      rankings = Heat.rank_placement(numbers, slot, judges.length/2+1)
      rankings.each do |entry, rank|
        summary[entry.lead.back][dance_name] = rank
      end
    end

    # Filter summary to only include couples who have complete results (were called back to finals)
    finalists_summary = summary.select { |back, dance_results| !dance_results.empty? }
    
    # Only rank the finalists among themselves
    if finalists_summary.any?
      majority = judges.length * dance_slots.length / 2 + 1
      ranks = Heat.rank_summaries(finalists_summary, numbers, dance_slots, majority).to_a.sort.to_h
    else
      ranks = {}
    end

    # Convert back numbers to entry IDs for the return value
    entry_by_back = {}
    entries.each do |heat|
      entry_by_back[heat.entry.lead.back] = heat.entry_id
    end
    
    summary_by_entry_id = {}
    ranks_by_entry_id = {}
    
    # Only include finalists in the results
    finalists_summary.each do |back, dances|
      summary_by_entry_id[entry_by_back[back]] = dances
    end
    
    ranks.each do |back, rank|
      ranks_by_entry_id[entry_by_back[back]] = rank
    end

    return [summary_by_entry_id, ranks_by_entry_id]
  end
end
