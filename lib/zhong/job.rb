module Zhong
  class Job
    attr_reader :name, :category

    def initialize(scheduler:, name:, every: nil, at: nil, only_if: nil, category: nil, &block)
      @name = name
      @category = category

      @at = At.parse(at, grace: scheduler.config[:grace])
      @every = Every.parse(every)

      if @at && !@every
        @logger.error "warning: #{self} has `at` but no `every`; could run far more often than expected!"
      end

      @block = block
      @redis = scheduler.config[:redis]
      @logger = scheduler.config[:logger]
      @tz = scheduler.config[:tz]
      @if = only_if
      @lock = Suo::Client::Redis.new(lock_key, client: @redis, stale_lock_expiration: scheduler.config[:long_running_timeout])
      @timeout = 5

      refresh_last_ran
    end

    def run?(time = Time.now)
      run_every?(time) && run_at?(time) && run_if?(time)
    end

    def run(time = Time.now)
      return unless run?(time)

      if running?
        @logger.info "already running: #{self}"
        return
      end

      ran_set = @lock.lock do
        refresh_last_ran

        break true unless run?(time)

        if disabled?
          @logger.info "disabled: #{self}"
          break true
        end

        @logger.info "running: #{self}"

        @thread = Thread.new { @block.call } if @block

        ran!(time)
      end

      @logger.info "unable to acquire exclusive run lock: #{self}" unless ran_set
    end

    def stop
      return unless running?
      Thread.new { @logger.error "killing #{self} due to stop" } # thread necessary due to trap context
      @thread.join(@timeout)
      @thread.kill
    end

    def running?
      @thread && @thread.alive?
    end

    def refresh_last_ran
      last_ran_val = @redis.get(run_time_key)
      @last_ran = last_ran_val ? Time.at(last_ran_val.to_i) : nil
    end

    def disable
      @redis.set(disabled_key, "true")
    end

    def enable
      @redis.del(disabled_key)
    end

    def disabled?
      !!@redis.get(disabled_key)
    end

    def to_s
      [@category, @name].compact.join(".")
    end

    private

    def run_every?(time)
      !@last_ran || !@every || @every.next_at(@last_ran) <= time
    end

    def run_at?(time)
      !@at || @at.next_at(time) <= time
    end

    def run_if?(time)
      !@if || @if.call(time)
    end

    def ran!(time)
      @last_ran = time
      @redis.set(run_time_key, @last_ran.to_i)
    end

    def run_time_key
      "zhong:last_ran:#{self}"
    end

    def disabled_key
      "zhong:disabled:#{self}"
    end

    def lock_key
      "zhong:lock:#{self}"
    end
  end
end
