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

    # Note: my read of the rules is that there is a tie for third place:
    #
    # * Having placed the first 4 places we must now award 5th place. #105 and
    #   #106 have the same total so we count “5th and higher” places for the
    #   two couples.
    #
    # * If the two couples have the same number of places and the same total
    #   you do not go to the lower places to break the tie.
    #
    # So:
    #  103 has a second place, and 104 has a third place, so both have exactly
    #  one "3rd and higher" place.
    #
    # Note:
    #  If we ignore the rule to start at the nth place, and instead always
    #  start at the first place, then 10B should place couple 106 as 5th
    #  as both 105 and 106 have a single 3rd place finishing, but only
    #  couple 106 has a fourth.

    "10A" => {
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
        104 => 3,
        105 => 5,
        106 => 6,
      }
    },

    "10B" => {
      places: {
        101 => {w: 1, t: 6, f: 4, q: 1},
        102 => {w: 6, t: 2, f: 2, q: 2},
        103 => {w: 2, t: 1, f: 6, q: 3},
        104 => {w: 3, t: 4, f: 1, q: 4},
        105 => {w: 5, t: 3, f: 5, q: 5},
        106 => {w: 4, t: 5, f: 3, q: 6},
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

  final_example = {
    waltz: {
      a: {111 => 2, 112 => 6, 113 => 8, 114 => 7, 115 => 1, 116 => 4, 117 => 5, 118 => 3},
      b: {111 => 5, 112 => 8, 113 => 3, 114 => 4, 115 => 1, 116 => 2, 117 => 7, 118 => 6},
      c: {111 => 6, 112 => 1, 113 => 2, 114 => 3, 115 => 5, 116 => 4, 117 => 8, 118 => 7},
      d: {111 => 6, 112 => 5, 113 => 8, 114 => 3, 115 => 2, 116 => 1, 117 => 7, 118 => 4},
      e: {111 => 4, 112 => 7, 113 => 8, 114 => 2, 115 => 6, 116 => 1, 117 => 3, 118 => 5},
    },
    tango: {
      a: {111 => 3, 112 => 7, 113 => 8, 114 => 6, 115 => 1, 116 => 5, 117 => 2, 118 => 4},
      b: {111 => 6, 112 => 8, 113 => 5, 114 => 3, 115 => 1, 116 => 2, 117 => 7, 118 => 4},
      c: {111 => 5, 112 => 3, 113 => 4, 114 => 1, 115 => 2, 116 => 6, 117 => 7, 118 => 8},
      d: {111 => 5, 112 => 8, 113 => 6, 114 => 3, 115 => 4, 116 => 2, 117 => 7, 118 => 1},
      e: {111 => 4, 112 => 7, 113 => 8, 114 => 3, 115 => 5, 116 => 2, 117 => 1, 118 => 6},
    },
    summary: {
      111 => {waltz: 4, tango: 5},
      112 => {waltz: 6, tango: 8},
      113 => {waltz: 8, tango: 6},
      114 => {waltz: 3, tango: 3},
      115 => {waltz: 2, tango: 1},
      116 => {waltz: 1, tango: 2},
      117 => {waltz: 7, tango: 7},
      118 => {waltz: 5, tango: 4},
    },
    ranks: {
      111 => 4,
      112 => 6,
      113 => 7,
      114 => 3,
      115 => 1,
      116 => 2,
      117 => 8,
      118 => 5,
    }
  }

  test "rule 11" do
    # create judges
    staff = Studio.find(0)
    judges = {}
    final_example[:waltz].keys.each do |name|
      judges[name] = Person.create!(name: name, type: "Judge", studio: staff)
    end

    # create entries, heats, and scores
    studio = studios(:one)
    leaders = {}
    heats = {waltz: 100, tango: 101}
    heats.map do |dance, heat_number|
      final_example[dance].values.map(&:keys).flatten.uniq.sort.each do |back_number|
        leaders[back_number] ||= Person.create(name: back_number, type: "Leader", studio: studio, back: back_number)

        entry = Entry.find_or_create_by!(
          lead: leaders[back_number],
          follow: people(:Kathryn),
          instructor: people(:Arthur),
          age: ages(:A),
          level: levels(:FB)
        )

        heat = Heat.create!(
          number: heat_number,
          entry: entry,
          dance: dances(dance),
        )

        final_example[dance].each do |judge_name, scores|
          judge = judges[judge_name]
          Score.create!(heat_id: heat.id, judge_id: judge.id, value: scores[back_number])
        end
      end
    end

    summary = leaders.values.map {|leader| [leader.back, {}]}.to_h
    %i(waltz tango).each do |dance|
      Heat.rank_placement(heats[dance], judges.keys.length/2+1).each do |entry, rank|
        summary[entry.lead.back][dance] = rank
      end
    end

    assert_equal final_example[:summary], summary

    ranks = Heat.rank_summaries(summary, heats.values).to_a.sort.to_h

    # assert_equal final_example[:ranks], ranks
  end
end
