module GnCrossmap
  # Processes data received from the GN Resolver
  class ResultProcessor
    MATCH_TYPES = {
      0 => "No match",
      1 => "Exact string match",
      2 => "Canonical form exact match",
      3 => "Canonical form fuzzy match",
      4 => "Partial canonical form match",
      5 => "Partial canonical form fuzzy match",
      6 => "Genus part match"
    }.freeze

    attr_reader :input, :writer

    def initialize(writer)
      @writer = writer
      @input = {}
    end

    def process(result, original_data)
      @original_data = original_data
      res = rubyfy(result)
      res[:data].each do |d|
        d[:results].nil? ? write_empty_result(d) : write_result(d)
      end
    end

    private

    def rubyfy(result)
      JSON.parse(result, symbolize_names: true)
    end

    def write_empty_result(datum)
      res = @original_data[datum[:supplied_id]]
      res += [MATCH_TYPES[0], datum[:supplied_name_string], nil,
              nil, @input[datum[:supplied_id]][:rank], nil,
              nil, nil, nil]
      @writer.write(res)
    end

    def write_result(datum)
      datum[:results].each do |result|
        @writer.write(compile_result(datum, result))
      end
    end

    def compile_result(datum, result)
      @original_data[datum[:supplied_id]] + new_data(datum, result)
    end

    def new_data(datum, result)
      synonym = result[:current_name_string] ? "synonym" : nil
      [matched_type(result), datum[:supplied_name_string],
       result[:name_string], result[:canonical_form],
       @input[datum[:supplied_id]][:rank], matched_rank(result),
       synonym, result[:current_name_string] || result[:name_string],
       result[:edit_distance], result[:score], result[:taxon_id]]
    end

    def matched_rank(record)
      record[:classification_path_ranks].split("|").last
    end

    def matched_type(record)
      MATCH_TYPES[record[:match_type]]
    end
  end
end
