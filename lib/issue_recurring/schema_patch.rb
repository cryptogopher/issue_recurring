module IssueRecurring
  module SchemaPatch
    # TODO: replace arguments with argument forwarding (info, ...) in Ruby 3.0
    def define(info, &block)
      super

      info.except(:version).each do |id, v|
        connection.assume_plugin_migrated_upto_version(id, v)
      end
    end
  end
end
