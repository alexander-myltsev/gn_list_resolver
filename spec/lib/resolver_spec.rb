describe GnCrossmap::Resolver do
  let(:writer) { GnCrossmap::Writer.new(FILES[:output]) }
  subject { GnCrossmap::Resolver.new(writer, 1) }

  describe ".new" do
    it "creates instance" do
      expect(subject).to be_kind_of GnCrossmap::Resolver
    end
  end

  describe "#resolve" do
    let(:data) { GnCrossmap::Reader.new(FILES[:all_fields]).read }

    it "resolves names and writes them into output file" do
      expect(subject.resolve(data))
    end
  end
end
