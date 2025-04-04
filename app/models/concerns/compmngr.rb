module Compmngr
  AGE_MAP = {
    "JR" => "J",
    "A" => "A",
    "A*" => "A1",
    "B" => "B",
    "B*" => "B1",
    "C" => "C",
    "C " => "C",
    "C*" => "C1",
    "C *" => "C1",
    "D" => "D"
  }

  def import_from_compmngr(spreadsheet)
    event = self.is_a?(Event) ? self : Event.first

    event.update!(include_closed: false, pro_heats: true)

    heat = nil
    level = nil
    dance = nil
    song = nil
    solo = false
    formation = nil
    ballroom = nil

    dances = Set.new
    studios = Set.new
    people = Hash.new {|k, v| k[v] = {} }
    heats = []
    categories = []
    current_category = Set.new

    multis = Set.new

    spreadsheet.each do |line|  
      if line[0] =~ /^
        Heat\s(\d+)\s\[.*?\]\s*
        (?:Sat\.\s*)?
        (Newcomer|Bronze\s\d|Silver\s\d|Gold\s\d|Advanced|(?:Associate|Full)\s(?:Bronze|Silver|Gold))?\s*
        (?:Sat\.\s*)?
        (.*)
      /x
        heat = $1.to_i
        level = $2
        dance = $3
        song = nil
        solo = false
        formation = nil
        combo = nil
        ballroom = nil

        if dance =~ /\(([A-Z]+\/+\w+)\)$/
          multis.add($1)
        elsif dance =~ /^(.*?)\s+\((.*)\)$/
          song = $1
          dance = $2
          solo = true
        elsif dance =~ /^\((.*)\)$/
          dance = $1
          solo = true
        end

        if solo
          if dance =~ /(.*?) Trio with (.*)/
            dance = $1
            formation = $2
          elsif dance =~ /(.*?)\/(.*)/
            dance = $1
            combo = $2
          elsif dance =~ /^(.*) - .*$/
            dance = $1
          end
        end

        dances.add(dance) if dance

        next
      end

      if line[0] =~ /^Pro heat (TBD|\d+)\s\[.*?\]\s*(.*)/
        heat = $1.to_i + 500
        dance = $2
        level = 'Pro'
        dances.add(dance) if dance
        next
      end

      next if line[0] =~ /^Heat TBD\s\[.*?\]\s*/

      if line[0] == "___"
        next unless heat
        _, category, back, student, partner, studio = line

        instructor = nil

        if studio =~ /^(.*?) \((.*)\)$/
          studio = $1
          instructor = $2

          people[instructor][:instructor] = true
          people[instructor][:studio] = studio
        end

        studios.add(studio)

        if category =~ /^L-(.*)/
          lead, follow = partner, student
          people[student][:age] = AGE_MAP[$1] || $1
          people[partner][:instructor] = true
        elsif category =~ /^G-(.*)/
          lead, follow = student, partner
          people[student][:age] = AGE_MAP[$1] || $1
          people[partner][:instructor] = true
        elsif category =~ /^AC-(.*)/
          lead, follow = student, partner
          people[student][:age] = AGE_MAP[$1] || $1
          people[partner][:age] ||= AGE_MAP[$1] || $1

          if solo
            people[partner][:level] ||= level if level
          else
            people[partner][:level] = level if level
          end
        elsif level == "Pro"
          lead, follow = student, partner
        else
          p heat
          p line
          next
        end

        people[student][:studio] = studio
        people[partner][:studio] = studio
        people[lead][:lead] = true
        people[lead][:back] = back
        people[follow][:follow] = true

        if solo
          people[student][:level] ||= level if level
        else
          people[student][:level] = level if level
        end

        heats << {
          number: heat,
          level: level,
          dance: dance,
          song: song,
          solo: solo,
          combo: combo,
          ballroom: ballroom,
          formation: formation,
          lead: lead,
          follow: follow,
          instructor: instructor,
          studio: studio,
        }

        current_category.add(heat)
        next
      end

      next if line[0] == nil
      next if line[0].start_with?("......")
      next if line[0].start_with?("------")

      if line[0] =~ /^(Associate|Full)\s(?:Bronze|Silver|Gold)$/
        level = line[0]
        next
      elsif line[0] == "Newcomer"
        level = "Newcomer"
        next
      elsif line[0] == "Advanced"
        level = "Advanced"
        next
      end

      if line[0] =~ /^Ballroom (A|B)\s*(.*)/
        ballroom = $1.upcase
        level = $2 if $2 != ""
        next
      end

      if line[1..].compact.length == 0
        category = line[0].strip.
          sub(/^\[\d+:\d+[AP]M\]\s*/, "").
          sub(/(Saturday|Sunday)\s+/, "").
          sub(/\s*-\s+Part \d$/, "").
          sub(/\s+Continued$/, "")

        break if category == "End of competition"

        current_category = Set.new
        categories.push([category, current_category])
        next
      end

      p line
    end

    multis = multis.to_a.map {|dances| dances.split("/") }.flatten.uniq
    require 'fuzzy_match'
    dances.add("Club Swing")
    matcher = FuzzyMatch.new(dances.to_a)
    multis.each do |dance|
      puts [dance, matcher.find(dance)].join(" => ")
    end

    ages = Age.all.map { |age| [age.category, age] }.to_h

    puts "Levels"
    person_levels = {
      "Newcomer" => Level.find_or_create_by!(name: "Newcomer"),
      "Bronze 1" => Level.find_or_create_by!(name: "Assoc. Bronze"),
      "Bronze 2" => Level.find_or_create_by!(name: "Assoc. Bronze"),
      "Associate Bronze" => Level.find_or_create_by!(name: "Assoc. Bronze"),
      "Bronze 3" => Level.find_or_create_by!(name: "Full Bronze"),
      "Bronze 4" => Level.find_or_create_by!(name: "Full Bronze"),
      "Full Bronze" => Level.find_or_create_by!(name: "Full Bronze"),
      "Silver 1" => Level.find_or_create_by!(name: "Assoc. Silver"),
      "Silver 2" => Level.find_or_create_by!(name: "Assoc. Silver"),
      "Associate Silver" => Level.find_or_create_by!(name: "Assoc. Silver"),
      "Silver 3" => Level.find_or_create_by!(name: "Full Silver"),
      "Silver 4" => Level.find_or_create_by!(name: "Full Silver"),
      "Full Silver" => Level.find_or_create_by!(name: "Full Silver"),
      "Gold 1" => Level.find_or_create_by!(name: "Assoc. Gold"),
      "Gold 2" => Level.find_or_create_by!(name: "Assoc. Gold"),
      "Associate Gold" => Level.find_or_create_by!(name: "Assoc. Gold"),
      "Gold 3" => Level.find_or_create_by!(name: "Full Gold"),
      "Gold 4" => Level.find_or_create_by!(name: "Full Gold"),
      "Full Gold" => Level.find_or_create_by!(name: "Full Gold"),
      "Advanced" => Level.find_or_create_by!(name: "Advanced"),
      "Pro" => Level.find_or_create_by!(name: "Professional"),
    }

    solo_levels = {
      "Newcomer" => Level.find_or_create_by!(name: "Newcomer"),
      "Bronze 1" => Level.find_or_create_by!(name: "Bronze 1"),
      "Bronze 2" => Level.find_or_create_by!(name: "Bronze 2"),
      "Bronze 3" => Level.find_or_create_by!(name: "Bronze 3"),
      "Bronze 4" => Level.find_or_create_by!(name: "Bronze 4"),
      "Silver 1" => Level.find_or_create_by!(name: "Silver 1"),
      "Silver 2" => Level.find_or_create_by!(name: "Silver 2"),
      "Silver 3" => Level.find_or_create_by!(name: "Silver 3"),
      "Silver 4" => Level.find_or_create_by!(name: "Silver 4"),
      "Gold 1" => Level.find_or_create_by!(name: "Gold 1"),
      "Gold 2" => Level.find_or_create_by!(name: "Gold 2"),
      "Gold 3" => Level.find_or_create_by!(name: "Gold 3"),
      "Gold 4" => Level.find_or_create_by!(name: "Gold 4"),
      "Advanced" => Level.find_or_create_by!(name: "Advanced"),
    }

    puts "Studios"
    Studio.where(id: 1..).destroy_all
    studios = studios.compact.sort.map do |studio|
      [studio, Studio.create!(name: studio)]
    end.to_h

    puts "Dances"
    Dance.destroy_all
    order = 0
    dances = dances.sort.map do |dance|
      order += 1
      [dance, Dance.create!(name: dance, order: order)]
    end.to_h

    puts "Categories"
    cat_map = {}
    Category.destroy_all

    if categories.length > 1 && categories[0][1].length == 0
      name, _ = categories.shift

      event.update!(name: name.split(' - ').first)
    end

    categories.each_with_index do |(name, heats), index|
      next if name.include?(" - ") && name.split(' - ').first == event.name

      category = Category.find_by(name: name)

      if category
        extension = CatExtension.create!(
          category: category,
          start_heat: heats.to_a.min,
          order: index+1,
          part: category.extensions.length + 2
        )
      else
        split = nil

        parts = categories.select { |cat, _| cat == name }
        if parts.length > 1
          split = parts.map { |cat, heats| heats.length }.join(" ")
        end

        category = Category.create!(
          name: name,
          order: index+1,
          split: split,
        )
      end

      heats.each do |number|
        cat_map[number] = category
      end
    end

    puts "People"
    Person.destroy_all
    people.each do |name, person|
      person[:instructor] = true unless person[:level]

      person[:name] = name
      person[:studio] = studios[person[:studio]] if person[:studio]
      person[:age] = ages[person[:age]] if person[:age]
      person[:level] = person_levels[person[:level]] if person[:level]

      if person[:instructor]
        person[:type] = "Professional"
      else
        person[:type] = "Student"
      end

      if not person[:lead]
        person[:role] = "Follower"
      elsif not person[:follow]
        person[:role] = "Leader"
      else
        person[:role] = "Both"
      end

      person.delete(:lead)
      person.delete(:follow)
      person.delete(:instructor)

      people[name] = Person.create!(person)
    end

    Heat.destroy_all
    Solo.destroy_all
    Formation.destroy_all
    Entry.destroy_all

    solo_order = 0
    heats.each do |heat|
      p heat
      lead = people[heat[:lead]]
      follow = people[heat[:follow]]
      instructor = people[heat[:instructor]] if heat[:instructor]

      if heat[:solo]
        level = solo_levels[heat[:level]]
        category = "Solo"
      else
        level = person_levels[heat[:level]]
        category = "Open"
      end

      if !instructor && lead.type == "Student" && follow.type == "Student"
        instructor = Person.where(studio: lead.studio, type: "Professional").first
      end

      entry = Entry.find_or_create_by!(
        lead: lead,
        follow: follow,
        instructor: instructor,
        age: heat[:age] || lead.age || follow.age || Age.first,
        level: level || lead.level || follow.level,
      )

      cat = cat_map[heat[:number]]
      dance = dances[[cat, heat[:dance]]] || dances[heat[:dance]]
      if category == "Open"
        if dance.open_category_id.nil?
          dance.update(open_category: cat)
        elsif dance.open_category_id != cat.id
          dance = Dance.create!(
            name: heat[:dance],
            open_category: cat,
            order: [Dance.minimum(:order), 0].min - 1
          )
          dances[[cat, heat[:dance]]] = dance
        end
      elsif category == "Closed"
        if dance.closed_category_id.nil?
          dance.update(closed_category: cat)
        elsif dance.closed_category_id != cat.id
          dance = Dance.create!(
            name: heat[:dance],
            closed_category: cat,
            order: [Dance.minimum(:order), 0].min - 1
          )
          dances[[cat, heat[:dance]]] = dance
        end
      elsif category == "Solo"
        if dance.solo_category_id.nil?
          dance.update(solo_category: cat)
        elsif dance.solo_category_id != cat.id
          dance = Dance.create!(
            name: heat[:dance],
            solo_category: cat,
            order: [Dance.minimum(:order), 0].min - 1
          )

          dances[[cat, heat[:dance]]] = dance
        end   
      end

      heat = Heat.create!(
        category: category,
        entry: entry,
        number: heat[:number],
        ballroom: heat[:ballroom].blank? ? nil : heat[:ballroom],
        dance: dance,
      )

      if category == "Solo"
        solo_order += 1

        solo = Solo.create!(
          heat: heat,
          order: solo_order,
        )

        if heat[:formation]
          Formation.create(
            solo: solo,
            person: Person.find_by(name: heat[:formation])
          )
        end
      end
    end
  end
end
