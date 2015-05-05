module Zhong
  class Every
    class FailedToParse < StandardError; end

    EVERY_KEYWORDS = {
      day: 1.day,
      week: 1.week,
      month: 1.month,
      semiannual: 6.months, # enterprise!
      year: 1.year,
      decade: 10.year
    }.freeze

    def initialize(period)
      @period = period
    end

    def next_at(last = Time.now)
      last + @period
    end

    def self.parse(every)
      return unless every

      case every
      when Numeric, ActiveSupport::Duration
        new(every)
      when String, Symbol
        key = every.downcase.to_sym

        fail FailedToParse, every unless EVERY_KEYWORDS.key?(key)

        new(EVERY_KEYWORDS[key])
      else
        fail FailedToParse, every
      end
    end
  end
end