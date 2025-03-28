require "test_helper"

# https://www.dancepartner.com/articles/dancesport-skating-system.asp

class HeatTest < ActiveSupport::TestCase
  test "rule 1" do
    callbacks = {
      a: [11, 12, 14, 17, 18, 19],
      b: [10, 12, 14, 15, 17, 18],
      c: [10, 11, 13, 15, 17, 18],
      d: [10, 11, 12, 15, 17, 18],
      e: [11, 14, 15, 17, 18, 19],
      f: [10, 11, 13, 14, 15, 18],
      g: [11, 12, 13, 15, 17, 18],
    }

    # create judges
    staff = Studio.find(0)
    judges = {}
    callbacks.keys.each do |name|
      judges[name] = Person.create!(name: name, type: "Judge", studio: staff)
    end

    # create entries, heats, and scores
    studio = studios(:one)
    leaders = []
    heat_number = 100
    callbacks.values.flatten.uniq.sort.each do |back_number|
      leaders[back_number] = Person.create(name: back_number, type: "Leader", studio: studio, back: back_number)

      entry = Entry.create!(
        lead: leaders[back_number],
        follow: people(:Kathryn),
        instructor: people(:Arthur),
        age: ages(:A),
        level: levels(:FB)
      )

      heat = Heat.create!(
        number: heat_number,
        entry: entry,
        dance: dances(:waltz),
      )

      callbacks.each do |judge_name, scores|
        judge = judges[judge_name]
        scores.each do |score|
          next unless score == back_number
          Score.create!(heat_id: heat.id, judge_id: judge.id, value: 1)
        end
      end
    end

    assert_equal [7, 6, 6, 6, 4, 4, 4, 3, 2], Heat.rank_callbacks(heat_number).values
  end

  rule_examples = {
    5 => {
      places: {
        a: {51 => 1, 52 => 4, 53 => 3, 54 => 2, 55 => 5, 56 => 6},
        b: {51 => 1, 52 => 2, 53 => 3, 54 => 4, 55 => 6, 56 => 5},
        c: {51 => 1, 52 => 2, 53 => 3, 54 => 5, 55 => 4, 56 => 6},
        d: {51 => 2, 52 => 1, 53 => 5, 54 => 4, 55 => 3, 56 => 6},
        e: {51 => 1, 52 => 2, 53 => 4, 54 => 3, 55 => 5, 56 => 6},
       },
       results: {
          51 => 1,
          52 => 2,
          53 => 3,
          54 => 4,
          55 => 5,
          56 => 6,
       }
    }
  }

  rule_examples.each do |rule, test_data|
    test "rule #{rule}" do
      places = test_data[:places]

      # create judges
      staff = Studio.find(0)
      judges = {}
      places.keys.each do |name|
        judges[name] = Person.create!(name: name, type: "Judge", studio: staff)
      end

      # create entries, heats, and scores
      studio = studios(:one)
      leaders = []
      heat_number = 200
      places.values.map(&:keys).flatten.uniq.sort.each do |back_number|
        leaders[back_number] = Person.create(name: back_number, type: "Leader", studio: studio, back: back_number)

        entry = Entry.create!(
          lead: leaders[back_number],
          follow: people(:Kathryn),
          instructor: people(:Arthur),
          age: ages(:A),
          level: levels(:FB)
        )

        heat = Heat.create!(
          number: heat_number,
          entry: entry,
          dance: dances(:waltz),
        )

        places.each do |judge_name, scores|
          judge = judges[judge_name]
          Score.create!(heat_id: heat.id, judge_id: judge.id, value: scores[back_number])
        end
      end

      assert_equal(
        test_data[:results],
        Heat.rank_placement(heat_number, 3).map {|entry, count| [entry.lead.back, count]}.to_h
      )
    end
  end

end
