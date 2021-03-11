module ActiveRecord
  module Encryption
    # An +ActiveModel::Type+ that encrypts/decrypts strings of text
    #
    # This is the central piece that connects the encryption system with +encrypts+ declarations in the
    # model classes. Whenever you declare an attribute as encrypted, it configures an +EncryptedAttributeType+
    # for that attribute.
    class EncryptedAttributeType < ::ActiveRecord::Type::Text
      include ActiveModel::Type::Helpers::Mutable

      attr_reader :key_provider, :previous_types, :subtype, :downcase

      def initialize(key_provider: nil, deterministic: false, downcase: false, subtype: ActiveModel::Type::String.new, context: nil, previous_types: [])
        super()
        @key_provider = key_provider
        @deterministic = deterministic
        @downcase = downcase
        @subtype = subtype
        @previous_types = previous_types
        @context = context
      end

      def deserialize(value)
        @subtype.deserialize decrypt(value)
      end

      def serialize(value)
        casted_value = @subtype.serialize(value)
        casted_value = casted_value&.downcase if @downcase
        encrypt(casted_value.to_s) unless casted_value.nil? # Object values without a proper serializer get converted with #to_s
      end

      def changed_in_place?(raw_old_value, new_value)
        old_value = raw_old_value.nil? ? nil : deserialize(raw_old_value)
        old_value != new_value
      end

      def deterministic?
        @deterministic
      end

      private
        def decrypt(value)
          with_context do
            encryptor.decrypt(value, **decryption_options) unless value.nil?
          end
        rescue ActiveRecord::Encryption::Errors::Base => error
          if previous_types.blank?
            handle_deserialize_error(error, value)
          else
            try_to_deserialize_with_previous_types(value)
          end
        end

        def try_to_deserialize_with_previous_types(value)
          previous_types.each.with_index do |type, index|
            break type.deserialize(value)
          rescue ActiveRecord::Encryption::Errors::Base => error
            handle_deserialize_error(error, value) if index == previous_types.length - 1
          end
        end

        def handle_deserialize_error(error, value)
          if error.is_a?(Errors::Decryption) && ActiveRecord::Encryption.config.support_unencrypted_data
            value
          else
            raise error
          end
        end

        def encrypt(value)
          with_context do
            encryptor.encrypt(value, **encryption_options)
          end
        end

        def encryptor
          ActiveRecord::Encryption.encryptor
        end

        def encryption_options
          @encryption_options ||= { key_provider: @key_provider, cipher_options: { deterministic: @deterministic } }.compact
        end

        def decryption_options
          @decryption_options ||= { key_provider: @key_provider }.compact
        end

        def with_context(&block)
          if @context
            ActiveRecord::Encryption.with_encryption_context(**@context, &block)
          else
            block.call
          end
        end
    end
  end
end
