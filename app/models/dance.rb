class Dance < ApplicationRecord
  normalizes :name, with: -> name { name.strip }

  # Rails 8.0 compatible ordering scopes
  scope :ordered, -> { order(arel_table[:order]) }
  scope :by_name, -> { order(arel_table[:name]) }

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

  # Get the effective limit for this dance (considering semi_finals and Event defaults)
  def effective_limit
    return 1 if semi_finals?
    limit || Event.current.dance_limit
  end

  def scrutineering(with_explanations: false)
    # Optimized eager loading to prevent N+1 queries
    entries = heats.includes(entry: [:lead, :follow])
    
    # Batch load all scores with a single query
    scores = Score.includes(:heat).where(heat: heats)
    
    # Extract unique values more efficiently
    score_data = scores.pluck(:slot, :judge_id).uniq
    slots = score_data.map(&:first).uniq.sort
    judges = score_data.map(&:last).uniq.sort
    numbers = heats.where.not(number: ..0).distinct.pluck(:number)

    explanations = with_explanations ? {
      setup: [],
      individual_dances: {},
      compilation: [],
      final_results: []
    } : nil

    # Pre-compute entry mappings for better performance
    entry_by_back = {}
    back_by_entry = {}
    unique_entry_ids = Set.new
    entry_by_id = {}
    
    entries.each do |heat|
      back = heat.entry.lead.back
      entry_id = heat.entry_id
      entry_by_back[back] = entry_id
      back_by_entry[entry_id] = back
      unique_entry_ids << entry_id
      entry_by_id[entry_id] ||= heat.entry
    end
    
    # Use actual score slots to determine dance mappings
    # For semi-finals, use slots 1 to heat_length for individual dances
    # If there are 8 or fewer couples, they all dance in slot 1 (semi-finals only)
    # If there are more than 8 couples, finalists dance in slots > heat_length
    unique_entries_count = unique_entry_ids.size
    dance_slots = if unique_entries_count > 8 && heat_length && slots.any? { |slot| slot > heat_length }
      # Finals: use slots > heat_length (only if final scores exist)
      slots.select { |slot| slot > heat_length }
    else
      # Semi-finals or direct finals: use slots 1 to heat_length
      heat_length ? slots.select { |slot| slot <= heat_length } : slots
    end
    
    if explanations
      explanations[:setup] << "Processing #{name} with #{entries.count} entries"
      explanations[:setup] << "Found #{judges.length} judges and #{dance_slots.length} dance slots"
      explanations[:setup] << "Dance slots being used: #{dance_slots.join(', ')}"
    end
    
    # Create dance name mapping based on multi_children and actual slots
    # Pre-load all dance names to avoid N+1
    dance_children = multi_children.includes(:dance).to_a
    dance_names = {}
    dance_children.each_with_index do |child, index|
      # Map to actual slot if available, otherwise use sequential slots
      actual_slot = dance_slots[index] || (index + 1)
      dance_names[actual_slot] = child.dance.name
    end

    # Initialize summary for all backs in one pass
    summary = entry_by_back.keys.to_h { |back| [back, {}] }
    
    # Get rankings for each dance slot
    dance_slots.each do |slot|
      dance_name = dance_names[slot] || "Dance #{slot}"
      if explanations
        rankings, dance_explanation = Heat.rank_placement(numbers, slot, judges.length/2+1, with_explanations: true, entry_map: entry_by_id)
        explanations[:individual_dances][dance_name] = dance_explanation
      else
        rankings = Heat.rank_placement(numbers, slot, judges.length/2+1, entry_map: entry_by_id)
      end
      rankings.each do |entry, rank|
        summary[entry.lead.back][dance_name] = rank
      end
    end

    # Filter summary to only include couples who have complete results (were called back to finals)
    finalists_summary = summary.select { |back, dance_results| !dance_results.empty? }
    
    if explanations
      explanations[:compilation] << "Identified #{finalists_summary.count} finalists with complete results"
    end
    
    # Only rank the finalists among themselves
    if finalists_summary.any?
      majority = judges.length * dance_slots.length / 2 + 1
      if explanations
        ranks, compilation_explanation = Heat.rank_summaries(finalists_summary, numbers, dance_slots, majority, with_explanations: true)
        explanations[:compilation] += compilation_explanation
        ranks = ranks.to_a.sort.to_h
      else
        ranks = Heat.rank_summaries(finalists_summary, numbers, dance_slots, majority).to_a.sort.to_h
      end
    else
      ranks = {}
    end

    # Build final results using pre-computed mappings
    summary_by_entry_id = {}
    ranks_by_entry_id = {}
    
    # Only include finalists in the results
    finalists_summary.each do |back, dances|
      if entry_id = entry_by_back[back]
        summary_by_entry_id[entry_id] = dances
      end
    end
    
    ranks.each do |back, rank|
      if entry_id = entry_by_back[back]
        ranks_by_entry_id[entry_id] = rank
      end
    end

    if explanations
      explanations[:final_results] << "Final rankings determined for #{ranks.count} competitors"
      return [summary_by_entry_id, ranks_by_entry_id, explanations]
    else
      return [summary_by_entry_id, ranks_by_entry_id]
    end
  end
end
