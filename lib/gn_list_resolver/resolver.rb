# frozen_string_literal: true

module GnListResolver
  # Sends data to GN Resolver and collects results
  class Resolver
    GRAPHQL = GnGraphQL.new
    QUERY = GRAPHQL.client.parse(GRAPHQL.query)
    attr_reader :stats

    def initialize(writer, opts)
      instance_vars_from_opts(opts)
      @processor = GnListResolver::ResultProcessor.
                   new(writer, @stats, @with_classification)
      @count = 0
      @jobs = []
      @batch = 1000
      @smoothing = 0.05
    end

    def resolve(data)
      resolution_stats(data.size)
      @threads.times do
        batch = data.shift(@batch)
        add_job(batch)
      end
      block_given? ? traverse_jobs(data, &Proc.new) : traverse_jobs(data)
      wrap_up
      block_given? ? yield(@stats.stats) : @stats.stats
    end

    private

    def wrap_up
      @stats.stats[:resolution][:stop_time] = Time.now
      @stats.stats[:status] = :finish
      @processor.writer.close
    end

    def add_job(batch)
      job = batch.empty? ? nil : create_job(batch)
      @jobs << job
    end

    def traverse_jobs(data)
      until data.empty? && @jobs.compact.empty?
        process_results(data)
        cmd = yield(@stats.stats) if block_given?
        break if cmd == "STOP"
        sleep(0.5)
      end
    end

    def resolution_stats(records_num)
      @stats.stats[:total_records] = records_num
      @stats.stats[:resolution][:start_time] = Time.now
      @stats.stats[:status] = :resolution
    end

    def process_results(data)
      indices = []
      @jobs.each_with_index do |job, i|
        next if job.nil? || !job.complete?
        with_log do
          process_job(job)
          indices << i
        end
      end
      add_jobs(indices, data) unless indices.empty?
    end

    def add_jobs(indices, data)
      indices.each do |i|
        batch = data.shift(@batch)
        @jobs[i] = batch.empty? ? nil : create_job(batch)
      end
    end

    def process_job(job)
      if job.fulfilled?
        results, current_data, stats = job.value
        update_stats(stats)
        @processor.process(results, current_data)
      else
        GnListResolver.logger.error(job.reason.message)
      end
    end

    def create_job(batch)
      batch_data = collect_names(batch)
      rb = ResolverJob.new(batch, batch_data, @ds_id)
      Concurrent::Future.execute { rb.run }
    end

    def instance_vars_from_opts(opts)
      @stats = opts.stats
      @with_classification = opts.with_classification.freeze
      @ds_id = opts.data_source_id.freeze
      @threads = opts.threads
    end

    def collect_names(batch)
      batch_data = {}
      batch.each do |row|
        id = row[:id].strip
        batch_data[id] = row[:original]
        @processor.input[id] = { rank: row[:rank] }
      end
      batch_data
    end

    # rubocop:disable Metrics/AbcSize
    def update_stats(job_stats)
      s = @stats.stats
      current_speed = job_stats.stats[:current_speed] *
                      @stats.penalty(@threads)

      s[:resolution][:completed_records] +=
        job_stats.stats[:resolution][:completed_records]
      @stats.update_eta(current_speed)
      s[:resolution][:time_span] = Time.now - s[:resolution][:start_time]
    end

    def with_log
      yield
      s = @count + 1
      @count += @batch
      e = [@count, @stats.stats[:total_records]].min
      eta = @stats.stats[:resolution][:eta].to_i + Time.now.to_i
      msg = format("Resolve %s-%s/%s records %d rec/s; eta: %s", s, e,
                   @stats.stats[:total_records],
                   @stats.stats[:resolution][:speed].to_i,
                   Time.at(eta))
      GnListResolver.log(msg)
    end
  end
end
# rubocop:enable all
