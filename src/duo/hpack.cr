require "./hpack/*"

module Duo
  module HPack
    include HPACK

    def self.encoder
      HPACK::Encoder.new(
        max_table_size: DEFAULT_HEADER_TABLE_SIZE,
        indexing: HPACK::Indexing::NONE,
        huffman: true
      )
    end

    def self.decoder
      HPACK::Decoder.new(
        max_table_size: DEFAULT_HEADER_TABLE_SIZE
      )
    end
  end
end
