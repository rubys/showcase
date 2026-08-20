# Describes how raw judge scores roll up into the standings reports
# (scores by level, by age, by studio, and the instructor summary).
#
# Each report renders one column group -- a "bucket" -- per separately scored
# heat category, Closed first and then Open.  When closed heats follow the open
# style (see Event#closed_follows_open?) there is a single Open bucket.
#
# A bucket knows the ordinal alphabet its judges use, best score first, and what
# each position is worth.  Callers hand it a raw score value plus the category
# of the heat it came from and get back which bucket it belongs to, which column
# within that bucket, and how many points it contributes.
class ScoreTabulator
  # Ordinal scoring styles: column headers (best first) and the points each
  # position earns.  Styles absent from this table contribute no columns:
  # '#' scores as a raw number, '+' and '@' collect feedback instead of points.
  ORDINAL_STYLES = {
    '1' => { headers: %w(1 2 3 F),   weights: [5, 3, 2, 1] },
    'G' => { headers: %w(GH G S B),  weights: [5, 3, 2, 1] },
    '&' => { headers: %w(5 4 3 2 1), weights: [5, 4, 3, 2, 1] }
  }.freeze

  NUMERIC_STYLE = '#'

  # Buckets are rendered in this order, and probed in this order when folding in
  # scores from categories that have no bucket of their own (see #tabulate).
  DISPLAY_ORDER = %w(Closed Open).freeze

  # Categories with no bucket of their own whose scores still belong in the
  # tables.  Multi heats are placed on the same 1/2/3/F or GH/G/S/B scale as
  # open and closed heats, so their scores fold in.  Solo heats are scored out
  # of 100 (or in four parts), a scale these tables cannot represent, so they
  # are left out.
  FOLD_IN_CATEGORIES = %w(Multi).freeze

  Bucket = Struct.new(:category, :style, :headers, :weights, keyword_init: true) do
    # Ordinal styles get one column per possible score; '#', '+' and '@' get none.
    def columns? = headers.any?

    def width = headers.length

    def index_of(value) = headers.index(value)

    def numeric? = style == NUMERIC_STYLE

    # Closed columns are shaded to set them apart from the open ones.
    def shaded? = category == 'Closed'
  end

  attr_reader :event, :buckets

  def initialize(event)
    @event = event
    categories = event.closed_follows_open? ? %w(Open) : DISPLAY_ORDER
    @buckets = categories.map { |category| build_bucket(category) }
    @by_category = @buckets.index_by(&:category)
  end

  # The bucket a heat in the given category reports into, or nil for categories
  # that have none of their own.
  def bucket_for(category)
    category = 'Open' if category == 'Closed' && event.closed_follows_open?
    @by_category[category]
  end

  # Are there any score columns to render?  When false the reports show points
  # only -- either because scoring is purely numeric or purely feedback.
  def columns? = @buckets.any?(&:columns?)

  # Should the reports print a header row naming each bucket?  Only worth it
  # when open and closed are shown side by side.
  def labeled? = @buckets.count(&:columns?) > 1

  # Do any buckets earn points?  False when every scored category collects
  # feedback only, in which case there are no standings to show.
  def points? = @buckets.any? { |bucket| bucket.columns? || bucket.numeric? }

  # A fresh set of per-bucket counters, keyed by bucket category.
  def empty_counts
    @buckets.to_h { |bucket| [bucket.category, Array.new(bucket.width, 0)] }
  end

  # Where a score lands in the reports.  Returns a hash of the bucket category,
  # the column index within it (nil when the bucket has no columns), and the
  # points earned -- or nil when the score does not belong in the tables at all.
  #
  # Open and Closed heats report into their own bucket.  Multi heats have no
  # bucket of their own, so they are probed against each bucket in turn and land
  # in the first whose alphabet recognizes the value.  Everything else -- solos
  # above all -- is left out.
  def tabulate(value, category)
    return nil if value.blank?

    if (bucket = bucket_for(category))
      score_in(bucket, value)
    elsif FOLD_IN_CATEGORIES.include?(category)
      @buckets.filter_map { |candidate| score_in(candidate, value) }.first
    end
  end

  private

  def build_bucket(category)
    style = event.scoring_for(category)
    ordinal = ORDINAL_STYLES[style] || { headers: [], weights: [] }

    Bucket.new(
      category: category,
      style: style,
      headers: ordinal[:headers],
      weights: ordinal[:weights]
    )
  end

  def score_in(bucket, value)
    if bucket.numeric?
      { category: bucket.category, index: nil, points: value.to_i }
    elsif (index = bucket.index_of(value))
      { category: bucket.category, index: index, points: bucket.weights[index] }
    end
  end
end
