module BatchApi
  class << self
    attr_writer :logger
    def logger
      @logger ||= Logger.new('STDOUT').tap do |log|
        log.progname = self.name
      end
    end
  end
end
