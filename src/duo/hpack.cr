require "./hpack/*"

module Duo
  module HPack
    include HPACK

    def self.encoder
      HPACK::Encoder.new(
        max_table_size: local_settings.header_table_size,
        indexing: HPACK::Indexing::NONE,
        huffman: true
      )
    end

    def self.decoder
      HPACK::Decoder.new(
        max_table_size: remote_settings.header_table_size
      )
    end
  end
end
