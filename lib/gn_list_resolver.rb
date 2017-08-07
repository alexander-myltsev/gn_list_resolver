# frozen_string_literal: true

require "csv"
require "ostruct"
require "rest_client"
require "tempfile"
require "logger"
require "logger/colors"
require "pp"
require "biodiversity"
require "gn_uuid"
require "graphql/client"
require "graphql/client/http"
require "gn_list_resolver/constants"
require "gn_list_resolver/graphql"
require "gn_list_resolver/errors"
require "gn_list_resolver/version"
require "gn_list_resolver/reader"
require "gn_list_resolver/writer"
require "gn_list_resolver/collector"
require "gn_list_resolver/column_collector"
require "gn_list_resolver/sci_name_collector"
require "gn_list_resolver/resolver"
require "gn_list_resolver/result_processor"
require "gn_list_resolver/stats"

# Namespace module for resolving lists with GN sources
module GnListResolver
  class << self
    attr_writer :logger

    # rubocop:disable Metrics/AbcSize

    def run(opts)
      opts = opts_struct(opts)
      input_io, output_io = io(opts.input, opts.output)
      reader = create_reader(input_io, opts)
      data = block_given? ? reader.read(&Proc.new) : reader.read
      writer = create_writer(reader, output_io, opts)
      resolver = create_resolver(writer, opts)
      block_given? ? resolver.resolve(data, &Proc.new) : resolver.resolve(data)
      logger.warn(resolver.stats.stats.pretty_inspect) if opts[:debug]
      resolver.stats
    end

    # rubocop:enable all

    def logger
      @logger ||= Logger.new(STDERR)
    end

    def log(message)
      logger.info(message)
    end

    def find_id(row, name)
      if row.key?(:taxonid) && row[:taxonid]
        row[:taxonid].to_s.strip
      else
        GnUUID.uuid(name.to_s)
      end
    end

    private

    def create_resolver(writer, opts)
      Resolver.new(writer, opts.data_source_id,
                   opts.stats, opts.with_classification)
    end

    def create_writer(reader, output_io, opts)
      Writer.new(output_io, reader.original_fields,
                 output_name(opts.output), opts.with_classification)
    end

    def create_reader(input_io, opts)
      Reader.new(input_io, input_name(opts.input),
                 opts.skip_original, opts.alt_headers, opts.stats)
    end

    def opts_struct(opts)
      OpenStruct.new({ stats: Stats.new, alt_headers: [] }.merge(opts))
    end

    def io(input, output)
      io_in = iogen(input, INPUT_MODE)
      io_out = iogen(output, OUTPUT_MODE)
      [io_in, io_out]
    end

    def iogen(arg, mode)
      if arg.nil? || arg == "-"
        mode == INPUT_MODE ? stdin : STDOUT
      else
        fd_i = IO.sysopen(arg, mode)
        IO.new(fd_i, mode)
      end
    end

    def stdin
      temp = Tempfile.open("stdin")
      return STDIN if File.file?(STDIN)
      IO.copy_stream(STDIN, temp)
      fd_i = IO.sysopen(temp, INPUT_MODE)
      IO.new(fd_i, INPUT_MODE)
    end

    def input_name(input)
      input.nil? || input == "-" ? "STDIN" : input
    end

    def output_name(output)
      output.nil? || output == "-" ? "STDOUT" : output
    end
  end
end
