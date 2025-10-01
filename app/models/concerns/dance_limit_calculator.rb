# Centralized logic for calculating and validating dance limits
module DanceLimitCalculator
  extend ActiveSupport::Concern

  module ClassMethods
    # Check if Open and Closed categories should be combined
    def combined_categories?
      Event.current.heat_range_cat == 1
    end

    # Get the effective category name for limit checking
    def effective_category(category)
      combined_categories? && %w[Open Closed].include?(category) ? 'Open/Closed' : category
    end

    # Calculate heat counts for a person in a specific dance
    # Returns hash with keys: :lead_counts, :follow_counts, :combined_counts
    def calculate_heat_counts_for_person(person_id, dance_id, exclude_entry_id: nil)
      # Get all entries for this person (as lead or follow)
      entry_scope = Entry.where(lead_id: person_id).or(Entry.where(follow_id: person_id))
      entry_scope = entry_scope.where.not(id: exclude_entry_id) if exclude_entry_id
      entry_ids = entry_scope.pluck(:id)

      # Count heats by category for lead and follow positions
      lead_counts = Heat.joins(:entry)
                        .where(entry: { lead_id: person_id }, dance_id: dance_id)
                        .where(entry_id: entry_ids)
                        .where(category: ['Closed', 'Open'])
                        .where('heats.number >= 0')
                        .group(:category)
                        .count

      follow_counts = Heat.joins(:entry)
                          .where(entry: { follow_id: person_id }, dance_id: dance_id)
                          .where(entry_id: entry_ids)
                          .where(category: ['Closed', 'Open'])
                          .where('heats.number >= 0')
                          .group(:category)
                          .count

      # Calculate combined counts
      combined_counts = {}
      if combined_categories?
        # Combine Open and Closed when heat_range_cat == 1
        combined_lead = (lead_counts['Open'] || 0) + (lead_counts['Closed'] || 0)
        combined_follow = (follow_counts['Open'] || 0) + (follow_counts['Closed'] || 0)
        combined_counts['Open/Closed'] = [combined_lead, combined_follow].max
      else
        # Keep separate counts for each category
        (lead_counts.keys + follow_counts.keys).uniq.each do |category|
          combined_counts[category] = [(lead_counts[category] || 0), (follow_counts[category] || 0)].max
        end
      end

      {
        lead_counts: lead_counts,
        follow_counts: follow_counts,
        combined_counts: combined_counts
      }
    end

    # Check if adding heats would violate limit for a person
    # Returns nil if no violation, or hash with violation details
    def check_limit_violation(person_id, dance, category, additional_heats: 0, exclude_entry_id: nil)
      return nil unless person_id && dance

      # Get the effective limit for this dance
      effective_limit = dance.effective_limit
      return nil unless effective_limit

      # Calculate current counts
      counts = calculate_heat_counts_for_person(person_id, dance.id, exclude_entry_id: exclude_entry_id)

      # Determine which count to check
      check_category = effective_category(category)
      current_count = counts[:combined_counts][check_category] || 0
      new_total = current_count + additional_heats

      if new_total > effective_limit
        {
          person_id: person_id,
          dance: dance.name,
          dance_id: dance.id,
          category: check_category,
          current_count: current_count,
          additional_heats: additional_heats,
          total_count: new_total,
          limit: effective_limit,
          excess: new_total - effective_limit
        }
      else
        nil
      end
    end

    # Get all people with heats for a specific dance, with counts
    def people_with_heats_for_dance(dance)
      results = []

      # Get all people who have heats for this dance
      people = Person.joins('JOIN entries ON people.id = entries.lead_id OR people.id = entries.follow_id')
                    .joins('JOIN heats ON entries.id = heats.entry_id')
                    .where(heats: { dance_id: dance.id })
                    .distinct

      people.find_each do |person|
        counts = calculate_heat_counts_for_person(person.id, dance.id)

        if combined_categories?
          # Single combined entry for Open/Closed
          total = (counts[:lead_counts]['Open'] || 0) + (counts[:lead_counts]['Closed'] || 0) +
                  (counts[:follow_counts]['Open'] || 0) + (counts[:follow_counts]['Closed'] || 0)

          if total > 0
            results << {
              person: person,
              category: 'Open/Closed',
              total_count: total,
              lead_count: (counts[:lead_counts]['Open'] || 0) + (counts[:lead_counts]['Closed'] || 0),
              follow_count: (counts[:follow_counts]['Open'] || 0) + (counts[:follow_counts]['Closed'] || 0)
            }
          end
        else
          # Separate entries for each category
          all_categories = (counts[:lead_counts].keys + counts[:follow_counts].keys).uniq
          all_categories.each do |category|
            lead_count = counts[:lead_counts][category] || 0
            follow_count = counts[:follow_counts][category] || 0
            total = lead_count + follow_count

            if total > 0
              results << {
                person: person,
                category: category,
                total_count: total,
                lead_count: lead_count,
                follow_count: follow_count
              }
            end
          end
        end
      end

      results
    end

    # Find all dance limit violations across the event
    def find_all_violations
      violations = []

      Dance.find_each do |dance|
        effective_limit = dance.effective_limit
        next unless effective_limit

        people_data = people_with_heats_for_dance(dance)
        people_data.each do |data|
          if data[:total_count] > effective_limit
            violations << {
              person: data[:person].name,
              person_id: data[:person].id,
              role: 'On Floor',
              dance: dance.name,
              dance_id: dance.id,
              category: data[:category],
              count: data[:total_count],
              limit: effective_limit,
              excess: data[:total_count] - effective_limit,
              is_custom_limit: dance.limit.present?,
              lead_count: data[:lead_count],
              follow_count: data[:follow_count]
            }
          end
        end
      end

      violations
    end

    # Batch load all heat counts for multiple people and dances (optimized)
    def batch_load_heat_counts(person_ids, dance_ids)
      # Single query to get all relevant heat counts
      heat_data = Heat.joins(:entry)
                      .where(dance_id: dance_ids)
                      .where(
                        'entries.lead_id IN (?) OR entries.follow_id IN (?)',
                        person_ids, person_ids
                      )
                      .where(category: ['Closed', 'Open'])
                      .where('heats.number >= 0')
                      .group(:dance_id, 'entries.lead_id', 'entries.follow_id', :category)
                      .count

      # Transform into nested hash structure
      counts_by_person_dance = {}

      heat_data.each do |(dance_id, lead_id, follow_id, category), count|
        # Track for lead
        if person_ids.include?(lead_id)
          counts_by_person_dance[lead_id] ||= {}
          counts_by_person_dance[lead_id][dance_id] ||= { lead: {}, follow: {} }
          counts_by_person_dance[lead_id][dance_id][:lead][category] ||= 0
          counts_by_person_dance[lead_id][dance_id][:lead][category] += count
        end

        # Track for follow
        if person_ids.include?(follow_id)
          counts_by_person_dance[follow_id] ||= {}
          counts_by_person_dance[follow_id][dance_id] ||= { lead: {}, follow: {} }
          counts_by_person_dance[follow_id][dance_id][:follow][category] ||= 0
          counts_by_person_dance[follow_id][dance_id][:follow][category] += count
        end
      end

      counts_by_person_dance
    end
  end
end