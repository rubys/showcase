# frozen_string_literal: true

# Shared module for prerender configuration logic used by:
# - lib/tasks/prerender.rake
# - app/controllers/concerns/configurator.rb
#
# This module defines which paths should be prerendered as static files.
# Prerendered paths must be:
# 1. Public (no authentication required)
# 2. Served locally from all regions (excluded from fly-replay)
#
# The critical distinction is between:
# - Multi-event studios (with :events key) → prerendered index pages
# - Single-tenant studios (no :events key) → NO prerendered index pages
module PrerenderConfiguration
  extend self

  # Returns structured data about what should be prerendered
  #
  # @param showcases [Hash] The showcases.yml data
  # @return [Hash] Structure:
  #   {
  #     regions: ["iad", "ewr", ...],
  #     studios: ["boston", "seattle", ...],
  #     years: [2023, 2024, 2025, ...],
  #     multi_event_studios: {
  #       2025 => ["raleigh", "boston"],
  #       2024 => ["seattle", "portland"]
  #     }
  #   }
  def prerenderable_paths(showcases)
    regions = Set.new
    studios = {}
    years = Set.new
    multi_event_studios = {}

    showcases.each do |year, sites|
      years << year

      sites.each do |token, info|
        # Collect all regions and studios
        regions << info[:region] if info[:region]
        studios[token] = info[:region] if info[:region]

        # Only studios with :events get prerendered index pages
        if info[:events]
          multi_event_studios[year] ||= []
          multi_event_studios[year] << token
        end
      end
    end

    {
      regions: regions.to_a.sort,
      studios: studios.keys.sort,
      years: years.to_a.sort,
      multi_event_studios: multi_event_studios
    }
  end

  # Check if a specific studio in a specific year has a prerendered index
  #
  # @param year [Integer] The year
  # @param studio [String] The studio token
  # @param showcases [Hash] The showcases.yml data
  # @return [Boolean] true if the studio has :events (prerendered index)
  def prerendered_index?(year, studio, showcases)
    showcases.dig(year, studio, :events).present?
  end

  # Group studios by region and type for fly-replay configuration
  # Returns data needed to generate correct fly-replay patterns
  #
  # @param showcases [Hash] The showcases.yml data
  # @param current_region [String] The current region (to exclude from results)
  # @return [Hash] Structure:
  #   {
  #     "iad" => {
  #       multi_event: { 2025 => ["raleigh"], 2024 => ["annapolis"] },
  #       single_tenant: { 2025 => ["kennesaw"], 2023 => ["charlotte"] }
  #     }
  #   }
  def studios_by_region_and_type(showcases, current_region = nil)
    regions = {}

    showcases.each do |year, sites|
      sites.each do |token, info|
        site_region = info[:region]
        next unless site_region
        next if current_region && site_region == current_region

        regions[site_region] ||= {
          multi_event: {},   # Studios with :events (prerendered indexes)
          single_tenant: {}  # Studios without :events (no prerendered indexes)
        }

        if info[:events]
          regions[site_region][:multi_event][year] ||= []
          regions[site_region][:multi_event][year] << token
        else
          regions[site_region][:single_tenant][year] ||= []
          regions[site_region][:single_tenant][year] << token
        end
      end
    end

    regions
  end

  # Get list of all regions from showcases
  #
  # @param showcases [Hash] The showcases.yml data
  # @return [Array<String>] Sorted list of region codes
  def all_regions(showcases)
    regions = Set.new
    showcases.each do |_year, sites|
      sites.each do |_token, info|
        regions << info[:region] if info[:region]
      end
    end
    regions.to_a.sort
  end
end
