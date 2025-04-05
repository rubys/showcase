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
    },

    6 => {
      places: {
        a: {61 => 1, 62 => 6, 63 => 2, 64 => 3, 65 => 4, 66 => 5},
        b: {61 => 1, 62 => 2, 63 => 4, 64 => 3, 65 => 5, 66 => 6},
        c: {61 => 2, 62 => 1, 63 => 3, 64 => 5, 65 => 6, 66 => 4},
        d: {61 => 1, 62 => 5, 63 => 3, 64 => 2, 65 => 4, 66 => 6},
        e: {61 => 4, 62 => 2, 63 => 6, 64 => 1, 65 => 3, 66 => 5},
        f: {61 => 2, 62 => 1, 63 => 3, 64 => 5, 65 => 6, 66 => 4},
        g: {61 => 1, 62 => 2, 63 => 3, 64 => 4, 65 => 5, 66 => 6},
       },
       results: {
          61 => 1,
          62 => 2,
          63 => 3,
          64 => 4,
          65 => 5,
          66 => 6,
       }
    },

    7 => {
      places: {
        a: {71 => 3, 72 => 2, 73 => 1, 74 => 5, 75 => 4, 76 => 6},
        b: {71 => 1, 72 => 2, 73 => 5, 74 => 4, 75 => 6, 76 => 3},
        c: {71 => 6, 72 => 1, 73 => 4, 74 => 2, 75 => 3, 76 => 5},
        d: {71 => 1, 72 => 5, 73 => 2, 74 => 4, 75 => 3, 76 => 6},
        e: {71 => 1, 72 => 3, 73 => 2, 74 => 6, 75 => 5, 76 => 4},
        f: {71 => 2, 72 => 1, 73 => 6, 74 => 5, 75 => 4, 76 => 3},
        g: {71 => 1, 72 => 3, 73 => 2, 74 => 4, 75 => 6, 76 => 5},
      },
      results: {
        71 => 1,
        72 => 2,
        73 => 3,
        74 => 4,
        75 => 5,
        76 => 6,
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
        Heat.rank_placement(heat_number, places.keys.length/2+1).map {|entry, count| [entry.lead.back, count]}.to_h
      )
    end
  end

  summary_examples = {
    9 => {
      places: {
        91 => {w: 1, t: 1, v: 1, f: 1, q: 1},
        92 => {w: 4, t: 2, v: 2, f: 2, q: 2},
        93 => {w: 2, t: 3, v: 3, f: 3, q: 3},
        94 => {w: 5, t: 5, v: 6, f: 4, q: 5},
        95 => {w: 3, t: 4, v: 5, f: 7, q: 7},
        96 => {w: 6, t: 7, v: 4, f: 5, q: 6},
        97 => {w: 7, t: 6, v: 7, f: 6, q: 4},
        98 => {w: 8, t: 8, v: 8, f: 8, q: 8},
      },
      results: {
        91 => 1,
        92 => 2,
        93 => 3,
        94 => 4,
        95 => 5,
        96 => 6,
        97 => 7,
        98 => 8
      }
    },

    10 => {
      places: {
        101 => {w: 1, t: 1, f: 3},
        102 => {w: 2, t: 2, f: 1},
        103 => {w: 6, t: 4, f: 2},
        104 => {w: 5, t: 3, f: 4},
        105 => {w: 4, t: 5, f: 5},
        106 => {w: 3, t: 6, f: 6},
      },
      results: {
        101 => 1,
        102 => 2,
        103 => 3,
        104 => 4,
        105 => 5,
        106 => 6,
      }
    },
  }

  summary_examples.each do |rule, test_data|
    test "rule #{rule}" do

      assert_equal(
        test_data[:results],
        Heat.rank_summaries(test_data[:places])
      )
    end
  end

end
